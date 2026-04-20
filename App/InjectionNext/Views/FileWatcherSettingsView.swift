//
//  FileWatcherSettingsView.swift
//  InjectionNext
//
//  Injectable file pattern, watcher latency.
//

import SwiftUI

struct FileWatcherSettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Injectable Pattern (regex)") {
                    TextField("Pattern", text: $config.injectablePattern)
                        .textFieldStyle(.roundedBorder)
                }

                Button("Reset to Default") {
                    config.injectablePattern = #"[^~]\.(mm?|cpp|cc|swift|lock|o)$"#
                }
            } header: {
                Label("File Matching", systemImage: "doc.text.magnifyingglass")
            } footer: {
                Text("Regex pattern for files the watcher considers injectable. The default matches Swift, ObjC, and C++ source files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Latency")
                        Spacer()
                        Text(String(format: "%.2fs", config.fileWatcherLatency))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $config.fileWatcherLatency, in: 0.05...1.0, step: 0.05)
                }

                Button("Reset to Default (0.10s)") {
                    config.fileWatcherLatency = 0.1
                }
            } header: {
                Label("Watcher Timing", systemImage: "clock")
            } footer: {
                Text("Time in seconds the FSEvents watcher waits before reporting file changes. Lower values = faster response, higher values = fewer spurious events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
