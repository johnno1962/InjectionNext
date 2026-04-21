//
//  GeneralSettingsView.swift
//  InjectionNext
//
//  Version info, build number, about section.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        Form {
            Section {
                LabeledContent("App Name", value: "InjectionNext")
                LabeledContent("Version", value: config.appVersion)
                LabeledContent("Build Number", value: config.buildNumber)
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "?")
            } header: {
                Label("Application Info", systemImage: "info.circle")
            }

            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 10, height: 10)
                        Text(config.injectionState.rawValue)
                    }
                }
                LabeledContent("Xcode Running", value: config.haveLaunchedXocde ? "Yes" : "No")
                LabeledContent("Client Connected", value: config.isClientConnected ? "Yes" : "No")

                if !config.watchingDirectories.isEmpty {
                    LabeledContent("Watching") {
                        VStack(alignment: .trailing) {
                            ForEach(config.watchingDirectories, id: \.self) { dir in
                                Text(dir)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                } else {
                    LabeledContent("Watching", value: "None")
                }
            } header: {
                Label("Runtime Status", systemImage: "bolt.fill")
            }

            Section {
                LabeledContent("Author", value: "John Holdsworth")
                LabeledContent("License", value: "MIT")
                Link("GitHub Repository", destination: URL(string: "https://github.com/johnno1962/InjectionNext")!)
            } header: {
                Label("About", systemImage: "person.circle")
            }
        }
        .formStyle(.grouped)
    }

    private var stateColor: Color {
        switch config.injectionState {
        case .idle: return .blue
        case .ok: return .orange
        case .busy: return .purple
        case .ready: return .green
        case .error: return .red
        }
    }
}
