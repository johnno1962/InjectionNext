//
//  FrontendServer.swift
//  InjectionNext
//
//  Created by John Holdsworth on 23/02/2025.
//  Copyright © 2025 John Holdsworth. All rights reserved.
//
//  Code related to "Intercepting" version where the binary
//  swift-frontend is replaced by a script which feeds all
//  compilation commands to the app where they can be reused
//  when a file is injected to recompile individual Swift files.
//
import Cocoa
import Popen

class FrontendServer: SimpleSocket {
    enum State: String {
        case unpatched = "Intercept Compiler"
        case patched = "Unpatch Compiler"
    }

    static var binURL: URL { URL(fileURLWithPath: Defaults.xcodePath +
        "/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin") }
    static var unpatchedURL: URL { binURL.appendingPathComponent("swift-frontend") }
    static var patched: String { unpatchedURL.path + ".save" }
    static var patchedURL: URL { URL(fileURLWithPath: patched) }
    static var loggedFrontend: String?
    static var startOnce: Void = {
        FrontendServer.startServer(COMMANDS_PORT)
    }()

    static var clientPlatform: String {
        InjectionServer.currentClient?.platform ?? "iPhoneSimulator" }
    static func cacheURL(platform: String) -> URL {
        return URL(fileURLWithPath: "/tmp/\(platform)_commands.json")
    }
    static private var recompilers = [String: NextCompiler]()
    static func frontendRecompiler(platform: String = clientPlatform) -> NextCompiler {
        if let recompiler = recompilers[platform] {
            return recompiler
        }
        let recompiler = NextCompiler()
        do {
            let compressed = cacheURL(platform: platform).path+".gz"
            if Fstat(path: compressed)?.st_size ?? 0 != 0,
               let stream = Popen(cmd: "gunzip <"+compressed)?.readAll(),
               let cached = stream.data(using: .utf8) {
                let stored = try JSONDecoder().decode(
                    [String: NextCompiler.Compilation].self, from: cached)
                for source in stored.keys.sorted() {
                    guard let compile = stored[source] else { continue }
                    recompiler.store(compilation: compile, for: source)
                }
                print("Loaded \(recompiler.compilations.count) cached commands")
            }
        } catch {
            InjectionServer.error("Unable to read commands cache: \(error).")
        }
        recompilers[platform] = recompiler
        return recompiler
    }
    static func writeCache(platform: String = clientPlatform) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let cache = cacheURL(platform: platform)
            let commands = frontendRecompiler(platform: platform).compilations
            try encoder.encode(commands).write(to: cache, options: .atomic)
            if let error = Popen.system("gzip -f "+cache.path, errors: true) {
                InjectionServer.error("Unable to zip commands cache: \(error)")
            } else {
                print("Cached \(commands.count) \(platform) commands")
            }
        } catch {
            InjectionServer.error("Unable to write commands cache: \(error)")
        }
    }

    func validateConnection() -> Bool {
        return readInt() == COMMANDS_VERSION && readString() == NSHomeDirectory()
    }

    override func runInBackground() {
        guard validateConnection() && readString() == "1.0" else {
            return _ = Self.frontendRecompiler()
                .error("Unpatch then repatch compiler to update script version")
        }
        do {
            try Self.processFrontendCommandFrom(feed: self)
        } catch {
            Self.error("Feed error: \(error)")
        }
    }
    
    class func processFrontendCommandFrom(feed: SimpleSocket) throws {
        guard let projectRoot = feed.readString(),
              let frontendPath = feed.readString(),
              frontendPath.hasSuffix(".save"),
              feed.readString() == "-frontend" &&
                feed.readString() == "-c" else { return }

        var primaries = [String](), platform = "iPhoneSimulator"
        var compile = NextCompiler.Compilation()

        while let arg = feed.readString() {
            switch arg {
            case "-filelist":
                guard let filelist = feed.readString() else { return }
                let files = try String(contentsOfFile: filelist,
                                       encoding: .utf8)
                compile.swiftFiles += files
            case "-primary-file":
                guard let source = feed.readString() else { return }
                primaries.append(source)
                if !compile.swiftFiles.contains(source) {
                    compile.swiftFiles += source+"\n"
                }
            case "-o":
                _ = feed.readString()
            default:
                if let sdkPlatform: String = arg[#"/([A-Za-z]+)[\d\.]+\.sdk$"#] {
                    platform = sdkPlatform
                }
                if arg.hasSuffix(".swift") && compile.arguments.last != "-F" {
                    compile.swiftFiles += arg+"\n"
                } else if arg[Reloader.optionsToRemove] {
                    _ = feed.readString()
                } else if !(arg == "-F" && compile.arguments.last == "-F") && !arg[
                    "-validate-clang-modules-once|-frontend-parseable-output"] {
                    compile.arguments.append(arg)
                }
            }
        }

        if !projectRoot.hasSuffix(".xcodeproj") &&
            MonitorXcode.runningXcode == nil &&
            AppDelegate.alreadyWatching(projectRoot) == nil {
            DispatchQueue.main.async {
                let open = NSOpenPanel()
//                open.titleVisibility = .visible
//                open.title = "InjectionNext: add directory"
                open.prompt = "InjectionNext - Watch Directory?"
                open.directoryURL = URL(fileURLWithPath: projectRoot)
                open.canChooseDirectories = true
                open.canChooseFiles = false
                if open.runModal() == .OK, let url = open.url {
                    AppDelegate.ui.watch(path: url.path)
                }
            }
        }

        NextCompiler.compileQueue.async {
            let recompiler = Self.frontendRecompiler(platform: platform)
            Self.loggedFrontend = frontendPath

            for source in primaries {
                #if !INJECTION_III_APP
                // Don't update compilations while connected
                if InjectionServer.currentClient != nil &&
                    recompiler.compilations.index(forKey: source) != nil {
                    continue
                }
                #endif

                print("Updating \(compile.arguments.count) args for \(platform)/" +
                      URL(fileURLWithPath: source).lastPathComponent)
                recompiler.store(compilation: compile, for: source)
            }
        }
    }
}

