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
        guard Self.watchers[path] == nil else { return }
        setenv(INJECTION_DIRECTORIES,
               NSHomeDirectory()+"/Library/Developer,"+path, 1)
        Self.watchers[path] = InjectionHybrid()
        Self.lastWatched = path
        GitIgnoreParser.monitor(directory: path)
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
    /// InjectionNext compiler that uses InjectionLite log parser
    var liteRecompiler: NextCompiler = HybridCompiler()
    /// Minimum seconds between injections
    let minInterval = 1.0

    /// Called from file watcher when file is edited.
    override func inject(source: String) {
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
        if let why = GitIgnoreParser.shouldExclude(file: source) {
            log("Excluded \(source) as \(why)")
        } else if !recompiler.inject(source: source) {
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
