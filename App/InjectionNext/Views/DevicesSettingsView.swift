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
                Toggle("Enable Device Testing", isOn: $config.deviceTesting)
                    .onChange(of: config.deviceTesting) { newValue in
                        AppDelegate.ui?.deviceTestingToggled(enabled: newValue)
                    }

                TextField("Linker Libraries", text: $config.deviceLibraries)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!config.deviceTesting)

                Button("Reset to Default") {
                    config.deviceLibraries = "-framework XCTest -lXCTestSwiftSupport"
                }
                .disabled(!config.deviceTesting)
            } header: {
                Label("On-Device Testing", systemImage: "testtube.2")
            } footer: {
                Text("Only enable if you've added the copy_bundle.sh Run Script build phase to your target. When on, the injection dylib is linked with the libraries below (XCTest + helpers). Apps that don't link XCTest themselves will crash at dlopen (\"Library not loaded: @rpath/XCTest.framework/XCTest\") if this is on but copy_bundle.sh isn't shipping the frameworks.")
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
