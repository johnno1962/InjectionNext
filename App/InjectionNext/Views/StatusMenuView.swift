//
//  StatusMenuView.swift
//  InjectionNext
//
//  SwiftUI menu bar dropdown replacing MainMenu.xib status menu.
//

import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var config: ConfigStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("InjectionNext v\(config.appVersion) (build \(config.buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button {
                AppDelegate.ui?.runXcode(self)
            } label: {
                HStack {
                    Text("Launch Xcode")
                    if config.isXcodeRunning {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            Button {
                let open = NSOpenPanel()
                open.prompt = "Select Project Directory"
                open.canChooseDirectories = true
                open.canChooseFiles = false
                if open.runModal() == .OK, let url = open.url {
                    Reloader.xcodeDev = config.xcodePath + "/Contents/Developer"
                    AppDelegate.ui.watch(path: url.path)
                    config.updateWatchingDirectories()
                }
            } label: {
                HStack {
                    Text(config.watchingDirectories.isEmpty ? "Watch Project..." : "Watch Another...")
                    if !config.watchingDirectories.isEmpty {
                        Spacer()
                        Image(systemName: "eye.fill")
                    }
                }
            }

            if !config.watchingDirectories.isEmpty {
                Button("Stop Watching") {
                    AppDelegate.watchers.removeAll()
                    AppDelegate.lastWatched = nil
                    config.updateWatchingDirectories()
                }

                ForEach(config.watchingDirectories, id: \.self) { dir in
                    Text("  \(URL(fileURLWithPath: dir).lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button(config.compilerState == .patched ? "Unpatch Compiler" : "Intercept Compiler") {
                AppDelegate.ui.patchCompiler(NSMenuItem())
            }

            Button("Unhide Symbols") {
                Unhider.startUnhide()
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "console")
            } label: {
                Label("Open Console…", systemImage: "terminal")
            }

            Divider()

            if #available(macOS 14.0, *) {
                SettingsLink {
                    Text("Settings...")
                }
                .keyboardShortcut(",", modifiers: .command)
            } else {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            Divider()

            Label {
                Text(config.isClientConnected ? "Client Connected" : "No Client")
            } icon: {
                Image(nsImage: Self.coloredDot(config.isClientConnected ? .systemGreen : .systemGray))
            }

            Label {
                Text("Status: \(config.injectionState.rawValue)")
            } icon: {
                Image(nsImage: Self.coloredDot(stateNSColor))
            }

            Divider()

            Button("Quit InjectionNext") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var stateColor: Color {
        switch config.injectionState {
        case .ok: return .orange
        case .idle: return .blue
        case .busy: return .green
        case .ready: return .purple
        case .error: return .yellow
        }
    }

    private var stateNSColor: NSColor {
        switch config.injectionState {
        case .ok: return .systemOrange
        case .idle: return .systemBlue
        case .busy: return .systemGreen
        case .ready: return .systemPurple
        case .error: return .systemYellow
        }
    }

    private static func coloredDot(_ color: NSColor, size: CGFloat = 10) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

}
