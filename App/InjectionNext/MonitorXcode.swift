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
import AppKit
import SwiftRegex
import Fortify
import Popen

class MonitorXcode {

    // Currently running Xcode process
    static weak var runningXcode: MonitorXcode?
    // The service to recompile and inject a source file.
    static var recompiler = FrontendServer.frontendRecompiler(for: "Xcode")

    struct RunningXcodeMatch {
        let pid: pid_t
        let app: NSRunningApplication
        let workspacePaths: [String]
    }

    /// When InjectionNext reuses an already-running Xcode instead of
    /// spawning one, we don't own its stdout. We still mirror the UI
    /// state (menu icon + `isXcodeRunning`) here and clear it when
    /// that Xcode terminates.
    private(set) static var attachedExternal: NSRunningApplication?
    private static var attachedObserver: NSObjectProtocol?

    @MainActor
    static func attach(to match: RunningXcodeMatch) {
        if attachedExternal?.processIdentifier == match.pid { return }
        detachExternal()
        attachedExternal = match.app
        ConfigStore.shared.isXcodeRunning = true
        AppDelegate.ui?.setMenuIcon(.ready)

        attachedObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  app.processIdentifier == attachedExternal?.processIdentifier
            else { return }
            detachExternal()
            ConfigStore.shared.isXcodeRunning = false
            AppDelegate.ui?.setMenuIcon(.idle)
        }
    }

    static func detachExternal() {
        if let obs = attachedObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        attachedObserver = nil
        attachedExternal = nil
    }

    static var isXcodeActive: Bool {
        runningXcode != nil ||
            (attachedExternal.map { !$0.isTerminated } ?? false)
    }

    /// Marker env var set when InjectionNext launches Xcode.
    static let injectionEnvMarker = "RUNNING_VIA_INJECTION_NEXT=1"

    /// Returns a running Xcode with the given project/workspace already open.
    /// Detection order: AppleScript (workspace documents) → lsof fallback
    /// (for when Automation permission hasn't been granted yet).
    /// If `project` is `nil`, returns the first Xcode launched by
    /// InjectionNext (based on the env marker).
    static func existingInjectionXcode(matching project: String? = nil)
        -> RunningXcodeMatch? {
        let xcodes = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dt.Xcode")
        guard !xcodes.isEmpty else { return nil }

        let scripted = openedWorkspacePaths()

        if let project = project {
            let target = (project as NSString).standardizingPath
            for app in xcodes {
                let pid = app.processIdentifier
                guard pid > 0 else { continue }
                let hasProject = scripted.contains(where: { pathMatches($0, target) })
                    || lsofHasOpenFile(pid: pid, path: target)
                if hasProject {
                    return RunningXcodeMatch(
                        pid: pid, app: app, workspacePaths: scripted)
                }
            }
            return nil
        }

        for app in xcodes {
            let pid = app.processIdentifier
            guard pid > 0,
                  let env = Popen(cmd: "ps eww -o command= -p \(pid) 2>/dev/null")?
                      .readAll(),
                  env.contains(injectionEnvMarker) else { continue }
            return RunningXcodeMatch(pid: pid, app: app, workspacePaths: scripted)
        }
        return nil
    }

    private static func pathMatches(_ lhs: String, _ rhs: String) -> Bool {
        let l = (lhs as NSString).standardizingPath
        let r = (rhs as NSString).standardizingPath
        return l == r || l.hasPrefix(r) || r.hasPrefix(l)
    }

    /// Paths of workspace documents currently open in Xcode (best effort).
    /// Requires user-granted Automation permission; returns `[]` otherwise.
    private static func openedWorkspacePaths() -> [String] {
        let src = """
        tell application id "com.apple.dt.Xcode"
            set out to ""
            repeat with d in workspace documents
                try
                    set out to out & (path of d) & linefeed
                end try
            end repeat
            return out
        end tell
        """
        var err: NSDictionary?
        guard let s = NSAppleScript(source: src)?
                .executeAndReturnError(&err).stringValue else { return [] }
        return s.split(whereSeparator: \.isNewline).map(String.init)
    }

    /// Cheap fallback: does this pid have the given project path open?
    /// Xcode keeps the `.xcodeproj` / `.xcworkspace` directory as an open
    /// file descriptor for as long as the document is loaded.
    private static func lsofHasOpenFile(pid: pid_t, path: String) -> Bool {
        guard let out = Popen(
            cmd: "/usr/sbin/lsof -p \(pid) -Fn 2>/dev/null")?.readAll()
        else { return false }
        let needle = (path as NSString).standardizingPath
        return out.range(of: needle) != nil
    }

    func debug(_ what: Any..., separator: String = " ") {
        #if DEBUG
        print(what, separator: separator)
        #endif
    }

    init(args: String = "") {
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
        else if let xcodeStdout = Popen(cmd: """
            export SOURCEKIT_LOGGING=0
            export RUNNING_VIA_INJECTION_NEXT=1
            '\(Defaults.xcodePath)/Contents/MacOS/Xcode' \
            -ApplePersistenceIgnoreState YES \
            -NSQuitAlwaysKeepsWindows NO 2>&1 \(args)
            """) {
            Self.runningXcode = self
            DispatchQueue.main.async { ConfigStore.shared.isXcodeRunning = true }
            DispatchQueue.global().async {
                while true {
                    do {
                        try Fortify.protect {
                            AppDelegate.ui.setMenuIcon(.ready)
                            self.processSourceKitOutput(from: xcodeStdout)
                            AppDelegate.ui.setMenuIcon(.idle)
                        }
                        Self.runningXcode = nil
                        DispatchQueue.main.async { ConfigStore.shared.isXcodeRunning = false }
                        if !xcodeStdout.terminatedOK() && Defaults.xcodeRestart == true {
                            DispatchQueue.main.async { AppDelegate.ui.runXcode(self) }
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

                print("Updating \(parser.args.count) args with \(parser.swiftFileCount) swift files "+source+" "+line)
                let update = NextCompiler.Compilation(arguments: parser.args,
                    swiftFiles: parser.swiftFiles, workingDir: parser.workingDir)

                NextCompiler.compileQueue.async {
                    Self.recompiler.store(compilation: update, for: source)
                }
            } else if line ==
                "  key.request: source.request.indexer.editor-did-save-file,",
                let _ = xcodeStdout.readLine(), let source = readQuotedString() {
                print("Injecting saved file "+source)
                NextCompiler.compileQueue.async {
                    _ = Self.recompiler.inject(source: source)
                }
            }
        }
        }
    }
}
