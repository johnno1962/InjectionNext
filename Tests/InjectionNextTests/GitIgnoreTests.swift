//
//  GitIgnoreTests.swift
//  InjectionNextTests
//
//  Tests for GitIgnoreParser functionality
//

import XCTest
@testable import InjectionNext

class GitIgnoreTests: XCTestCase {
    
    func testBasicPatterns() {
        let gitignoreContent = """
        *.log
        build/
        node_modules
        temp/*.tmp
        """
        
        let parser = GitIgnoreParser(content: gitignoreContent)
        
        // Test file patterns
        XCTAssertTrue(parser.shouldIgnore(path: "error.log"))
        XCTAssertTrue(parser.shouldIgnore(path: "logs/debug.log"))
        XCTAssertFalse(parser.shouldIgnore(path: "readme.txt"))
        
        // Test directory patterns
        XCTAssertTrue(parser.shouldIgnore(path: "build/", isDirectory: true))
        XCTAssertTrue(parser.shouldIgnore(path: "build/output.bin"))
        XCTAssertTrue(parser.shouldIgnore(path: "node_modules"))
        
        // Test wildcard patterns
        XCTAssertTrue(parser.shouldIgnore(path: "temp/cache.tmp"))
        XCTAssertFalse(parser.shouldIgnore(path: "temp/data.json"))
    }
    
    func testNegationPatterns() {
        let gitignoreContent = """
        *.log
        !important.log
        build/
        !build/keep.txt
        """
        
        let parser = GitIgnoreParser(content: gitignoreContent)
        
        // Test negation
        XCTAssertTrue(parser.shouldIgnore(path: "debug.log"))
        XCTAssertFalse(parser.shouldIgnore(path: "important.log"))
        XCTAssertTrue(parser.shouldIgnore(path: "build/temp.bin"))
        XCTAssertFalse(parser.shouldIgnore(path: "build/keep.txt"))
    }
    
    func testCommentAndEmptyLines() {
        let gitignoreContent = """
        # This is a comment
        *.log
        
        # Another comment
        build/
        """
        
        let parser = GitIgnoreParser(content: gitignoreContent)
        
        XCTAssertTrue(parser.shouldIgnore(path: "error.log"))
        XCTAssertTrue(parser.shouldIgnore(path: "build/", isDirectory: true))
    }
    
    func testSourceFileFiltering() {
        let gitignoreContent = """
        *.o
        *.a
        build/
        .git/
        """
        
        let parser = GitIgnoreParser(content: gitignoreContent)
        
        // These should be ignored
        XCTAssertTrue(parser.shouldIgnore(path: "main.o"))
        XCTAssertTrue(parser.shouldIgnore(path: "libtest.a"))
        XCTAssertTrue(parser.shouldIgnore(path: "build/Debug/"))
        XCTAssertTrue(parser.shouldIgnore(path: ".git/config"))
        
        // These should not be ignored
        XCTAssertFalse(parser.shouldIgnore(path: "main.swift"))
        XCTAssertFalse(parser.shouldIgnore(path: "ViewController.m"))
        XCTAssertFalse(parser.shouldIgnore(path: "Header.h"))
    }
}