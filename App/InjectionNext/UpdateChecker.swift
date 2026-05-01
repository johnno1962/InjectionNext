//
//  UpdateChecker.swift
//  InjectionNext
//
//  Checks GitHub releases for a newer non-RC version and offers
//  to open the release page in the user's browser.
//

import AppKit

enum UpdateChecker {

    // MARK: - GitHub Releases API

    private struct Release: Decodable {
        let tag_name: String
        let prerelease: Bool
        let html_url: String
    }

    // MARK: - Public entry point

    /// Fetches https://api.github.com/repos/johnno1962/InjectionNext/releases,
    /// finds the latest non-RC tag whose semver is strictly greater than the
    /// running app's CFBundleShortVersionString, and – if one exists – presents
    /// an NSAlert offering to open the release page. Safe to call from any thread.
    static func checkForUpdates() {
        let currentVersion = Bundle.main
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"

        let url = URL(string:
            "https://api.github.com/repos/johnno1962/InjectionNext/releases")!
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: req) { data, _, error in
            guard let data, error == nil else {
                DispatchQueue.main.async { showError(error?.localizedDescription ?? "No data") }
                return
            }
            do {
                let releases = try JSONDecoder().decode([Release].self, from: data)
                handle(releases: releases, currentVersion: currentVersion)
            } catch {
                DispatchQueue.main.async { showError(error.localizedDescription) }
            }
        }.resume()
    }

    // MARK: - Private helpers

    private static func handle(releases: [Release], currentVersion: String) {
        // Filter: published (not prerelease) and tag does not look like an RC
        // (i.e. the tag_name must not contain "-rc" case-insensitively).
        let stable = releases.filter {
            !$0.prerelease && !$0.tag_name.lowercased().contains("rc")
        }

        // Find the newest tag that is strictly > currentVersion by semver.
        guard let newest = stable
            .compactMap({ r -> (version: String, url: String)? in
                let v = normaliseTag(r.tag_name)
                guard semverCompare(v, isGreaterThan: currentVersion) else { return nil }
                return (v, r.html_url)
            })
            .sorted(by: { semverCompare($0.version, isGreaterThan: $1.version) })
            .first
        else {
            // Nothing newer – tell the user only when they explicitly asked.
            DispatchQueue.main.async { showUpToDate(current: currentVersion) }
            return
        }

        DispatchQueue.main.async { offerUpdate(to: newest.version, url: newest.url) }
    }

    /// Strips a leading "v" so both "v1.2.3" and "1.2.3" compare correctly.
    private static func normaliseTag(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Returns true when `lhs` > `rhs` by semver (numeric component comparison).
    private static func semverCompare(_ lhs: String, isGreaterThan rhs: String) -> Bool {
        let l = components(lhs)
        let r = components(rhs)
        let count = max(l.count, r.count)
        for i in 0..<count {
            let lv = i < l.count ? l[i] : 0
            let rv = i < r.count ? r[i] : 0
            if lv != rv { return lv > rv }
        }
        return false // equal
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }

    // MARK: - Alerts (must be called on main thread)

    private static func offerUpdate(to version: String, url: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available — v\(version)"
        alert.informativeText = """
            A new version of InjectionNext (v\(version)) is available on GitHub. \
            Would you like to view the release page?
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "View on GitHub")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let releaseURL = URL(string: url) {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private static func showUpToDate(current: String) {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "InjectionNext v\(current) is the latest stable release."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
