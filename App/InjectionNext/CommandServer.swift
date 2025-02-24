//
//  CommandServer.swift
//  InjectionNext
//
//  Created by John Holdsworth on 23/02/2025.
//  Copyright © 2025 John Holdsworth. All rights reserved.
//

import Cocoa
import Popen

extension AppDelegate {
    @IBAction func patchCompiler(_ sender: NSMenuItem) {
        let fm = FileManager.default
        do {
            if sender.title == Frontend.State.unpatched.rawValue {
                if !fm.fileExists(atPath: Frontend.patched),
                   let feeder = Bundle.main
                    .url(forResource: "swift-frontend", withExtension: nil) {
                    try fm.moveItem(at: Frontend.unpatchedURL,
                                    to: Frontend.patchedURL)
                    try fm.createSymbolicLink(at: Frontend
                        .unpatchedURL, withDestinationURL: feeder)
                    InjectionServer.error("""
                        The Swift compiler of your current toolchain \
                        \(Frontend.unpatched) has been replaced by \
                        a symbolic link to a script to capture all \
                        compilation commands. Use menu item "Unpatch \
                        Compiler" to revert this change.
                        """)
                }
            } else if fm.fileExists(atPath: Frontend.patched) {
                try fm.removeItem(atPath: Frontend.unpatched)
                try fm.moveItem(at: Frontend.patchedURL,
                                to: Frontend.unpatchedURL)
            }
        } catch {
            InjectionServer.error("Patching error: \(error)")
        }
        _ = updatePatchUnpatch()
    }

    func updatePatchUnpatch() -> Bool {
        let isPatched = FileManager.default
            .fileExists(atPath: Frontend.patched)
        patchCompilerItem.title = ( isPatched ?
               Frontend.State.patched : .unpatched).rawValue
        return isPatched
    }
}

class CommandServer: InjectionServer {
    struct Frontend {
        enum State: String {
            case unpatched = "Patch Compiler"
            case patched = "Unpatch Compiler"
        }
        
        static var unpatched: String = Defaults.xcodePath +
            "/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend"
        static var unpatchedURL: URL = URL(fileURLWithPath: unpatched)
        static var patched: String = unpatched + ".save"
        static var patchedURL: URL = URL(fileURLWithPath: patched)
        static var original: String?
    }
    
    static var currenPlatform: String =
    InjectionServer.currentClient?.platform ?? "iPhoneSimulator"
    static var cacheURL: URL {
        return URL(fileURLWithPath: "/tmp/\(currenPlatform)_commands.json")
    }
    static var recompilers = [String: NextCompiler]()
    static var platformRecompiler: NextCompiler = {
        if let recompiler = recompilers[currenPlatform] {
            return recompiler
        }
        let recompiler = NextCompiler()
        do {
            if let stream = Popen(cmd: "gunzip <\(cacheURL.path).gz")?.readAll(),
               let cached = stream.data(using: .utf8) {
                let decoder = JSONDecoder()
                recompiler.compilations = try decoder
                    .decode([String: NextCompiler.Compilation].self, from: cached)
                print("Loaded \(recompiler.compilations.count) cached commands")
            }
        } catch {
            InjectionServer.error("Unable to read commands cache: \(error)")
        }
        recompilers[currenPlatform] = recompiler
        return recompiler
    }()
    static func writeCache() {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(platformRecompiler.compilations)
            try data.write(to: cacheURL, options: .atomic)
            if let error = Popen.system("gzip -f "+cacheURL.path, errors: true) {
                InjectionServer.error("Unable to zip commands cache: \(error)")
            } else {
                print("Cached \(platformRecompiler.compilations.count) commands")
            }
        } catch {
            InjectionServer.error("Unable to write commands cache: \(error)")
        }
    }
}

extension InjectionServer {
    static var lastFilelist: String?, lastArguments: [String]?

    func processFeedCommand() throws {
        var swiftFiles = "", args = [String](),
            sourceFiles = [String](), workingDir = "/tmp"
        let originFrontend = readString()
        while let arg = readString(), arg != COMMANDS_END {
            switch arg {
            case "-frontend":
                continue
            case "-filelist":
                guard let filelist = readString() else { return }
                let files = try String(contentsOfFile: filelist,
                                       encoding: .utf8)
                swiftFiles += files
            case "-primary-file":
                guard let source = readString() else { return }
                sourceFiles.append(source)
            case "-o":
                _ = readString()
            default:
                if arg[#"(-(pch-output-dir|supplementary-output-file-map|emit-(reference-)?dependencies|serialize-diagnostics|index-(store|unit-output))-path|(-validate-clang-modules-once )?-clang-build-session-file|-Xcc -ivfsstatcache -Xcc)"#] {
                    _ = readString()
                } else if !arg["-validate-clang-modules-once"] {
                    args.append(arg)
                }
            }
        }
        
        MonitorXcode.compileQueue.async {
            CommandServer.Frontend.original = originFrontend
            let recompiler = CommandServer.platformRecompiler

            for source in sourceFiles {
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
                } else {
                    Self.lastFilelist = swiftFiles
                }
                
                print("Updating \(args.count) args for source " +
                      URL(fileURLWithPath: source).lastPathComponent)
                let update = NextCompiler.Compilation(arguments: args,
                      swiftFiles: swiftFiles, workingDir: workingDir)
                
                // The folling line should be on the compileQueue
                // but it seems to provoke a Swift compiler bug.
                recompiler.compilations[source] = update
                if source == CommandServer.platformRecompiler.pendingSource {
                    recompiler.pendingSource = nil
                    MonitorXcode.compileQueue.async {
                        if CommandServer.platformRecompiler.inject(source: source) {
                            recompiler.pendingSource = nil
                        }
                    }
                }
            }
        }
    }
}
