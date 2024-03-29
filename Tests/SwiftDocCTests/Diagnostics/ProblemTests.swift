/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/


import XCTest
import Markdown
@testable import SwiftDocC

class ProblemTests: XCTestCase {

    func testLocalizedDescriptionWithSolutions() {
        let source = URL(string: "/path/to/file.md")!
        let range = SourceLocation(line: 1, column: 8, source: source)..<SourceLocation(line: 10, column: 21, source: source)
        let identifier = "org.swift.docc.test-identifier"
        let summary = "Test diagnostic summary"
        let solutionSummary = "Test solution summary"
        let explanation = "Test diagnostic explanation."
        let expectedLocation = "/path/to/file.md:1:8"
        let expectedFixit = "/path/to/file.md:1:8-1:24: fixit: Replacement text"

        let replacementRange = SourceLocation(line: 1, column: 8, source: source)..<SourceLocation(line: 1, column: 24, source: source)
        let replacement = Replacement(range: replacementRange, replacement: "Replacement text")
        let solution = Solution(summary: solutionSummary, replacements: [replacement])
        let diagnostic = Diagnostic(source: source, severity: .error, range: range, identifier: identifier, summary: summary, explanation: explanation)
        let problem = Problem(diagnostic: diagnostic, possibleSolutions: [solution])

        XCTAssertEqual(DiagnosticConsoleWriter.formattedDescription(for: problem, options: .formatConsoleOutputForTools), """
        \(expectedLocation): error: \(summary). \(solutionSummary).
        \(explanation)
        \(expectedFixit)
        """)
    }

    func testFormattedDescription() {
        let source = URL(string: "/path/to/file.md")!
        let range = SourceLocation(line: 1, column: 8, source: source)..<SourceLocation(line: 10, column: 21, source: source)
        let identifier = "org.swift.docc.test-identifier"
        let summary = "Test diagnostic summary"
        let solutionSummary = "Test solution summary"
        let explanation = "Test diagnostic explanation."
        let expectedLocation = "/path/to/file.md:1:8"

        let replacementRange = SourceLocation(line: 1, column: 8, source: source)..<SourceLocation(line: 1, column: 24, source: source)
        let replacement = Replacement(range: replacementRange, replacement: "Replacement text")
        let solution = Solution(summary: solutionSummary, replacements: [replacement])
        let diagnostic = Diagnostic(source: source, severity: .error, range: range, identifier: identifier, summary: summary, explanation: explanation)
        let problem = Problem(diagnostic: diagnostic, possibleSolutions: [solution])

        XCTAssertEqual(DiagnosticConsoleWriter.formattedDescription(for: problem, options: [.formatConsoleOutputForTools]), """
        \(expectedLocation): error: \(summary). \(solutionSummary).
        \(explanation)
        \(source):1:8-1:24: fixit: Replacement text
        """)
    }
}
