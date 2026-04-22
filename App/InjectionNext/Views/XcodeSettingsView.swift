//
//  XcodeSettingsView.swift
//  InjectionNext
//
//  Xcode path picker, launch behavior, restart on crash.
//

import SwiftUI

struct XcodeSettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        Form {
            Section {
                if config.availableXcodes.isEmpty {
                    LabeledContent("Xcode Path") {
                        HStack {
                            Text(config.xcodePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            browseButton
                        }
                    }
                    .help("Path to Xcode launched by this app")
                } else {
                    Picker("Xcode", selection: $config.xcodePath) {
                        ForEach(config.availableXcodes) { xcode in
                            Text(xcode.displayName)
                                .tag(xcode.path)
                        }
                    }
                    .onChange(of: config.xcodePath) { _ in
                        AppDelegate.ui?.updatePatchUnpatch()
                    }
                    .help("Select path to valid Xcode")

                    HStack {
                        Spacer()
                        browseButton
                        Button("Refresh") {
                            config.discoverXcodes()
                        }
                    }
                }

                LabeledContent("Selected Path") {
                    Text(config.xcodePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .help("Currently selected path to Xcode.app")
            } header: {
                Label("Xcode Installation", systemImage: "hammer")
            }

            Section {
                Toggle("Auto-launch Xcode on app start", isOn: $config.autoLaunchXcode)
                Toggle("Restart Xcode if it crashes", isOn: $config.xcodeRestart)
                    .help("Restart Xcode if it does not exit cleanly")
                Toggle("Hide initial Xcode alert", isOn: $config.hideXcodeAlert)
                    .help("Suppress initial hint to launch Xcode")
            } header: {
                Label("Launch Behavior", systemImage: "play.circle")
            } footer: {
                Text("When auto-launch is enabled, InjectionNext will start the selected Xcode with SOURCEKIT_LOGGING when the app launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Launched Xcode") {
                    HStack {
                        Circle()
                            .fill(config.haveLaunchedXcode ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(config.haveLaunchedXcode ? "Running" : "Not Running")
                    }
                }
                .help("Was Xcode launched by this app")
                Button("Launch Xcode Now") {
                    AppDelegate.ui?.runXcode(self)
                }
                .disabled(config.haveLaunchedXcode)
                .help("Launch Xcode if it isn’t already running")
            } header: {
                Label("Status", systemImage: "info.circle")
            }
        }
        .formStyle(.grouped)
    }

    private var browseButton: some View {
        Button("Browse...") {
            let open = NSOpenPanel()
            open.prompt = "Select Xcode"
            open.directoryURL = URL(fileURLWithPath: "/Applications")
            open.canChooseDirectories = false
            open.canChooseFiles = true
            open.allowedContentTypes = [.application]
            if open.runModal() == .OK, let path = open.url?.path {
                config.xcodePath = path
                config.discoverXcodes()
            }
        }
    }
}
