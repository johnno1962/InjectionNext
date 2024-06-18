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
import Popen

open class Unhider {
    
    static var unhiddens = [String: [String: [String: String]]]()
    static let unhideQueue = DispatchQueue(label: "Unhider")
    static var lastUnhidden = [String: Date]()
    static var packageFrameworks: String?

    open class func log(_ msg: String) {
        InjectionServer.currentClient?.log(msg)
    }
    
    open class func startUnhide() {
        guard var derivedData = packageFrameworks.flatMap({
            URL(fileURLWithPath: $0) }) else {
            log("⚠️ packageFrameworks not set, view a Swift source.")
            return
        }
        for _ in 1...5 {
            derivedData = derivedData.deletingLastPathComponent()
        }
        let intermediates = derivedData
            .appendingPathComponent("Build/Intermediates.noindex")
        unhideQueue.async {
            do {
                try Fortify.protect {
                    var patched = [String](), files = 0, project = intermediates.path
                    var configs = unhiddens[project] ?? [String: [String: String]]()
                    log("Starting \"unhide\" for "+project+"...")

                    for module in try FileManager.default
                        .contentsOfDirectory(atPath: project) {
                        for config in (try? FileManager.default
                            .contentsOfDirectory(atPath: intermediates
                                .appendingPathComponent(module).path)) ?? [] {
                            var unhidden = configs[config] ?? [String: String]()

                            let platform = intermediates
                                .appendingPathComponent(module+"/"+config)
                            let enumerator = FileManager.default
                                .enumerator(atPath: platform.path)
                            while let path = enumerator?.nextObject() as? String {
                                guard path.hasSuffix(".o") else { continue }
                                patched += unhide(object: platform
                                    .appendingPathComponent(path).path, &unhidden)
                                files += 1
                            }

                            configs[config] = unhidden
                        }
                    }

                    unhiddens[project] = configs
                    log("\(patched.count) symbols exported in \(files)" +
                        " object files, please restart your app.")
                }
            } catch {
                log("⚠️ Unhide error: \(error)")
            }
        }
    }
    
    open class func unhide(object path: String, 
                           _ unhidden: inout [String: String]) -> [String] {
        guard let object = FileSymbols(path: path) else {
            log("⚠️ Could not load "+path)
            return []
        }

        var patched = [String](), global: UInt8 = 0xf
        for entry in object.entries.filter({
            $0.entry.pointee.n_sect != NO_SECT &&
            $0.symbol.hasPrefix("$s") && $0.symbol[#"A\d*_$"#] &&
            (unhidden[$0.symbol] == nil || unhidden[$0.symbol] == path) }) {
            unhidden[entry.symbol] = path
            if entry.entry.pointee.n_type & UInt8(N_PEXT) != 0 {
                entry.entry.pointee.n_type = global
                entry.entry.pointee.n_desc = UInt16(N_GSYM)
                patched.append(entry.symbol)
            }
        }

        if !patched.isEmpty {
            if !object.save(to: path) {
                log("⚠️ Could not save "+path)
            } else if let stat = Fstat(path: path) {
                if let written = lastUnhidden[path],
                   stat.modified != written {
                    log("\(patched.count) symbols re-exported in " +
                        URL(fileURLWithPath: path).lastPathComponent)
                }
                lastUnhidden[path] = stat.modified
            }
        }
        return patched
    }
}
