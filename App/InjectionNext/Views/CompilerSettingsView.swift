//
//  CompilerSettingsView.swift
//  InjectionNext
//
//  Compiler interception toggle and frontend path.
//

import SwiftUI

struct CompilerSettingsView: View {
    @ObservedObject var config: ConfigStore

    var body: some View {
        let currentState = config.compilerState
        Form {
            Section {
                LabeledContent("Compiler State") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(currentState == .patched ? .green : .gray)
                            .frame(width: 10, height: 10)
                        Text(currentState == .patched ? "Intercepted (Patched)" : "Not Intercepted")
                    }
                }

                Button(currentState.rawValue) {
                    AppDelegate.ui.patchCompiler(NSMenuItem())
                    config.updateCompilerState()
                }

                LabeledContent("Frontend Binary") {
                    Text(FrontendServer.unpatchedURL.path.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(FrontendServer.unpatchedURL.path)
                }

                if currentState == .patched {
                    LabeledContent("Saved Binary") {
                        Text(FrontendServer.patched.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(FrontendServer.patched)
                    }
                }
            } header: {
                Label("Compiler Interception", systemImage: "chevron.left.forwardslash.chevron.right")
            } footer: {
                Text("When intercepted, swift-frontend is replaced by a script that captures all compilation commands. This enables recompilation when you save a file. Use \"Unpatch Compiler\" to revert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Emit Frontend Command Lines (Xcode 16.3+)", isOn: $config.emitFrontendCommandLines)
            } header: {
                Label("Build Settings", systemImage: "gearshape")
            } footer: {
                Text("When enabled, sets EMIT_FRONTEND_COMMAND_LINES build setting for per-compilation logging in Xcode 16.3+.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .help("Information about whether xcode-frontend logs compilations")
    }
}
