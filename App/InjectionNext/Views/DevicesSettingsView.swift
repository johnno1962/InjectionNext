//
//  DevicesSettingsView.swift
//  InjectionNext
//
//  Device injection toggle, codesigning identity, libraries.
//

import SwiftUI

struct DevicesSettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        Form {
            Section {
                Toggle("Enable Device Injection", isOn: $config.devicesEnabled)
                    .onChange(of: config.devicesEnabled) { newValue in
                        AppDelegate.ui?.applyDeviceSettings(enabled: newValue)
                    }
            } header: {
                Label("Device Support", systemImage: "iphone")
            } footer: {
                Text("When enabled, InjectionNext listens on all interfaces for device connections and sets up multicast for device discovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if config.availableIdentities.isEmpty {
                    Text("No codesigning identities found")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Codesigning Identity", selection: Binding(
                        get: { config.codesigningIdentity ?? "" },
                        set: { config.codesigningIdentity = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(config.availableIdentities, id: \.self) { identity in
                            Text(identity)
                                .lineLimit(1)
                                .tag(identity.sha1Component ?? identity)
                        }
                    }
                }

                Button("Refresh Identities") {
                    config.discoverCodesigningIdentities()
                }
            } header: {
                Label("Code Signing", systemImage: "lock.shield")
            }

            Section {
                TextField("Linker Libraries", text: $config.deviceLibraries)
                    .textFieldStyle(.roundedBorder)

                Button("Reset to Default") {
                    config.deviceLibraries = "-framework XCTest -lXCTestSwiftSupport"
                }
            } header: {
                Label("Device Libraries", systemImage: "books.vertical")
            } footer: {
                Text("Additional linker flags for device testing (e.g. XCTest frameworks).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private extension String {
    var sha1Component: String? {
        guard let range = range(of: #"[0-9A-F]{40}"#, options: .regularExpression) else { return nil }
        return String(self[range])
    }
}
