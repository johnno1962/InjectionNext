//
//  NetworkSettingsView.swift
//  InjectionNext
//
//  Host, port display, multicast info.
//

import SwiftUI

struct NetworkSettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        Form {
            Section {
                LabeledContent("Injection Host") {
                    TextField("127.0.0.1", text: $config.injectionHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                LabeledContent("Injection Port", value: config.injectionPort)
                LabeledContent("Control Server Port", value: "\(config.controlPort)")
            } header: {
                Label("Connection", systemImage: "network")
            } footer: {
                Text("The injection host is the IP clients use to connect. Default 127.0.0.1 for local development. For device injection, use your Mac's IP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Client Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(config.isClientConnected ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(config.isClientConnected ? "Connected" : "Not Connected")
                    }
                }
            } header: {
                Label("Status", systemImage: "antenna.radiowaves.left.and.right")
            }

            Section {
                LabeledContent("Protocol Version", value: "\(INJECTION_VERSION)")
                LabeledContent("Commands Port") {
                    Text(COMMANDS_PORT)
                        .font(.caption.monospaced())
                }
            } header: {
                Label("Protocol Info", systemImage: "doc.text")
            }
        }
        .formStyle(.grouped)
    }
}
