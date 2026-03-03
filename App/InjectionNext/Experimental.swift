//
//  Experimental.swift
//  InjectionIII
//
//  Created by User on 20/10/2020.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  $Id: //depot/HotReloading/Sources/injectiond/Experimental.swift#35 $
//
//  Some regular expressions to automatically prepare SwiftUI sources.
//
import Cocoa
import SwiftRegex

extension AppDelegate {

    /// Prepare the SwiftUI source file currently being edited for injection.
    @IBAction func prepareSource(_ sender: NSMenuItem) {
        if let lastSource = NextCompiler.lastSource {
            prepareSwiftUI(source: lastSource)
        }
    }

    /// Prepare all sources in the current target for injection.
    @IBAction func prepareProject(_ sender: NSMenuItem) {
        var changes = 0, edited = 0
        for source in ((MonitorXcode.runningXcode != nil ?
                        MonitorXcode.recompiler.lastCompilation : nil) ??
                       FrontendServer.frontendRecompiler().lastCompilation)?
            .swiftFiles.components(separatedBy: "\n").dropLast() ??
                       Array(Recompiler.workspaceCache.keys) {
            InjectionHybrid.lastInjected[source] = Date.timeIntervalSinceReferenceDate
            prepareSwiftUI(source: source, changes: &changes)
            edited += 1
        }
        let s = changes == 1 ? "" : "s"
        InjectionServer.error("\(changes) automatic edit\(s) made to \(edited) files")
    }
}
