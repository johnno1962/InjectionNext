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
            } header: {
                Label("Xcode Installation", systemImage: "hammer")
            }

            Section {
                Toggle("Auto-launch Xcode on app start", isOn: $config.autoLaunchXcode)
                Toggle("Restart Xcode if it crashes", isOn: $config.xcodeRestart)
                Toggle("Hide initial Xcode alert", isOn: $config.hideXcodeAlert)
            } header: {
                Label("Launch Behavior", systemImage: "play.circle")
            } footer: {
                Text("When auto-launch is enabled, InjectionNext will start the selected Xcode with SOURCEKIT_LOGGING when the app launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Xcode Running") {
                    HStack {
                        Circle()
                            .fill(config.haveLaunchedXocde ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(config.haveLaunchedXocde ? "Running" : "Not Running")
                    }
                }
                Button("Launch Xcode Now") {
                    AppDelegate.ui?.runXcode(self)
                }
                .disabled(config.haveLaunchedXocde)
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
