//
//  AdvancedSettingsView.swift
//  InjectionNext
//
//  Debug flags, benchmarking, env overrides, reset all.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var config: ConfigStore
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

                Button("Show Full Error") {
                    let error = NextCompiler.lastError ?? "No error."
                    let alert = NSAlert()
                    alert.messageText = "Last Compilation Error"
                    alert.informativeText = error
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
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
                        envRow("INJECTION_HOST", "IP for device connection")
                        envRow("INJECTION_DIRECTORIES", "Directories to watch")
                        envRow("INJECTION_PROJECT_ROOT", "Project root for file watching")
                        envRow("INJECTION_PRESERVE_STATICS", "Preserve static vars")
                        envRow("BUILD_WORKSPACE_DIRECTORY", "Bazel workspace directory")
                        envRow("INJECTION_TRACE", "Enable function tracing")
                        envRow("INJECTION_DETAIL", "Verbose binding log")
                        envRow("INJECTION_BENCH", "Enable benchmarking")
                        envRow("INJECTION_HIDE_XCODE_ALERT", "Suppress initial alert")
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

    private func envRow(_ key: String, _ desc: String) -> some View {
        HStack {
            Text(key)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
            Spacer()
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
