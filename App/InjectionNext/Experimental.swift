//
//  Experimental.swift
//  InjectionIII
//
//  Created by User on 20/10/2020.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  $Id: //depot/HotReloading/Sources/injectiond/Experimental.swift#35 $
//
//  Some regular expressions to automatically prepare SwiftU sources.
//
import Cocoa
import SwiftRegex

extension AppDelegate {
    
    /// Prepare the SwiftUI source file currently being edited for injection.
    @IBAction func prepareSource(_ sender: NSMenuItem) {
        if let lastSource = MonitorXcode.runningXcode?.lastSource {
            prepare(source: lastSource)
        }
    }

    /// Prepare all sources in the current target for injection.
    @IBAction func prepareProject(_ sender: NSMenuItem) {
        var changes = 0, edited = 0
        for source in (MonitorXcode.runningXcode?.lastFilelist ??
                       CommandServer.lastFilelist)?
            .components(separatedBy: "\n").dropLast() ?? [] {
            CommandServer.platformRecompiler
                .lastInjected[source] = Date().timeIntervalSince1970
            prepare(source: source, changes: &changes)
            edited += 1
        }
        let s = changes == 1 ? "" : "s"
        InjectionServer.error("\(changes) automatic edit\(s) made to \(edited) files")
    }
    
    /// Use regular expresssions to patch .enableInjection() and @ObserveInject into a source
    func prepare(source: String, changes: UnsafeMutablePointer<Int>? = nil) {
        let fileURL = URL(fileURLWithPath: source)
        guard let original = try? String(contentsOf: fileURL) else {
            return
        }

        var patched = original, before = changes?.pointee
        patched[#"""
            ^((\s+)(public )?(var body:|func body\([^)]*\) -\>) some View \{\n\#
            (\2(?!    (if|switch|ForEach) )\s+(?!\.enableInjection)\S.*\n|(\s*|#.+)\n)+)(?<!#endif\n)\2\}\n
            """#.anchorsMatchLines, count: changes] = """
            $1$2    .enableInjection()
            $2}

            $2#if DEBUG
            $2@ObserveInjection var forceRedraw
            $2#endif

            """
        if changes?.pointee != before {
            print("Patched", source)
        }

        if (patched.contains("class AppDelegate") ||
            patched.contains("@main\n")) &&
            !patched.contains("InjectionObserver") {
            if !patched.contains("import SwiftUI") {
                patched += "\nimport SwiftUI\n"
            }

            patched += """

                #if canImport(HotSwiftUI)
                @_exported import HotSwiftUI
                #elseif canImport(Inject)
                @_exported import Inject
                #else
                // This code can be found in the Swift package:
                // https://github.com/johnno1962/HotSwiftUI or
                // https://github.com/krzysztofzablocki/Inject

                #if DEBUG
                import Combine

                public class InjectionObserver: ObservableObject {
                    public static let shared = InjectionObserver()
                    @Published var injectionNumber = 0
                    var cancellable: AnyCancellable? = nil
                    let publisher = PassthroughSubject<Void, Never>()
                    init() {
                        cancellable = NotificationCenter.default.publisher(for:
                            Notification.Name("INJECTION_BUNDLE_NOTIFICATION"))
                            .sink { [weak self] change in
                            self?.injectionNumber += 1
                            self?.publisher.send()
                        }
                    }
                }

                extension SwiftUI.View {
                    public func eraseToAnyView() -> some SwiftUI.View {
                        return AnyView(self)
                    }
                    public func enableInjection() -> some SwiftUI.View {
                        return eraseToAnyView()
                    }
                    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
                        return self
                            .onReceive(InjectionObserver.shared.publisher, perform: bumpState)
                            .eraseToAnyView()
                    }
                }

                @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
                @propertyWrapper
                public struct ObserveInjection: DynamicProperty {
                    @ObservedObject private var iO = InjectionObserver.shared
                    public init() {}
                    public private(set) var wrappedValue: Int {
                        get {0} set {}
                    }
                }
                #else
                extension SwiftUI.View {
                    @inline(__always)
                    public func eraseToAnyView() -> some SwiftUI.View { return self }
                    @inline(__always)
                    public func enableInjection() -> some SwiftUI.View { return self }
                    @inline(__always)
                    public func onInjection(bumpState: @escaping () -> ()) -> some SwiftUI.View {
                        return self
                    }
                }

                @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
                @propertyWrapper
                public struct ObserveInjection {
                    public init() {}
                    public private(set) var wrappedValue: Int {
                        get {0} set {}
                    }
                }
                #endif
                #endif

                """
        }

        if patched != original {
            do {
                try patched.write(to: fileURL,
                                  atomically: false, encoding: .utf8)
            } catch {
                InjectionServer.currentClient?
                    .error("Could not save \(source): \(error)")
            }
        }
    }
}
