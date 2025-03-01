//
//  FrontendServer.swift
//  InjectionNext
//
//  Created by John Holdsworth on 23/02/2025.
//  Copyright © 2025 John Holdsworth. All rights reserved.
//
//  Code realted to "Intercepting" version where the binary
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
                "swift-api-digester", "swift-api-extract", "swift-cache-tool"]
            if sender.title == FrontendServer.State.unpatched.rawValue {
                if !fm.fileExists(atPath: FrontendServer.patched),
                   let feeder = Bundle.main
                    .url(forResource: "swift-frontend", withExtension: "sh") {
                    try fm.moveItem(at: FrontendServer.unpatchedURL,
                                    to: FrontendServer.patchedURL)
                    try fm.createSymbolicLink(at: FrontendServer
                        .unpatchedURL, withDestinationURL: feeder)
                    for binary in linksToMove {
                        let link = FrontendServer.binURL.appendingPathComponent(binary)
                        try fm.removeItem(at: link)
                        symlink("swift-frontend.save", link.path)
                    }
                    InjectionServer.error("""
                        The Swift compiler of your current toolchain \
                        \(FrontendServer.unpatchedURL.path) has been replaced \
                        by a symbolic link to a script to capture all \
                        compilation commands. Use menu item "Unpatch \
                        Compiler" to revert this change.
                        """)
                }
            } else if fm.fileExists(atPath: FrontendServer.patched) {
                try fm.removeItem(at: FrontendServer.unpatchedURL)
                try fm.moveItem(at: FrontendServer.patchedURL,
                                to: FrontendServer.unpatchedURL)
                for binary in linksToMove {
                    let link = FrontendServer.binURL.appendingPathComponent(binary)
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
        patchCompilerItem.title = (isPatched ?
            FrontendServer.State.patched : .unpatched).rawValue
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
        let encoder = JSONEncoder()
        do {
            let cache = cacheURL(platform: clientPlatform)
            let data = try encoder.encode(frontendRecompiler().compilations)
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
        var swiftFiles = "", args = [String](), platform = "iPhoneSimulator",
            sourceFiles = [String](), workingDir = "/tmp"
        let frontendPath = feed.readString()
        
        while let arg = feed.readString(), arg != COMMANDS_END {
            switch arg {
            case "-filelist":
                guard let filelist = feed.readString() else { return }
                let files = try String(contentsOfFile: filelist,
                                       encoding: .utf8)
                swiftFiles += files
            case "-primary-file":
                guard let source = feed.readString() else { return }
                sourceFiles.append(source)
                if !swiftFiles.contains(source) {
                    swiftFiles += source+"\n"
                }
            case "-emit-module":
                return
            case "-o":
                _ = feed.readString()
            default:
                if let sdkPlatform: String = arg[#"/([A-Za-z]+)[\d\.]+\.sdk$"#] {
                    platform = sdkPlatform
                }
                if arg.hasSuffix(".swift") {
                    swiftFiles += arg+"\n"
                } else if arg[
                    #"(-(pch-output-dir|supplementary-output-file-map|emit-(reference-)?dependencies|serialize-diagnostics|index-(store|unit-output))(-path)?|(-validate-clang-modules-once )?-clang-build-session-file|-Xcc -ivfsstatcache -Xcc)"#] {
                    _ = feed.readString()
                } else if !arg["-validate-clang-modules-once|-frontend-parseable-output"] {
                    args.append(arg)
                }
            }
        }

        MonitorXcode.compileQueue.async {
            let recompiler = Self.frontendRecompiler(platform: platform)
            FrontendServer.loggedFrontend = frontendPath

            for source in sourceFiles {
                if InjectionServer.currentClient != nil &&
                    recompiler.compilations.index(forKey: source) != nil {
                    continue
                }

                if let previous = recompiler
                    .compilations[source]?.arguments ?? Self.lastArguments,
                   args == previous {
                    args = previous
                } else {
                    Self.lastArguments = args
                }
                if let previous = recompiler
                    .compilations[source]?.swiftFiles ?? Self.lastFilelist,
                   swiftFiles == previous {
                    swiftFiles = previous
                }
                Self.lastFilelist = swiftFiles

                print("Updating \(args.count) args for \(platform)/" +
                      URL(fileURLWithPath: source).lastPathComponent)
                let update = NextCompiler.Compilation(arguments: args,
                      swiftFiles: swiftFiles, workingDir: workingDir)
                
                recompiler.compilations[source] = update
                if source == FrontendServer.frontendRecompiler().pendingSource {
                    recompiler.pendingSource = nil
                    MonitorXcode.compileQueue.async {
                        if FrontendServer.frontendRecompiler().inject(source: source) {
                            recompiler.pendingSource = nil
                        }
                    }
                }
            }
        }
    }
}
