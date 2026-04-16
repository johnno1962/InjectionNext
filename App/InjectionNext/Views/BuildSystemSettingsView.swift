//
//  BuildSystemSettingsView.swift
//  InjectionNext
//
//  SPM / Bazel / Xcode build system picker and paths.
//

import SwiftUI

struct BuildSystemSettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        Form {
            Section {
                Picker("Build System", selection: $config.buildSystem) {
                    ForEach(BuildSystem.allCases) { system in
                        Text(system.rawValue).tag(system)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Build System", systemImage: "wrench.and.screwdriver")
            } footer: {
                Text("Select the build system used by your project. This affects how InjectionNext discovers compilation commands and recompiles files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if config.buildSystem == .bazel {
                Section {
                    LabeledContent("Bazel / Bazelisk Path") {
                        HStack {
                            TextField("e.g. /opt/homebrew/bin/bazelisk", text: $config.bazelPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse...") {
                                let open = NSOpenPanel()
                                open.prompt = "Select Bazel Binary"
                                open.canChooseFiles = true
                                open.canChooseDirectories = false
                                if open.runModal() == .OK, let path = open.url?.path {
                                    config.bazelPath = path
                                }
                            }
                        }
                    }

                    TextField("Bazel Target (optional)", text: $config.bazelTarget)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()

                    LabeledContent("Bazel Target") {
                        Text(config.bazelTarget.isEmpty ? "Auto-detected from client" : config.bazelTarget)
                            .foregroundStyle(config.bazelTarget.isEmpty ? .secondary : .primary)
                    }
                } header: {
                    Label("Bazel Configuration", systemImage: "cube")
                } footer: {
                    Text("InjectionNext detects Bazel workspaces via MODULE.bazel or WORKSPACE files. Specify a path to bazel/bazelisk if it's not in your standard PATH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("xcrun Path") {
                    HStack {
                        TextField("/usr/bin/xcrun", text: $config.xcrunPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            let open = NSOpenPanel()
                            open.prompt = "Select xcrun"
                            open.canChooseFiles = true
                            open.canChooseDirectories = false
                            if open.runModal() == .OK, let path = open.url?.path {
                                config.xcrunPath = path
                            }
                        }
                    }
                }
            } header: {
                Label("Tool Paths", systemImage: "terminal")
            }
        }
        .formStyle(.grouped)
    }
}
