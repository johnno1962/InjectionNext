//
//  GitIgnoreParser.swift
//  InjectionNext
//
//  Created for gitignore functionality integration.
//

import Foundation

/// Parses .gitignore files and provides pattern matching functionality
class GitIgnoreParser {
    private var patterns: [GitIgnorePattern] = []
    
    struct GitIgnorePattern {
        let pattern: String
        let isNegation: Bool
        let isDirectory: Bool
        let regex: NSRegularExpression?
        
        init(pattern: String) {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Handle negation patterns (starting with !)
            if trimmed.hasPrefix("!") {
                self.isNegation = true
                let negatedPattern = String(trimmed.dropFirst())
                self.pattern = negatedPattern
                self.isDirectory = negatedPattern.hasSuffix("/")
            } else {
                self.isNegation = false
                self.pattern = trimmed
                self.isDirectory = trimmed.hasSuffix("/")
            }
            
            // Convert gitignore pattern to regex
            self.regex = GitIgnorePattern.createRegex(from: self.pattern)
        }
        
        private static func createRegex(from pattern: String) -> NSRegularExpression? {
            var regexPattern = pattern
            
            // Remove trailing slash for directory patterns
            if regexPattern.hasSuffix("/") {
                regexPattern = String(regexPattern.dropLast())
            }
            
            // Escape special regex characters except * and ?
            let specialChars = CharacterSet(charactersIn: ".+^${}[]|()\\")
            var escaped = ""
            for char in regexPattern {
                if char == "*" {
                    if escaped.hasSuffix("*") {
                        // Handle ** (match any number of directories)
                        escaped = String(escaped.dropLast()) + ".*"
                    } else {
                        // Handle single * (match anything except /)
                        escaped += "[^/]*"
                    }
                } else if char == "?" {
                    escaped += "[^/]"
                } else if specialChars.contains(char.unicodeScalars.first!) {
                    escaped += "\\" + String(char)
                } else {
                    escaped += String(char)
                }
            }
            
            // Anchor the pattern
            if !escaped.hasPrefix("/") && !escaped.hasPrefix(".*") {
                escaped = "(^|/)" + escaped
            } else if escaped.hasPrefix("/") {
                escaped = "^" + String(escaped.dropFirst())
            }
            
            escaped += "($|/)"
            
            return try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive])
        }
    }
    
    /// Initialize with gitignore file path
    init(gitignoreFile: String) {
        loadGitIgnore(from: gitignoreFile)
    }
    
    /// Initialize with gitignore content
    init(content: String) {
        parseContent(content)
    }
    
    private func loadGitIgnore(from filePath: String) {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return
        }
        parseContent(content)
    }
    
    private func parseContent(_ content: String) {
        patterns = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { GitIgnorePattern(pattern: $0) }
    }
    
    /// Check if a file path should be ignored according to gitignore rules
    func shouldIgnore(path: String, isDirectory: Bool = false) -> Bool {
        let relativePath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var ignored = false
        
        for pattern in patterns {
            if let regex = pattern.regex {
                let range = NSRange(location: 0, length: relativePath.count)
                if regex.firstMatch(in: relativePath, options: [], range: range) != nil {
                    if pattern.isDirectory && !isDirectory {
                        continue // Directory pattern doesn't match files
                    }
                    ignored = !pattern.isNegation
                }
            }
        }
        
        return ignored
    }
    
    /// Find and parse .gitignore files in directory hierarchy
    static func findGitIgnoreFiles(startingFrom directory: String) -> [GitIgnoreParser] {
        var parsers: [GitIgnoreParser] = []
        var currentDir = directory
        
        // Walk up the directory tree looking for .gitignore files
        while currentDir != "/" && currentDir != "" {
            let gitignorePath = (currentDir as NSString).appendingPathComponent(".gitignore")
            if FileManager.default.fileExists(atPath: gitignorePath) {
                let parser = GitIgnoreParser(gitignoreFile: gitignorePath)
                parsers.append(parser)
            }
            currentDir = (currentDir as NSString).deletingLastPathComponent
        }
        
        return parsers
    }
}