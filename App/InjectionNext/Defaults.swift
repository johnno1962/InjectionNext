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
    static let xcodePathDefault = "XcodePath"
    static let librariesDefault = "libraries"
    static let codesigningDefault = "codesigningIdentity"
    static var xcodePath: String {
        get {
            appDelegate.defaults.string(forKey: xcodePathDefault) ??
                "/Applications/Xcode.app"
        }
        set {
            appDelegate.defaults.setValue(newValue, 
                                          forKey: xcodePathDefault)
        }
    }
    static var deviceLibraries: String {
        get {
            appDelegate.defaults.string(forKey: librariesDefault) ??
                "-framework XCTest -lXCTestSwiftSupport"
        }
        set {
            appDelegate.defaults.setValue(newValue,
                                          forKey: librariesDefault)
        }
    }
    static var codesigningIdentity: String? {
        get {
            appDelegate.defaults.string(forKey: codesigningDefault)
        }
        set {
            appDelegate.defaults.setValue(newValue, 
                                          forKey: codesigningDefault)
        }
    }
}
