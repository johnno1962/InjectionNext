//
//  InjectionHybrid.swift
//  InjectionNext
//
//  Created by John Holdsworth on 09/11/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Provide file watcher/log parser fallback
//  for use outside Xcode (i.e. Cursor/VSCode)
//
import Cocoa

extension AppDelegate {
    static var watchers = [InjectionHybrid]()

    @IBAction func watchProject(_ sender: NSMenuItem) {
        let open = NSOpenPanel()
        open.prompt = "Select Project Directory"
        open.canChooseDirectories = true
        open.canChooseFiles = false
        // open.showsHiddenFiles = TRUE;
        if open.runModal() == .OK, let url = open.url {
            setenv("INJECTION_DIRECTORIES",
                   NSHomeDirectory()+"/Library/Developer,"+url.path, 1)
            Reloader.xcodeDev = Defaults.xcodePath+"/Contents/Developer"
            Reloader.injectionQueue = .main
            Self.watchers.append(InjectionHybrid())
        } else {
            Self.watchers.removeAll()
        }
        sender.state = Self.watchers.isEmpty ? .off : .on
    }
}

class InjectionHybrid: InjectionBase {
    static var pendingInjections = [String]()
    /// InjectionNext compiler that uses InjectionLite log parser
    var mixRecompiler: NextCompiler = HybridCompiler()
    /// Minimum seconds between injections
    let minInterval = 1.0

    /// Called from file watcher when file is edited.
    override func inject(source: String) {
        if CommandServer.Frontend.lastFrontend != nil {
            mixRecompiler = CommandServer.platformRecompiler
            CommandServer.Frontend.lastInjected = source
        }
        guard !AppDelegate.watchers.isEmpty,
              Date().timeIntervalSince1970 - (MonitorXcode.runningXcode?
                .recompiler.lastInjected[source] ?? 0.0) > minInterval else {
            return
        }
        Self.pendingInjections.append(source)
        MonitorXcode.compileQueue.async(execute: injectNext)
    }
    
    func injectNext() {
        guard let source = DispatchQueue.main.sync(execute: { () -> String? in
            guard let source = Self.pendingInjections.first else { return nil }
            Self.pendingInjections.removeFirst()
            if !Self.pendingInjections.isEmpty {
                MonitorXcode.compileQueue.async(execute: injectNext)
            }
            return source
        }) else { return }
        guard let running = MonitorXcode.runningXcode,
              running.recompiler.inject(source: source) else {
            if !self.mixRecompiler.inject(source: source) {
                self.mixRecompiler.pendingSource = source
            } else {
                CommandServer.writeCache()
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
