//
//  AdvancedSettingsView.swift
//  InjectionNext
//
//  Debug flags, benchmarking, env overrides, reset all.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var config: ConfigStore
    @Environment(\.openWindow) private var openWindow
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker("dlopen Mode", selection: $config.dlOpenMode) {
                    ForEach(DLOpenMode.allCases) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                            Text(mode.shortDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .help(config.dlOpenMode.helpText)

                Text(config.dlOpenMode.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Label("Dynamic Loader", systemImage: "square.stack.3d.up")
            } footer: {
                Text("Flags passed to dlopen() when DLKit loads each injected dylib. Change this only if injections are failing to resolve symbols or you want eager error reporting. Maps to DLKit.dlOpenMode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            /* Realised using environment variables picked up by SPM */
            Section {
                Toggle("Preserve Static Variables", isOn: $config.preserveStatics)
                    .help("Static variables retained over injections")
                Toggle("Disable Standalone Mode﹡", isOn: $config.disableStandalone)
                    .help("Prevent injection from starting connectionless")
            } header: {
                Label("Injection Behavior", systemImage: "bolt.circle")
            } footer: {
                Text("\"Preserve Statics\" keeps static/top-level variable values across injections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Generics Injection﹡", selection: $config.genericsMode) {
                    ForEach(GenericsMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Key Paths﹡", selection: $config.keyPathsMode) {
                    ForEach(KeyPathsMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            } header: {
                Label("Generic & Key Path Support", systemImage: "chevron.left.forwardslash.chevron.right")
            } footer: {                Text("Auto mode detects TCA usage and adjusts key path hooking automatically. Legacy generics uses object sweep; new mode doesn't require it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Last Compilation Error") {
                    Text(NextCompiler.lastError ?? "None")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Button("Open Console") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "console")
                }

                Button("Unhide Symbols") {
                    Unhider.startUnhide()
                }
                .help("Process object files to export generators used for default arguments")

                Button("Reset Unhiding") {
                    Unhider.unhiddens.removeAll()
                }
            } header: {
                Label("Diagnostics", systemImage: "stethoscope")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Environment Variable Reference")
                        .font(.headline)

                    Group {
                        envRow("INJECTION_HOST", "IP for device connection", "192.168.1.42")
                        envRow("INJECTION_DIRECTORIES", "Directories to watch", "~/Projects/MyApp,~/Projects/Shared")
                        envRow("INJECTION_PROJECT_ROOT", "Project root for file watching", "~/Projects/MyApp")
                        envRow("INJECTION_PRESERVE_STATICS", "Preserve static vars", "1")
                        envRow("BUILD_WORKSPACE_DIRECTORY", "Bazel workspace directory", "~/Projects/MyApp")
                        envRow("INJECTION_TRACE", "Enable function tracing", "1")
                        envRow("INJECTION_DETAIL", "Verbose binding log", "1")
                        envRow("INJECTION_BENCH", "Enable benchmarking", "1")
                        envRow("INJECTION_HIDE_XCODE_ALERT", "Suppress initial alert", "1")
                    }
                }
            } header: {
                Label("Environment Variables", systemImage: "terminal")
            } footer: {
                Text("These environment variables can be set in your Xcode scheme to override settings at runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings to Defaults") {
                    showResetConfirmation = true
                }
                .foregroundStyle(.red)
                .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        config.resetAllSettings()
                    }
                } message: {
                    Text("This will reset all InjectionNext settings to their default values. This cannot be undone.")
                }
            } header: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
        }
        .formStyle(.grouped)
    }

    private func envRow(_ key: String, _ desc: String, _ example: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Text("e.g. \(example)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
