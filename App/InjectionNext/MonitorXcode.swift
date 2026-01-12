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
        if let xcodeStdout = Popen(cmd: """
            export SOURCEKIT_LOGGING=1; export RUNNING_VIA_INJECTION_NEXT=1; \
            '\(Defaults.xcodePath)/Contents/MacOS/Xcode' 2>&1\(args)
            """) {
            Self.runningXcode = self
            AppDelegate.ui.launchXcodeItem.state = .on
            DispatchQueue.global().async {
                while true {
                    do {
                        try Fortify.protect {
                            AppDelegate.ui.setMenuIcon(.ready)
                            self.processSourceKitOutput(from: xcodeStdout)
                            AppDelegate.ui.setMenuIcon(.idle)
                        }
                        Self.runningXcode = nil
                        AppDelegate.ui.launchXcodeItem.state = .off
                        if Defaults.xcodeRestart == true && !xcodeStdout.terminatedOK()  {
                            AppDelegate.ui.runXcode(self)
                        }
                        break // break on clean exit and EOF.
                    } catch {
                        // Continue processing on error
                        self.recompiler.error(error)
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
        let productDir = "-"+FrontendServer.clientPlatform.lowercased()
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
                    workingDir = "/tmp"

                while var arg = readQuotedString() {
                    /// Used if injecting the Swift compiler.
                    let llvmIncs = "/llvm-macosx-arm64/lib"
                    if arg.hasPrefix("-I"), arg.contains(llvmIncs) {
                        arg = arg.replacingOccurrences(of: llvmIncs,
                            with: "/../buildbot_osx"+llvmIncs)
                    }
                    
                    /// Arguments received from SourceKit while syntax highlighting the editor
                    /// have their own "Intermediates" directory. Map it back to the main one.
                    let alt = arg[indexBuild, "/Build/"]
                    if !arg.hasSuffix(".yaml"), alt != arg,
                       !arg.contains("/Intermediates.noindex/"),
                       let path: String = alt[#"(?:-I)?(.*)"#],
                       FileManager.default.fileExists(atPath: path) {
                        arg = alt
                    }

                    /// Determine path to DerivedData for "unhiding".
                    if args.last == "-F" {
                        if arg.hasSuffix("/PackageFrameworks") {
                            Unhider.packageFrameworks = arg
                        }
                        else if Unhider.packageFrameworks == nil,
                                arg.hasSuffix(productDir) {
                            Unhider.packageFrameworks = arg+"/PackageFrameworks"
                        }
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
                    } else if arg != "-Xfrontend" && !arg.hasPrefix("-driver-") {
                        args.append(arg)
                    }
                }

                guard !args.isEmpty, let source =
                        readQuotedString() ?? readQuotedString(),
                      !source.contains("\\n") else {
                    continue
                }

                print("Updating \(args.count) args with \(fileCount) swift files "+source+" "+line)
                let update = NextCompiler.Compilation(arguments: args,
                    swiftFiles: swiftFiles, workingDir: workingDir)
 
                NextCompiler.compileQueue.async {
                    self.recompiler.store(compilation: update, for: source)
                }
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
