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
                    TextField("Include Filter (regex)",
                              text: $config.traceFilter)
                        .textFieldStyle(.roundedBorder)
                        .help("Filter function call traces by this regex.")

                    TextField("Trace calls to Frameworks\n(comma-separated, 1 = SwiftUI)",
                              text: $config.traceFrameworks)
                        .textFieldStyle(.roundedBorder)
                        .help("Trace calls to system/local frameworks")

                    TextField("Trace Frameworks named (1 = UIKit)",
                              text: $config.traceUIKit)
                        .textFieldStyle(.roundedBorder)
                        .help("Objective-C system frameworks to trace")

                    Toggle("Expand Custom Types in Trace",
                           isOn: $config.traceLookup)
                        .help("Expand App types used as arguments")
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
