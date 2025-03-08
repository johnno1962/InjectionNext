//
//  InjectionHybrid.swift
//  InjectionNext
//
//  Created by John Holdsworth on 09/11/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  Provide file watcher/log parser fallback
//  for use outside Xcode (e.g. Cursor/VSCode)
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
    var liteRecompiler = HybridCompiler()
    /// Minimum seconds between injections
    let minInterval = 1.0

    /// Called from file watcher when file is edited.
    override func inject(source: String) {
        var recompiler: NextCompiler = liteRecompiler
        if FrontendServer.loggedFrontend != nil && source.hasSuffix(".swift") {
            recompiler = FrontendServer.frontendRecompiler()
            FrontendServer.lastInjected = source
        }
        guard !AppDelegate.watchers.isEmpty,
              Date().timeIntervalSince1970 - (MonitorXcode.runningXcode?
                .recompiler.lastInjected[source] ?? 0.0) > minInterval else {
            return
        }
        Self.pendingInjections.append(source)
        MonitorXcode.compileQueue.async {
            self.injectNext(fallback: recompiler)
        }
    }

    func injectNext(fallback: NextCompiler) {
        guard let source = DispatchQueue.main.sync(execute: { () -> String? in
            guard let source = Self.pendingInjections.first else { return nil }
            Self.pendingInjections.removeFirst()
            if !Self.pendingInjections.isEmpty {
                MonitorXcode.compileQueue.async {
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
