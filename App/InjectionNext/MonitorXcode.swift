//
//  RunXcode.swift
//  InjectionNext
//
//  Created by John H on 30/05/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Launches Xcode and monitors console output for SourceKit
//  logging messages which reveal the compiler arguments to
//  use for the file currently being edited (Used for real
//  time syntax and error checking by the SourceKit daemon).
//  Captures this information and passes it onto a Recompiler
//  instance to process and inject when edited file is saved.
//
import Foundation
import SwiftRegex
import Fortify
import Popen

class MonitorXcode {

    // Currently running Xcode process
    static weak var runningXcode: MonitorXcode?
    // Trying to avoid fragmenting memory
    var lastFilelist: String?, lastArguments: [String]?, lastSource: String?
    // The service to recompile and inject a source file.
    var recompiler = NextCompiler()

    func debug(_ what: Any..., separator: String = " ") {
        #if DEBUG
        print(what, separator: separator)
        #endif
    }

    init(args: String = "") {
        var args = args
        #if DEBUG
        args += " | tee \(recompiler.tmpbase).log"
        #endif
        if let xcodeStdout = Popen(cmd: "export SOURCEKIT_LOGGING=1; " +
            "'\(Defaults.xcodePath)/Contents/MacOS/Xcode' 2>&1\(args)") {
            Self.runningXcode = self
            appDelegate.launchXcodeItem.state = .on
            DispatchQueue.global().async {
                while true {
                    do {
                        try Fortify.protect {
                            appDelegate.setMenuIcon(.ready)
                            self.processSourceKitOutput(from: xcodeStdout)
                            appDelegate.setMenuIcon(.idle)
                        }
                        Self.runningXcode = nil
                        appDelegate.launchXcodeItem.state = .off
                        if Defaults.xcodeRestart == true && !xcodeStdout.terminatedOK()  {
                            appDelegate.runXcode(self)
                        }
                        break // break on clean exit and EOF.
                    } catch {
                        // Continue processing on error
                        _ = self.recompiler.error(error)
                    }
                }
            }
        }
    }

