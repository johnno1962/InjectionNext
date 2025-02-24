//
//  CommandServer.swift
//  InjectionNext
//
//  Created by John Holdsworth on 23/02/2025.
//  Copyright © 2025 John Holdsworth. All rights reserved.
//

import Foundation

extension InjectionServer {
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

    static var recompiler = NextCompiler()
    static var lastFilelist: String?, lastArguments: [String]?, pendingSource: String?

    func processFeedCommand() throws {
        var swiftFiles = "", args = [String](),
            sourceFiles = [String](), workingDir = "/tmp"
        Frontend.original = readString()
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
                if arg[#" (-(pch-output-dir|supplementary-output-file-map|emit-(reference-)?dependencies|serialize-diagnostics|index-(store|unit-output))-path|(-validate-clang-modules-once )?-clang-build-session-file|-Xcc -ivfsstatcache -Xcc) \#(Recompiler.argumentRegex)"#] {
                    _ = readString()
                } else {
                    args.append(arg)
                }
            }
        }
        
        MonitorXcode.compileQueue.async {
            for source in sourceFiles {
                if let previous = Self.recompiler
                    .compilations[source]?.arguments ?? Self.lastArguments,
                   args == previous {
                    args = previous
                } else {
                    Self.lastArguments = args
                }
                if let previous = Self.recompiler
                    .compilations[source]?.swiftFiles ?? Self.lastFilelist,
                   swiftFiles == previous {
                    swiftFiles = previous
                } else {
                    Self.lastFilelist = swiftFiles
                }
                
                print("Updating \(args.count) args with \(sourceFiles.count) swift files "+source)
                let update = NextCompiler.Compilation(arguments: args,
                                                      swiftFiles: swiftFiles, workingDir: workingDir)
                
                // The folling line should be on the compileQueue
                // but it seems to provoke a Swift compiler bug.
                Self.recompiler.compilations[source] = update
                if source == Self.pendingSource {
                    Self.pendingSource = nil
                    MonitorXcode.compileQueue.async {
                        if Self.recompiler.inject(source: source) {
                            Self.pendingSource = nil
                        }
                    }
                }
            }
        }
    }
}
