//
//  Unhider.swift
//  InjectionNext
//
//  Created by John H on 11/06/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//
//  In Swift "default argument generators" are emitted "private external"
//  which means you can link against them but not dynamic link against them.
//  This code exports these symbols in all object files in the derived data
//  of a project so code which uses a default argument is able to inject.
//
import Foundation
import SwiftRegex
import Fortify
import DLKit

open class Unhider {
    
    static var packageFrameworks: String?
    static let unhideQueue = DispatchQueue(label: "Unhider")
    
    open class func log(_ msg: String) {
        InjectionServer.currentClient?.log(msg)
    }
    
    open class func startUnhide() {
        guard var derivedData = packageFrameworks.flatMap({
            URL(fileURLWithPath: $0) }) else { return }
        for _ in 1...5 {
            derivedData = derivedData.deletingLastPathComponent()
        }
        let intermediates = derivedData
            .appendingPathComponent("Build/Intermediates.noindex")
        unhideQueue.sync {
            do {
                try Fortify.protect {
                    log("Starting \"unhide\" for "+intermediates.path)
                    var unhidden = Set<String>(), files = 0
                    let enumerator = FileManager.default
                        .enumerator(atPath: intermediates.path)
                    while let path = enumerator?.nextObject() as? String {
                        guard path.hasSuffix(".o") else { continue }
                        unhide(object: intermediates
                            .appendingPathComponent(path).path, &unhidden)
                        files += 1
                    }
                    log("""
                        Exported \(unhidden.count) symbols \
                        in \(files) files, restart app.
                        """)
                }
            } catch {
                log("⚠️ Unhide error: \(error)")
            }
        }
    }
    
    open class func unhide(object path: String, _ unhidden: inout Set<String>) {
        guard let object = FileSymbols(path: path) else {
            log("⚠️ Could not load "+path)
            return
        }

        var patched = 0, global: UInt8 = 0xf
        for entry in object.entries.filter({
            $0.name[strlen($0.name)-1] == UInt8(ascii: "_") &&
            $0.symbol[#"A\d*_$"#] && unhidden.insert($0.symbol).inserted }) {
            if entry.entry.pointee.n_type & UInt8(N_PEXT) != 0 {
                entry.entry.pointee.n_type = global
                entry.entry.pointee.n_desc = UInt16(N_GSYM)
                patched += 1
            }
        }
       
        if patched != 0 && !object.save(to: path) {
            log("⚠️ Could not save "+path)
        }
    }
}
