//
//  TracingSettingsView.swift
//  InjectionNext
//
//  Trace mode picker, filter, frameworks, UIKit.
//

import SwiftUI

struct TracingSettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        Form {
            Section {
                Picker("Trace Mode", selection: $config.traceMode) {
                    ForEach(TraceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Function Tracing", systemImage: "waveform.path.ecg")
            } footer: {
                Text("\"Injected Functions\" traces only functions in injected files. \"All Functions\" traces every Swift function in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help("Enable function/method invocation tracing.")

            if config.traceMode != .off {
                Section {
                    TextField("Include Filter (regex)", text: $config.traceFilter)
                        .textFieldStyle(.roundedBorder)
                        .help("function calls logged can be filted by this regex")

                    TextField("Frameworks to Trace (comma-separated)", text: $config.traceFrameworks)
                        .textFieldStyle(.roundedBorder)
                        .help("Trace calls to system frameworks (1 = SwiftUI)")

                    TextField("UIKit Framework Name", text: $config.traceUIKit)
                        .textFieldStyle(.roundedBorder)
                        .help("System frameworks to trace (1 = UIKit)")

                    Toggle("Expand Custom Types in Trace", isOn: $config.traceLookup)
                        .help("App types used as arguments can be expanded")
                } header: {
                    Label("Trace Filters", systemImage: "line.3.horizontal.decrease.circle")
                } footer: {
                    Text("Filter controls which functions appear in the trace output. Framework tracing logs calls into the specified frameworks. UIKit tracing swizzles internal methods.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