    func processSourceKitOutput(from xcodeStdout: Popen) {
        var buffer = [CChar](repeating: 0, count: Popen.initialLineBufferSize)
        func readQuotedString() -> String? {
            var offset = 0
            let doubleQuote = Int32(UInt8(ascii: "\"")), escaped = #"\""#
            while let line = fgets(&buffer[offset], CInt(buffer.count-offset),
                                   xcodeStdout.fileStream) {
                offset += strlen(line)
                if offset > 0 && buffer[offset-1] == UInt8(ascii: "\n") {
                    if let start = strchr(buffer, doubleQuote),
                       let end = strrchr(start+1, doubleQuote) {
                        end[0] = 0
                        var out = String(cString: start+1)
                        // Xcode uses NSLog to log internal UTF8 strings
                        // using %s which uses the macOS system encoding.
                        // https://en.wikipedia.org/wiki/Mac_OS_Roman
                        // For now we need to do the following dance
                        // to revert scrambled non-ASCII file paths.
                        if out.hasPrefix("/") &&
                            !FileManager.default.fileExists(atPath: out),
                           let data = out.data(using: .macOSRoman),
                           let recovered = String(data: data, encoding: .utf8),
                           FileManager.default.fileExists(atPath: recovered) {
                            out = recovered
                        }
                        if strstr(start+1, escaped) != nil {
                            out = out.replacingOccurrences(of: escaped, with: "\"")
                        }
                        return out
                    }

                    return nil
                }

                var grown = [CChar](repeating: 0, count: buffer.count*2)
                strcpy(&grown, buffer)
                buffer = grown
            }

            return nil
        }

        let indexBuild = "/Index.noindex/Build/"
        while let line = xcodeStdout.readLine() {
//            debug(">>"+line+"<<")
            if line.hasPrefix("  key.request: source.request.") &&
                (line == "  key.request: source.request.editor.open," ||
                 line == "  key.request: source.request.diagnostics," ||
                 line == "  key.request: source.request.activeregions," ||
                 line == "  key.request: source.request.relatedidents,") &&
                xcodeStdout.readLine() == "  key.compilerargs: [" ||
                line == "  key.compilerargs: [" {
                var swiftFiles = "", args = [String](), fileCount = 0,
                    workingDir = "/tmp", configDirs = Set<String>()

                while var arg = readQuotedString() {
                    let llvmIncs = "/llvm-macosx-arm64/lib"
                    if arg.hasPrefix("-I"), arg.contains(llvmIncs) {
                        arg = arg.replacingOccurrences(of: llvmIncs,
                            with: "/../buildbot_osx"+llvmIncs)
                    }
                    if args.last == "-F" && arg.hasSuffix("/PackageFrameworks") {
                        Unhider.packageFrameworks = arg
                        #if DEFAULTS_PACKAGE_PROBLEM || false
                        let frameworksURL = URL(fileURLWithPath: arg)
                        let derivedData = frameworksURL.deletingLastPathComponent()
                            .deletingLastPathComponent().deletingLastPathComponent()
                            .deletingLastPathComponent().deletingLastPathComponent()
                        let productsDir =
                            derivedData.appendingPathComponent("Build/Products")
                        let platform = InjectionServer
                            .currentClient?.platform ?? "iPhoneSimulator"
                        if let configs = Glob(pattern: productsDir.path +
                                               "/*-" + platform.lowercased()) {
                            for other in configs
                                where configDirs.insert(other).inserted {
                                args += [other, "-F"]
                            }
                        }
                        #endif
                    }

                    if arg.hasSuffix(".swift") && args.last != "-F" {
                        swiftFiles += arg+"\n"
                        fileCount += 1
                    } else if arg == "-fsyntax-only" || arg == "-o" {
                        _ = xcodeStdout.readLine()
                    } else if var work: String = arg[#"-working-directory(?:=(.*))?"#] {
                        if work == RegexOptioned.unmatchedGroup,
                           let swork = readQuotedString() {
                            work = swork
                        }
                        workingDir = work
                    } else if args.last == "-vfsoverlay" &&
                                arg.contains(indexBuild) {
                        // injecting tests without having run tests
                        args.removeLast()
                    // Xcode seems to maintain two sets of "build inputs"
                    // i.e. .swiftmodule, .modulemap etc. files and it
                    // seems the main build allows you to avoid "unhiding"
                    // whereas the paths provided to SourceKit are for the
                    // Index.noindex/Build tree of inputs. Switch them.
                    } else if /*(args.last == "-I" || args.last == "-F" ||
                               args.last == "-Xcc" && (arg.hasPrefix("-I") ||
                                   arg.hasPrefix("-fmodule-map-file="))) &&*/
                        arg.contains(indexBuild) &&
                            !arg.contains("/Intermediates.noindex/"),
                        let option = args.last {
                        // expands out default argument generators
                        var change = [arg.replacingOccurrences(
                            of: indexBuild, with: "/Build/")]
                            // alternate fix of Defaults problem
                            // hopefully without causing unhides
                        if InjectionServer.currentClient?
                            .platform.hasPrefix("AppleTV") != true {
                            change += (arg.hasPrefix("-") ? [arg] :
                                        option.hasPrefix("-") ? [option, arg] :
                                        [])
                        }
//                        debug(change)
                        args += change
                    } else if !(arg == "-F" && args.last == "-F") &&
                        arg != "-Xfrontend" && !arg.hasPrefix("-driver-") {
                        args.append(arg)
                    }
                }

                guard !args.isEmpty, let source =
                        readQuotedString() ?? readQuotedString(),
                      !source.contains("\\n") else {
                    continue
                }
                lastSource = source

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
                } else {
                    lastFilelist = swiftFiles
                }

                print("Updating \(args.count) args with \(fileCount) swift files "+source+" "+line)
                let update = NextCompiler.Compilation(arguments: args,
                    swiftFiles: swiftFiles, workingDir: workingDir)
 
                recompiler.store(compilation: update, for: source)
            } else if line ==
                "  key.request: source.request.indexer.editor-did-save-file,",
                let _ = xcodeStdout.readLine(), let source = readQuotedString() {
                print("Injecting saved file "+source)
                NextCompiler.compileQueue.async {
                    _ = self.recompiler.inject(source: source)
                }
            }
        }
    }
}