extension AppDelegate {

    @IBAction func patchCompiler(_ sender: NSMenuItem) {
        let fm = FileManager.default
        do {
            let linksToMove = ["swift", "swiftc", "swift-symbolgraph-extract",
                "swift-api-digester", "swift-cache-tool"]
            if updatePatchUnpatch() == .unpatched {
                if !fm.fileExists(atPath: FrontendServer.patched),
                   let feeder = Bundle.main
                    .url(forResource: "swift-frontend", withExtension: "sh") {
                    let alert: NSAlert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = APP_NAME
                    alert.informativeText = """
                        The Swift compiler of your current toolchain \
                        \(FrontendServer.unpatchedURL.path) will be \
                        replaced by a script that calls the compiler \
                        and captures all compilation commands. Use menu \
                        item "Unpatch Compiler" to revert this change.
                        """
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() != .alertFirstButtonReturn {
                        return
                    }
                    try fm.moveItem(at: FrontendServer.unpatchedURL,
                                    to: FrontendServer.patchedURL)
                    try fm.copyItem(at: feeder,
                                    to: FrontendServer.unpatchedURL)
                    for binary in linksToMove {
                        let link = FrontendServer.binURL
                            .appendingPathComponent(binary)
                        try fm.removeItem(at: link)
                        symlink("swift-frontend.save", link.path)
                    }
                }
            } else if fm.fileExists(atPath: FrontendServer.patched) {
                try? fm.removeItem(at: FrontendServer.unpatchedURL)
                try fm.moveItem(at: FrontendServer.patchedURL,
                                to: FrontendServer.unpatchedURL)
                for binary in linksToMove {
                    let link = FrontendServer.binURL
                        .appendingPathComponent(binary)
                    try fm.removeItem(at: link)
                    symlink("swift-frontend", link.path)
                }
                FrontendServer.loggedFrontend = nil
            }
        } catch {
            let chmod = FrontendServer.unpatchedURL.deletingLastPathComponent()
            InjectionServer.error("Patching error: \(error). " +
                                  "Is the directory \(chmod.path) writable?")
        }
        updatePatchUnpatch()
    }

