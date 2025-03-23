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

extension AppDelegate {

    @IBAction func patchCompiler(_ sender: NSMenuItem) {
        let fm = FileManager.default
        do {
            let linksToMove = ["swift", "swiftc", "swift-symbolgraph-extract",
                "swift-api-digester", "swift-cache-tool"]
            if sender.title == FrontendServer.State.unpatched.rawValue {
                if !fm.fileExists(atPath: FrontendServer.patched),
                   let feeder = Bundle.main
                    .url(forResource: "swift-frontend", withExtension: "sh") {
                    InjectionServer.error("""
                        The Swift compiler of your current toolchain \
                        \(FrontendServer.unpatchedURL.path) will be \
                        replaced by a script that calls the compiler \
                        and captures all compilation commands. Use menu \
                        item "Unpatch Compiler" to revert this change.
                        """)
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
    func updatePatchUnpatch() -> Bool {
        let isPatched = FileManager.default
            .fileExists(atPath: FrontendServer.patched)
        DispatchQueue.main.async {
            self.patchCompilerItem.title = (isPatched ?
                FrontendServer.State.patched : .unpatched).rawValue
        }
        return isPatched
    }
}

extension JSONDecoder {
    func decode<T: Decodable>(from: Data) throws -> T {
        return try decode(T.self, from: from)
    }
}

class FrontendServer: InjectionServer {
    enum State: String {
        case unpatched = "Intercept Compiler"
        case patched = "Unpatch Compiler"
    }

    static var binURL: URL = URL(fileURLWithPath: Defaults.xcodePath +
        "/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin")
    static var unpatchedURL: URL = binURL.appendingPathComponent("swift-frontend")
    static var patched: String = unpatchedURL.path + ".save"
    static var patchedURL: URL = URL(fileURLWithPath: patched)
    static var loggedFrontend: String?, lastInjected: String?

    static var clientPlatform: String {
        InjectionServer.currentClient?.platform ?? "iPhoneSimulator" }
    static func cacheURL(platform: String) -> URL {
        return URL(fileURLWithPath: "/tmp/\(platform)_commands.json")
    }
    static var recompilers = [String: NextCompiler]()
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
                recompiler.compilations = try JSONDecoder().decode(from: cached)
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
            let cache = cacheURL(platform: clientPlatform)
            let data = try JSONEncoder().encode(frontendRecompiler().compilations)
            try data.write(to: cache, options: .atomic)
            if let error = Popen.system("gzip -f "+cache.path, errors: true) {
                InjectionServer.error("Unable to zip commands cache: \(error)")
            } else {
                print("Cached \(frontendRecompiler().compilations.count) \(platform) commands")
            }
        } catch {
            InjectionServer.error("Unable to write commands cache: \(error)")
        }
    }

    static var lastFilelist: String?, lastArguments: [String]?

    static func processFrontendCommandFrom(feed: SimpleSocket) throws {
        guard feed.readString() == "1.0" else {
            return _ = frontendRecompiler()
                .error("Unpatch then repatch compiler to update script version")
        }
        guard let projectRoot = feed.readString(),
              let frontendPath = feed.readString(),
                feed.readString() == "-frontend" &&
                feed.readString() == "-c" else { return }

        var swiftFiles = "", args = [String](), primaries = [String](),
            platform = "iPhoneSimulator"

        while let arg = feed.readString(), arg != COMMANDS_END {
            switch arg {
            case "-filelist":
                guard let filelist = feed.readString() else { return }
                let files = try String(contentsOfFile: filelist,
                                       encoding: .utf8)
                swiftFiles += files
            case "-primary-file":
                guard let source = feed.readString() else { return }
                primaries.append(source)
                if !swiftFiles.contains(source) {
                    swiftFiles += source+"\n"
                }
            case "-o":
                _ = feed.readString()
            default:
                if let sdkPlatform: String = arg[#"/([A-Za-z]+)[\d\.]+\.sdk$"#] {
                    platform = sdkPlatform
                }
                if arg.hasSuffix(".swift") && args.last != "-F" {
                    swiftFiles += arg+"\n"
                } else if arg[Recompiler.optionsToRemove] {
                    _ = feed.readString()
                } else if !(arg == "-F" && args.last == "-F") && !arg[
                    "-validate-clang-modules-once|-frontend-parseable-output"] {
                    args.append(arg)
                }
            }
        }

        DispatchQueue.main.async {
            if !projectRoot.hasSuffix(".xcodeproj") &&
                AppDelegate.alreadyWatching(projectRoot) == nil {
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
            let recompiler = frontendRecompiler(platform: platform)
            loggedFrontend = frontendPath

            for source in primaries {
                // Don't update compilations while connected
                if InjectionServer.currentClient != nil &&
                    recompiler.compilations.index(forKey: source) != nil {
                    continue
                }

                // Try to minimise memory churn
                if let previous = recompiler
                    .compilations[source]?.arguments ?? lastArguments,
                   args == previous {
                    args = previous
                } else {
                    lastArguments = args
                }
                if let previous = recompiler
                    .compilations[source]?.swiftFiles ?? lastFilelist,
                   swiftFiles == previous {
                    swiftFiles = previous
                }
                lastFilelist = swiftFiles

                print("Updating \(args.count) args for \(platform)/" +
                      URL(fileURLWithPath: source).lastPathComponent)
                let update = NextCompiler.Compilation(arguments: args,
                      swiftFiles: swiftFiles, workingDir: projectRoot)
                recompiler.store(compilation: update, for: source)
            }
        }
    }
}
