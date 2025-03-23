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
    static var pendingInjections = [String]()
    /// InjectionNext compiler that uses InjectionLite log parser
    var liteRecompiler = HybridCompiler()
    /// Minimum seconds between injections
    let minInterval = 1.0

    /// Called from file watcher when file is edited.
    override func inject(source: String) {
        var recompiler: NextCompiler = liteRecompiler
        if AppDelegate.ui.updatePatchUnpatch() && source.hasSuffix(".swift") {
            recompiler = FrontendServer.frontendRecompiler()
            FrontendServer.lastInjected = source
        }
        guard !AppDelegate.watchers.isEmpty,
              Date().timeIntervalSince1970 - (MonitorXcode.runningXcode?
                .recompiler.lastInjected[source] ?? 0.0) > minInterval else {
            return
        }
        Self.pendingInjections.append(source)
        NextCompiler.compileQueue.async {
            self.injectNext(fallback: recompiler)
        }
    }

    func injectNext(fallback: NextCompiler) {
        guard let source = DispatchQueue.main.sync(execute: { () -> String? in
            guard let source = Self.pendingInjections.first else { return nil }
            Self.pendingInjections.removeFirst()
            if !Self.pendingInjections.isEmpty {
                NextCompiler.compileQueue.async {
                    self.injectNext(fallback: fallback)
                }
            }
            return source
        }) else { return }

        guard let running = MonitorXcode.runningXcode,
              running.recompiler.inject(source: source) else {
            if !fallback.inject(source: source) {
                fallback.pendingSource = source
            } else if FrontendServer.loggedFrontend != nil {
                FrontendServer.writeCache()
            }
            return
        }
    }
}

class HybridCompiler: NextCompiler {
    /// Legacy log parsing version of recomilation
    var liteRecompiler = Recompiler()

    override func recompile(source: String, platform: String) ->  String? {
        return liteRecompiler.recompile(source: source, dylink: false)
    }
}
