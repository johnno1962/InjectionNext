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

import AppKit
import SwiftRegex
import Fortify
import Popen

class MonitorXcode {

    // Currently running Xcode process
    static weak var runningXcode: MonitorXcode? {
        didSet {
            DispatchQueue.main.async {
                ConfigStore.shared.haveLaunchedXcode = runningXcode != nil
            }
        }
    }
    // The service to recompile and inject a source file.
    static var recompiler = FrontendServer.frontendRecompiler(for: "Xcode")

    /// Any Xcode already running on this machine (not necessarily spawned
    /// by InjectionNext). Used to avoid launching a second `Xcode`
    /// process that would show the "already open in another Xcode
    /// process" dialog when the project is already open elsewhere.
    static var externalXcode: NSRunningApplication? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dt.Xcode")
            .first(where: { $0.processIdentifier > 0 })
    }

    init?(args: String = "") {
        let exports = ConfigStore.shared.envVarsForSwiftPackage(),
            project = ConfigStore.shared.projectPath
        if Self.externalXcode != nil {
            InjectionServer.error("Xcode already running, cannot start another")
            return nil
        }
        var args = args
        #if DEBUG
        args += " | tee \(Reloader.tmpbase).log"
        #endif
        if !FileManager.default.fileExists(atPath: Defaults.xcodePath) {
            InjectionServer.error("""
                No valid Xcode at path:
                \(Defaults.xcodePath)
                Use menu item "Select Xcode"
                to select a valid path.
                """)
        }
        else if let xcodeStdout = Popen(cmd: exports+"""
            export SOURCEKIT_LOGGING=1
            export RUNNING_VIA_INJECTION_NEXT=1
            '\(Defaults.xcodePath)/Contents/MacOS/Xcode' 2>&1 \(args)
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
                        if !xcodeStdout.terminatedOK() && Defaults.xcodeRestart == true {
                            AppDelegate.ui.runXcode(self)
                        }
                        Self.recompiler.writeCache()
                        break // break on clean exit and EOF.
                    } catch {
                        // Continue processing on error
                        Self.recompiler.error(error)
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
                        // Xcode used NSLog to log internal UTF8 strings
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
            autoreleasepool {
            if line.hasPrefix("  key.request: source.request.") &&
                (line == "  key.request: source.request.editor.open," ||
                 line == "  key.request: source.request.diagnostics," ||
                 line == "  key.request: source.request.activeregions," ||
                 line == "  key.request: source.request.relatedidents,") &&
                xcodeStdout.readLine() == "  key.compilerargs: [" ||
                line == "  key.compilerargs: [" {
                var parser = FrontendServer.CompilationArgParser()

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
                       let path: String = alt[#"[^/]*([^#]+)"#],
                       FileManager.default.fileExists(atPath: path) {
                        arg = alt
                    }

                    // SourceKit-specific args handled before the shared parser.
                    if arg == "-fsyntax-only" || arg == "-o" {
                        _ = xcodeStdout.readLine()
                    } else if var work: String = arg[#"-working-directory(?:=(.*))?"#] {
                        if work == RegexOptioned.unmatchedGroup,
                           let swork = readQuotedString() {
                            work = swork
                        }
                        parser.workingDir = work
                    } else if parser.args.last == "-vfsoverlay",
                              arg.contains(indexBuild) {
                        // injecting tests without having run tests
                        parser.args.removeLast()
                    } else if arg == "-Xfrontend" || arg.hasPrefix("-driver-") {
                        // drop silently
                    } else {
                        parser.process(arg: arg, next: readQuotedString)
                    }
                }

                guard !parser.args.isEmpty, let source =
                        readQuotedString() ?? readQuotedString(),
                      !source.contains("\\n") else {
                    return
                }

                debug("Updating \(parser.args.count) args with \(parser.swiftFileCount) swift files "+source+" "+line)
                let update = NextCompiler.Compilation(arguments: parser.args,
                    swiftFiles: parser.swiftFiles, workingDir: parser.workingDir)

                NextCompiler.compileQueue.async {
                    Self.recompiler.store(compilation: update, for: source)
                }
            } else if line ==
                "  key.request: source.request.indexer.editor-will-save-file,",
                let _ = xcodeStdout.readLine(), let source = readQuotedString() {
                debug("Injecting saved file "+source)
                DispatchQueue.main.async {
                    InjectionHybrid.lastInjected[source] = Date.timeIntervalSinceReferenceDate
                }
                NextCompiler.compileQueue.async {
                    _ = Self.recompiler.inject(source: source)
                }
            }
        }
        }
    }
}
