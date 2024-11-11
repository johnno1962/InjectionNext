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
    let nextRecompiler = HybridCompiler()

    override func inject(source: String) {
        if MonitorXcode.runningXcode == nil {
            MonitorXcode.compileQueue.async {
                self.nextRecompiler.inject(source: source)
            }
        }
    }
}

class HybridCompiler: NextCompiler {
    var liteRecompiler = Recompiler()

    override func recompile(source: String, platform: String) ->  String? {
        return liteRecompiler.recompile(source: source, dylink: false)
    }
}
