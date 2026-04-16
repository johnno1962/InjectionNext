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
                Toggle("Verbose Logging", isOn: $config.verboseLogging)
                Toggle("Benchmarking", isOn: $config.benchmarking)
            } header: {
                Label("Debug", systemImage: "ladybug")
            } footer: {
                Text("Verbose logging shows detailed binding steps. Benchmarking logs timing information for various operations.")
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
