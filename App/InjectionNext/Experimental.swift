//
//  Experimental.swift
//  InjectionIII
//
//  Created by User on 20/10/2020.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  $Id: //depot/HotReloading/Sources/injectiond/Experimental.swift#35 $
//

import Cocoa
import SwiftRegex

extension AppDelegate {

    @IBAction func prepareSource(_ sender: NSMenuItem) {
        if let lastSource = MonitorXcode.runningXcode?.lastSource {
            prepare(source: lastSource)
        }
    }

    @IBAction func prepareProject(_ sender: NSMenuItem) {
        for source in MonitorXcode.runningXcode?.lastFilelist?
            .components(separatedBy: "\n").dropLast() ?? [] {
            prepare(source: source)
        }
    }
    
    func prepare(source: String) {
        let fileURL = URL(fileURLWithPath: source)
        guard let original = try? String(contentsOf: fileURL) else {
            return
        }

        var patched = original
        patched[#"""
            ^((\s+)(public )?(var body:|func body\([^)]*\) -\>) some View \{\n\#
            (\2(?!    (if|switch|ForEach) )\s+(?!\.enableInjection)\S.*\n|\s*\n)+)(?<!#endif\n)\2\}\n
            """#.anchorsMatchLines] = """
            $1$2    .enableInjection()
            $2}

            $2#if DEBUG
            $2@ObserveInjection var forceRedraw
            $2#endif

            """

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

                public let injectionObserver = InjectionObserver()

                public class InjectionObserver: ObservableObject {
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
                            .onReceive(injectionObserver.publisher, perform: bumpState)
                            .eraseToAnyView()
                    }
                }

                @available(iOS 13.0, *)
                @propertyWrapper
                public struct ObserveInjection: DynamicProperty {
                    @ObservedObject private var iO = injectionObserver
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

                @available(iOS 13.0, *)
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
