//
//  InjectionNextApp.swift
//  InjectionNext
//
//  SwiftUI app entry point replacing main.m + MainMenu.xib.
//

import SwiftUI

@main
struct InjectionNextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var config = ConfigStore.shared

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(config: config)
        } label: {
            Image(nsImage: config.statusIcon)
        }

        Window("InjectionNext Settings", id: "settings") {
            SettingsView(config: config)
        }
        .defaultSize(width: 640, height: 480)
        .windowResizability(.contentMinSize)

        Window("InjectionNext Console", id: "console") {
            ConsoleView()
        }
        .defaultSize(width: 900, height: 520)
        .windowResizability(.contentMinSize)
    }
}
