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
    // One compilation at a time.
    static let compileQueue = DispatchQueue(label: "InjectionCompile")
    // Trying to avoid fragmenting memory
    var lastFilelist: String?, lastArguments: [String]?, lastSource: String?
    // The service to reomcpile and inject a source file.
    var recompiler = Recompiler()

    func debug(_ msg: String) {
        #if DEBUG
        //print(msg)
        #endif
    }
    
    init() {
        #if DEBUG
        let tee = " | tee \(recompiler.tmpbase).log"
        #else
        let tee = ""
        #endif
        if let xcodeStdout = Popen(cmd: "export SOURCEKIT_LOGGING=1; " +
            "'\(Recompiler.xcodePath)/Contents/MacOS/Xcode' 2>&1\(tee)") {
            Self.runningXcode = self
            DispatchQueue.global().async {
                while true {
                    do {
                        try Fortify.protect {
                            appDelegate.setMenuIcon(.ready)
                            self.processSourceKitOutput(from: xcodeStdout)
                            appDelegate.setMenuIcon(.idle)
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
        
        while let line = xcodeStdout.readLine() {
            debug(">>"+line+"<<")
            if line.hasPrefix("  key.request: source.request.") &&
                (line == "  key.request: source.request.editor.open," ||
                 line == "  key.request: source.request.diagnostics," ||
                 line == "  key.request: source.request.activeregions," ||
                 line == "  key.request: source.request.relatedidents,") &&
                xcodeStdout.readLine() == "  key.compilerargs: [" ||
                line == "  key.compilerargs: [" {
                var swiftFiles = "", args = [String](),
                    fileCount = 0, workingDir = "/tmp"
                while var arg = readQuotedString() {
                    if arg.hasSuffix(".swift") {
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
                    } else if /*(args.last == "-I" || args.last == "-F" ||
                               args.last == "-Xcc" && (arg.hasPrefix("-I") ||
                                   arg.hasPrefix("-fmodule-map-file="))) &&*/
                                arg.contains("/Index.noindex/Build/") &&
                                    !arg.hasSuffix(".yaml") {
                        // expands out default argument generators
                        args += [arg.replacingOccurrences(
                            of: "/Index.noindex/Build/", with: "/Build/")]
                    } else if arg != "-Xfrontend" &&
                        arg != "-experimental-allow-module-with-compiler-errors" {
                        if args.last == "-F" && arg.hasSuffix("/PackageFrameworks") {
                            Unhider.packageFrameworks = arg
                        } else if arg.hasPrefix("-I") {
                            let llvmIncs = "/llvm-macosx-arm64/lib"
                            arg = arg.replacingOccurrences(of: llvmIncs,
                                with: "/../buildbot_osx"+llvmIncs)
                        }
                        args.append(arg)
                    }
                }
                guard args.count > 0, let source = 
                        readQuotedString() ?? readQuotedString() else {
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
                let update = Recompiler.Compilation(
                    arguments: args, swiftFiles: swiftFiles, workingDir: workingDir)
                // The folling line should be on the compileQueue
                // but it seems to provoke a compiler bug.
                self.recompiler.compilations[source] = update
                Self.compileQueue.async {
                    if source == self.recompiler.pendingSource {
                        print("Delayed injection of "+source)
                        self.recompiler.pendingSource = nil
                        self.recompiler.inject(source: source)
                    }
                }
            } else if line ==
                "  key.request: source.request.indexer.editor-did-save-file,",
                let _ = xcodeStdout.readLine(), let source = readQuotedString() {
                print("Injecting saved file "+source)
                Self.compileQueue.async {
                    self.recompiler.inject(source: source)
                }
            }
        }
    }
}