    @discardableResult
    func updatePatchUnpatch() -> FrontendServer.State {
        let state = FileManager.default
            .fileExists(atPath: FrontendServer.patched) ?
            FrontendServer.State.patched : .unpatched
        DispatchQueue.main.async {
            self.patchCompilerItem?.title = state.rawValue
            if state == .patched {
                _ = FrontendServer.startOnce
            }
        }
        return state
    }

    /// Shared regular expresssions to patch .enableInjection() and @ObserveInject into a source
    func prepareSwiftUI(source: String, changes: UnsafeMutablePointer<Int>? = nil) {
        let fileURL = URL(fileURLWithPath: source)
        guard let original = try? String(contentsOf: fileURL) else {
            return
        }

        var patched = original, before = changes?.pointee
        patched[#"""
            ^((\s+)(public )?(var body:|func body\([^)]*\) -\>) some View \{\n\#
            (\2(?!    (if|switch|ForEach) )\s+(?!\.enableInjection)\S.*\n|(\s*|#.+)\n)+)(?<!#endif\n)\2\}\n
            """#.anchorsMatchLines, count: changes] = """
            $1$2    .enableInjection()
            $2}

            $2#if DEBUG
            $2@ObserveInjection var forceRedraw
            $2#endif

            """
        if changes?.pointee != before {
            print("Patched", source)
        }

        if (patched.contains("class AppDelegate") ||
            patched.contains("@main\n")) &&
            !patched.contains("InjectionObserver") {
            if !patched.contains("import SwiftUI") {
                patched += "\nimport SwiftUI\n"
            }

            patched += """

                #if canImport(HotSwiftUI)
                @_exported import HotSwiftUI
                #elseif canImport(Inject)
                @_exported import Inject
                #else
                // This code can be found in the Swift package:
                // https://github.com/johnno1962/HotSwiftUI or
                // https://github.com/krzysztofzablocki/Inject

                #if DEBUG
                import Combine

                public class InjectionObserver: ObservableObject {
                    public static let shared = InjectionObserver()
                    @Published var injectionNumber = 0
                    var cancellable: AnyCancellable? = nil
                    let publisher = PassthroughSubject<Void, Never>()
                    init() {
                        cancellable = NotificationCenter.default.publisher(for:
                            Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
                            .sink { [weak self] change in
                            self?.injectionNumber += 1
                            self?.publisher.send()
                        }
                    }
                }

                extension SwiftUI.View {
                    public func eraseToAnyView() -> some SwiftUI.View {
                        return AnyView(self)
                    }
                    public func enableInjection() -> some SwiftUI.View {
                        return eraseToAnyView()
                    }
                    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
                        return self
                            .onReceive(InjectionObserver.shared.publisher, perform: bumpState)
                            .eraseToAnyView()
                    }
                }

                @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
                @propertyWrapper
                public struct ObserveInjection: DynamicProperty {
                    @ObservedObject private var iO = InjectionObserver.shared
                    public init() {}
                    public private(set) var wrappedValue: Int {
                        get {0} set {}
                    }
                }
                #else
                extension SwiftUI.View {
                    @inline(__always)
                    public func eraseToAnyView() -> some SwiftUI.View { return self }
                    @inline(__always)
                    public func enableInjection() -> some SwiftUI.View { return self }
                    @inline(__always)
                    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
                        return self
                    }
                }

                @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
                @propertyWrapper
                public struct ObserveInjection {
                    public init() {}
                    public private(set) var wrappedValue: Int {
                        get {0} set {}
                    }
                }
                #endif
                #endif

                """
        }

        if patched != original {
            do {
                try patched.write(to: fileURL,
                                  atomically: false, encoding: .utf8)
            } catch {
                InjectionServer.error("Could not save \(source): \(error)")
            }
        }
    }
}
