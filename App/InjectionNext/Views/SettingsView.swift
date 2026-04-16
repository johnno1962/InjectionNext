//
//  SettingsView.swift
//  InjectionNext
//
//  Main settings window with tabbed sections.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        TabView {
            GeneralSettingsView(config: config)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            XcodeSettingsView(config: config)
                .tabItem {
                    Label("Xcode", systemImage: "hammer")
                }

            BuildSystemSettingsView(config: config)
                .tabItem {
                    Label("Build", systemImage: "wrench.and.screwdriver")
                }

            CompilerSettingsView(config: config)
                .tabItem {
                    Label("Compiler", systemImage: "chevron.left.forwardslash.chevron.right")
                }

            InjectionSettingsView(config: config)
                .tabItem {
                    Label("Injection", systemImage: "bolt.circle")
                }

            DevicesSettingsView(config: config)
                .tabItem {
                    Label("Devices", systemImage: "iphone")
                }

            TracingSettingsView(config: config)
                .tabItem {
                    Label("Tracing", systemImage: "waveform.path.ecg")
                }

            FileWatcherSettingsView(config: config)
                .tabItem {
                    Label("Watcher", systemImage: "eye")
                }

            NetworkSettingsView(config: config)
                .tabItem {
                    Label("Network", systemImage: "network")
                }

            AdvancedSettingsView(config: config)
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
        }
        .frame(minWidth: 650, minHeight: 450)
    }
}
