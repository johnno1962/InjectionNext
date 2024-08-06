//
//  Defaults.swift
//  InjectionNext
//
//  Created by John Holdsworth on 24/07/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//

import Foundation

struct Defaults {
    /// App deauflts for persistent state
    static let userDefaults = UserDefaults.standard
    static let xcodePathDefault = "XcodePath"
    static let librariesDefault = "libraries"
    static let codesigningDefault = "codesigningIdentity"
    private static let xcodeRestartDefault = "xcodeRestartDefault"
    static var xcodePath: String {
        get {
            userDefaults.string(forKey: xcodePathDefault) ??
                "/Applications/Xcode.app"
        }
        set {
            userDefaults.setValue(newValue,
                                  forKey: xcodePathDefault)
        }
    }
    static var deviceLibraries: String {
        get {
            userDefaults.string(forKey: librariesDefault) ??
                "-framework XCTest -lXCTestSwiftSupport"
        }
        set {
            userDefaults.setValue(newValue,
                                  forKey: librariesDefault)
        }
    }
    static var codesigningIdentity: String? {
        get {
            userDefaults.string(forKey: codesigningDefault)
        }
        set {
            userDefaults.setValue(newValue,
                                  forKey: codesigningDefault)
        }
    }   

    static var xcodeRestart: Bool {
        get {
            if userDefaults.value(forKey: xcodeRestartDefault) == nil { return true }
            return userDefaults.bool(forKey: xcodeRestartDefault)
        }
        set {
            userDefaults.setValue(newValue,
                                  forKey: xcodeRestartDefault)
        }
    }
}
