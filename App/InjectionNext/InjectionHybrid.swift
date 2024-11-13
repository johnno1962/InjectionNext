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
            Reloader.injectionQueue = .main
            Self.watchers.append(InjectionHybrid())
            sender.state = .on
        }
    }
}

class InjectionHybrid: InjectionBase {
    /// InjectionNext compiler that uses InjectionLite log parser
    let mixRecompiler = HybridCompiler()
    /// Minimum seconds between injections
    let minInterval = 1.0

    /// Called from file watcher when file is edited.
    override func inject(source: String) {
        guard Date().timeIntervalSince1970 - (MonitorXcode.runningXcode?
            .recompiler.lastInjected[source] ?? 0.0) > minInterval else {
            return
        }
        MonitorXcode.compileQueue.async {
            if let running = MonitorXcode.runningXcode {
                running.recompiler.inject(source: source)
            } else {
                self.mixRecompiler.inject(source: source)
            }
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
