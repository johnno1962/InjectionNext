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
    
    /// Record of previously unhidden symbols by project and platform and their files
    static var unhiddens = [String: [String: [String: String]]]()
    /// One unhide at a time please
    static let unhideQueue = DispatchQueue(label: "Unhider")
    /// Last time specific object file was patched (no longrer used)
    static var lastUnhidden = [String: Date]()
    /// Used to determine the path to the project's DerivedData
    static var packageFrameworks: String?

    open class func log(_ msg: String) {
        InjectionServer.currentClient?.log(msg)
    }
    
    /// Entry point for user initiated or perhaps one day automatic unhiding.
    open class func startUnhide() {
        guard var derivedData = packageFrameworks.flatMap({
            URL(fileURLWithPath: $0) }) else {
            log("⚠️ packageFrameworks not set, view a Swift source.")
            return
        }
        for _ in 1...5 {
            derivedData = derivedData.deletingLastPathComponent()
        }
        unhideQueue.async {
            do {
                try Fortify.protect {
                    try unhideAllObjects(intermediates: derivedData
                        .appendingPathComponent("Build/Intermediates.noindex"))
                }
            } catch {
                log("⚠️ Unhide error: \(error)")
            }
        }
    }
    
    /// Unihide all objects in the current project's DerivedData's intermediate products
    open class func unhideAllObjects(intermediates: URL) throws {
        var patched = [String](), files = 0, project = intermediates.path
        var configs = unhiddens[project] ?? [String: [String: String]]()
        log("Starting \"unhide\" for "+project+"...")

        // Foreach module and platform.
        for module in try FileManager.default
            .contentsOfDirectory(atPath: project) {
            for config in (try? FileManager.default
                .contentsOfDirectory(atPath: intermediates
                    .appendingPathComponent(module).path)) ?? [] {
                // Track unhidden symbols for each platform to not unhide
                // one twice which risks duplicate symbols on linking.
                var unhidden = configs[config] ?? [String: String]()

                let platformPath = intermediates
                    .appendingPathComponent(module+"/"+config)
                let enumerator = FileManager.default
                    .enumerator(atPath: platformPath.path)
                // Foreach object file, unhide the symbols in it.
                while let path = enumerator?.nextObject() as? String {
                    guard path.hasSuffix(".o") else { continue }
                    patched += unhide(object: platformPath
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
    
    /// Unhide default argument generators in an object file (avoiding duplicates).
    open class func unhide(object path: String,
                           _ unhidden: inout [String: String]) -> [String] {
        guard let object = FileSymbols(path: path) else {
            log("⚠️ Could not load "+path)
            return []
        }

        var patched = [String](), global: UInt8 = 0xf
        for entry in object.entries.filter({
            let symbol = $0.symbol
            return $0.entry.pointee.n_sect != NO_SECT && // Is this a definition?
            symbol.hasPrefix("$s") && symbol[#"(A\d*_|M[cgn])$"#] && // Default arg?
            // Have we not seen this symbol before or previously seen it in this file
            (unhidden[symbol] == nil || unhidden[symbol] == path) }) {
            unhidden[entry.symbol] = path
            // If symbol is "private extern" patch to export it
            if entry.entry.pointee.n_type & UInt8(N_PEXT) != 0 {
                entry.entry.pointee.n_type = global
                entry.entry.pointee.n_desc = UInt16(N_GSYM)
                patched.append(entry.symbol)
            }
        }

        if patched.isEmpty { return [] }

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

        return patched
    }
}
