//
//  SettingsView.swift
//  InjectionNext
//
//  Main settings window with sidebar navigation (macOS System Settings style).
//

import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, xcode, build, compiler, injection, devices, tracing, watcher, network, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .xcode: return "Xcode"
        case .build: return "Build"
        case .compiler: return "Compiler"
        case .injection: return "Injection"
        case .devices: return "Devices"
        case .tracing: return "Tracing"
        case .watcher: return "Watcher"
        case .network: return "Network"
        case .advanced: return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .xcode: return "hammer"
        case .build: return "wrench.and.screwdriver"
        case .compiler: return "chevron.left.forwardslash.chevron.right"
        case .injection: return "bolt.circle"
        case .devices: return "iphone"
        case .tracing: return "waveform.path.ecg"
        case .watcher: return "eye"
        case .network: return "network"
        case .advanced: return "gearshape.2"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .xcode: return .blue
        case .build: return .orange
        case .compiler: return .purple
        case .injection: return .yellow
        case .devices: return .green
        case .tracing: return .pink
        case .watcher: return .teal
        case .network: return .indigo
        case .advanced: return .red
        }
    }
}

struct SettingsView: View {
    @ObservedObject var config: ConfigStore
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(section.tint.gradient)
                            Image(systemName: section.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 20, height: 20)

                        Text(section.title)
                            .font(.system(size: 13))
                    }
                    .padding(.vertical, 1)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .listStyle(.sidebar)
        } detail: {
            detailView(for: selection)
                .navigationTitle(selection.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 780, minHeight: 520)
    }

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralSettingsView(config: config)
        case .xcode: XcodeSettingsView(config: config)
        case .build: BuildSystemSettingsView(config: config)
        case .compiler: CompilerSettingsView(config: config)
        case .injection: InjectionSettingsView(config: config)
        case .devices: DevicesSettingsView(config: config)
        case .tracing: TracingSettingsView(config: config)
        case .watcher: FileWatcherSettingsView(config: config)
        case .network: NetworkSettingsView(config: config)
        case .advanced: AdvancedSettingsView(config: config)
        }
    }
}
