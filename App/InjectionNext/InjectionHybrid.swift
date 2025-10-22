//
//  InjectionHybrid.swift
//  InjectionNext
//
//  Created by John Holdsworth on 09/11/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Provide file watcher/log parser fallback
//  for use outside Xcode (e.g. Cursor/VSCode)
//  Also uses FileWatcher for operation when
//  swift-frontend has been replaced by a
//  script to capture compiler invocations.
//
import Cocoa

extension AppDelegate {
    static var watchers = [String: InjectionHybrid]()
    static var lastWatched: String?

    @IBAction func watchProject(_ sender: NSMenuItem) {
        let open = NSOpenPanel()
        open.prompt = "Select Project Directory"
        open.canChooseDirectories = true
        open.canChooseFiles = false
        // open.showsHiddenFiles = TRUE;
        if open.runModal() == .OK, let url = open.url {
            Reloader.xcodeDev = Defaults.xcodePath+"/Contents/Developer"
            Reloader.injectionQueue = .main
            watch(path: url.path)
        } else {
            Self.watchers.removeAll()
            Self.lastWatched = nil
        }
    }
    
    func watch(path: String) {
        setenv("INJECTION_DIRECTORIES",
               NSHomeDirectory()+"/Library/Developer,"+path, 1)
        Self.watchers[path] = InjectionHybrid()
        Self.lastWatched = path
        watchDirectoryItem.state = Self.watchers.isEmpty ? .off : .on
    }
    static func alreadyWatching(_ projectRoot: String) -> String? {
        return watchers.keys.first { projectRoot.hasPrefix($0) }
    }
    static func restartLastWatcher() {
        DispatchQueue.main.async {
            lastWatched.flatMap { watchers[$0]?.watcher?.restart() }
        }
    }
}

class InjectionHybrid: InjectionBase {
    static var pendingFilesChanged = [String]()
    /// Repository locked state - stops processing until app reconnects
    static var isRepositoryLocked = false
    /// InjectionNext compiler that uses InjectionLite log parser
    var liteRecompiler: NextCompiler = HybridCompiler()
    /// Minimum seconds between injections
    let minInterval = 1.0

    override init() {
        super.init()
        // Extend FileWatcher pattern to detect git lock files
        FileWatcher.INJECTABLE_PATTERN = try! NSRegularExpression(
            pattern: "[^~]\\.(mm?|cpp|swift|storyboard|xib|lock)$")
    }

    /// Called from file watcher when file is edited.
    override func inject(source: String) {
        // Detect git lock files
        if source.hasSuffix(".lock") &&
           source.contains("/.git/") {
            Self.isRepositoryLocked = true
            Self.pendingFilesChanged.removeAll()
            log("""
                Git repository locked (branch switch/merge/rebase detected). \
                File processing stopped. Please relaunch your app to resume injection.
                """)
            return
        }

        // Skip processing if repository is locked
        if Self.isRepositoryLocked {
            log("""
                File processing stopped due to git lock. \
                Please relaunch your app to resume injection.
                """)
            return
        }

        guard !AppDelegate.watchers.isEmpty,
              Date().timeIntervalSince1970 - (MonitorXcode.runningXcode?
                .recompiler.lastInjected[source] ?? 0.0) > minInterval else {
            return
        }
        Self.pendingFilesChanged.append(source)
        NextCompiler.compileQueue.async { self.injectNext() }
    }

    func injectNext() {
        guard let source = (DispatchQueue.main.sync { () -> String? in
            if Self.pendingFilesChanged.isEmpty { return nil }
            let source = Self.pendingFilesChanged.removeFirst()
            if !Self.pendingFilesChanged.isEmpty {
                NextCompiler.compileQueue.async { self.injectNext() }
            }
            return source
        }) else { return }

        if let running = MonitorXcode.runningXcode,
           running.recompiler.inject(source: source) { return }

        var recompiler = liteRecompiler
        if FrontendServer.loggedFrontend != nil && source.hasSuffix(".swift") {
            recompiler = FrontendServer.frontendRecompiler()
        }
        if !recompiler.inject(source: source) {
            recompiler.pendingSource = source
        } else if !(recompiler === liteRecompiler) {
            FrontendServer.writeCache()
        }
    }
}

class HybridCompiler: NextCompiler {
    /// Legacy log parsing version of recomilation
    var liteRecompiler = Recompiler()

    override func recompile(source: String, platform: String) ->  String? {
        return liteRecompiler.recompile(source: source, platformFilter:
                                            "SDKs/"+platform, dylink: false)
    }
}
