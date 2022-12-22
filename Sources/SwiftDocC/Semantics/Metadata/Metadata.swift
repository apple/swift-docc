/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Markdown

/// A directive that contains various metadata about a page.
///
/// This directive acts as a container for metadata and configuration without any arguments of its own.
///
/// ## Topics
/// 
/// ### Child Directives
///
/// - ``DocumentationExtension``
/// - ``TechnologyRoot``
/// - ``DisplayName``
/// - ``PageImage``
/// - ``CallToAction``
/// - ``MetadataAvailability``
public final class Metadata: Semantic, AutomaticDirectiveConvertible {
    public let originalMarkup: BlockDirective
    
    /// Configuration that describes how this documentation extension file merges or overrides the in-source documentation.
    @ChildDirective
    var documentationOptions: DocumentationExtension? = nil
    
    /// Configuration to make this page root-level documentation.
    @ChildDirective
    var technologyRoot: TechnologyRoot? = nil
    
    /// Configuration to customize this page's symbol's display name.
    @ChildDirective
    var displayName: DisplayName? = nil
    
    /// The optional, custom image used to represent this page.
    @ChildDirective(requirements: .zeroOrMore)
    var pageImages: [PageImage]
    
    @ChildDirective(requirements: .zeroOrMore)
    var customMetadata: [CustomMetadata]

    @ChildDirective
    var callToAction: CallToAction? = nil

    @ChildDirective(requirements: .zeroOrMore)
    var availability: [MetadataAvailability]
    
    static var keyPaths: [String : AnyKeyPath] = [
        "documentationOptions"  : \Metadata._documentationOptions,
        "technologyRoot"        : \Metadata._technologyRoot,
        "displayName"           : \Metadata._displayName,
        "pageImages"            : \Metadata._pageImages,
        "customMetadata"        : \Metadata._customMetadata,
        "callToAction"          : \Metadata._callToAction,
        "availability"          : \Metadata._availability,
    ]
    
    /// Creates a metadata object with a given markup, documentation extension, and technology root.
    /// - Parameters:
    ///   - originalMarkup: The original markup for this metadata directive.
    ///   - documentationExtension: Optional configuration that describes how this documentation extension file merges or overrides the in-source documentation.
    ///   - technologyRoot: Optional configuration to make this page root-level documentation.
    ///   - displayName:Optional configuration to customize this page's symbol's display name.
    init(originalMarkup: BlockDirective, documentationExtension: DocumentationExtension?, technologyRoot: TechnologyRoot?, displayName: DisplayName?) {
        self.originalMarkup = originalMarkup
        self.documentationOptions = documentationExtension
        self.technologyRoot = technologyRoot
        self.displayName = displayName
    }
    
    @available(*, deprecated, message: "Do not call directly. Required for 'AutomaticDirectiveConvertible'.")
    init(originalMarkup: BlockDirective) {
        self.originalMarkup = originalMarkup
    }
    
    func validate(source: URL?, for bundle: DocumentationBundle, in context: DocumentationContext, problems: inout [Problem]) -> Bool {
        // Check that something is configured in the metadata block
        if documentationOptions == nil && technologyRoot == nil && displayName == nil && pageImages.isEmpty && customMetadata.isEmpty && callToAction == nil && availability.isEmpty {
            let diagnostic = Diagnostic(
                source: source,
                severity: .information,
                range: originalMarkup.range,
                identifier: "org.swift.docc.\(Metadata.directiveName).NoConfiguration",
                summary: "\(Metadata.directiveName.singleQuoted) doesn't configure anything and has no effect"
            )
            
            let solutions = originalMarkup.range.map {
                [Solution(summary: "Remove this \(Metadata.directiveName.singleQuoted) directive.", replacements: [Replacement(range: $0, replacement: "")])]
            } ?? []
            problems.append(Problem(diagnostic: diagnostic, possibleSolutions: solutions))
        }
        
        // Check that there is only a single `@PageImage` directive for each supported purpose
        var categorizedPageImages = [PageImage.Purpose : [PageImage]]()
        for pageImage in pageImages {
            categorizedPageImages[pageImage.purpose, default: []].append(pageImage)
        }
        
        for pageImages in categorizedPageImages.values {
            guard pageImages.count > 1 else {
                continue
            }
            
            for extraPageImage in pageImages {
                let diagnostic = Diagnostic(
                    source: extraPageImage.originalMarkup.nameLocation?.source,
                    severity: .warning,
                    range: extraPageImage.originalMarkup.range,
                    identifier: "org.swift.docc.DuplicatePageImage",
                    summary: "Duplicate \(PageImage.directiveName.singleQuoted) directive with \(extraPageImage.purpose.rawValue.singleQuoted) purpose",
                    explanation: """
                    A documentation page can only contain a single \(PageImage.directiveName.singleQuoted) \
                    directive for each purpose.
                    """
                )
                
                guard let range = extraPageImage.originalMarkup.range else {
                    problems.append(Problem(diagnostic: diagnostic))
                    continue
                }
                
                let solution = Solution(
                    summary: "Remove extraneous \(extraPageImage.purpose.rawValue.singleQuoted) \(PageImage.directiveName.singleQuoted) directive",
                    replacements: [
                        Replacement(range: range, replacement: "")
                    ]
                )
                
                problems.append(Problem(diagnostic: diagnostic, possibleSolutions: [solution]))
            }
        }

        var categorizedAvailability = [MetadataAvailability.Platform : [MetadataAvailability]]()
        for availability in availability {
            categorizedAvailability[availability.platform, default: []].append(availability)
        }

        for availabilityAttrs in categorizedAvailability.values {
            guard availabilityAttrs.count > 1 else {
                continue
            }

            let duplicateIntroduced = availabilityAttrs.filter({ $0.introduced != nil })
            if duplicateIntroduced.count > 1 {
                for avail in duplicateIntroduced {
                    let diagnostic = Diagnostic(
                        source: avail.originalMarkup.nameLocation?.source,
                        severity: .warning,
                        range: avail.originalMarkup.range,
                        identifier: "org.swift.docc.\(MetadataAvailability.self).DuplicateIntroduced",
                        summary: "Duplicate \(MetadataAvailability.directiveName.singleQuoted) directive with 'introduced' argument",
                        explanation: """
                        A documentation page can only contain a single 'introduced' version for each platform.
                        """
                    )

                    guard let range = avail.originalMarkup.range else {
                        problems.append(Problem(diagnostic: diagnostic))
                        continue
                    }

                    let solution = Solution(
                        summary: "Remove extraneous \(MetadataAvailability.directiveName.singleQuoted) directive",
                        replacements: [
                            Replacement(range: range, replacement: "")
                        ]
                    )

                    problems.append(Problem(diagnostic: diagnostic, possibleSolutions: [solution]))
                }
            }
        }
        
        return true
    }
}

