/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown

/// A block content element.
///
/// Block elements introduce a break in their container's layout flow, and
/// usually represent a discrete item of their parent's content.
///
/// Historically, the name "block element" comes from rendering scrollable, vertical content.
/// A block element introduced a break in the horizontal flow, was preceded
/// with an empty new line, and took the whole width, which started a new horizontal flow.
/// These are headings, paragraphs, tables, and more.
///
/// ```
/// [ Paragraph ...    ]
/// - - - - - - - - - -
/// [ Aside Note ...   ]
/// - - - - - - - - - -
/// [ Code Listing ... ]
/// - - - - - - - - - - 
/// [ Paragraph ...    ]
/// ```
///
/// `RenderBlockContent` contains traditional elements like ``paragraph(inlineContent:)`` and
/// ``heading(level:text:anchor:)`` but also other documentation-specific elements like
/// ``step(content:caption:media:code:runtimePreview:)`` and ``endpointExample(summary:request:response:)``.
///
/// Block elements can be nested, for example, an aside note contains one or more paragraphs of text.
public enum RenderBlockContent: Equatable {
    /// A paragraph of content.
    case paragraph(Paragraph)
    /// An aside block.
    case aside(Aside)
    /// A block of sample code.
    case codeListing(CodeListing)
    /// A heading with the given level.
    case heading(Heading)
    /// A list that contains ordered items.
    case orderedList(OrderedList)
    /// A list that contains unordered items.
    case unorderedList(UnorderedList)
    
    /// A step in a multi-step tutorial.
    case step(TutorialStep)
    /// A REST endpoint example that includes a request and the expected response.
    case endpointExample(summary: [RenderBlockContent]?, request: CodeExample, response: CodeExample)
    /// An example that contains a sample code block.
    case dictionaryExample(summary: [RenderBlockContent]?, example: CodeExample)
    
    /// A list of terms.
    case termList(items: [TermListItem])
    /// A table that contains a list of row data.
    case table(header: HeaderType, rows: [TableRow], metadata: RenderContentMetadata?)

    /// A paragraph of content.
    public struct Paragraph: Equatable {
        /// The content inside the paragraph.
        public var inlineContent: [RenderInlineContent]

        /// Creates a new paragraph with the given content.
        public init(inlineContent: [RenderInlineContent]) {
            self.inlineContent = inlineContent
        }
    }

    /// An aside block.
    public struct Aside: Equatable {
        /// The style of this aside block.
        public var style: AsideStyle

        /// The content inside this aside block.
        public var content: [RenderBlockContent]

        public init(style: AsideStyle, content: [RenderBlockContent]) {
            self.style = style
            self.content = content
        }
    }

    /// A block of sample code.
    public struct CodeListing: Equatable {
        /// The language to use for syntax highlighting, if given.
        public var syntax: String?
        /// The lines of code inside the code block.
        public var code: [String]
        /// Additional metadata for this code block.
        public var metadata: RenderContentMetadata?

        /// Make a new `CodeListing` with the given data.
        public init(syntax: String?, code: [String], metadata: RenderContentMetadata?) {
            self.syntax = syntax
            self.code = code
            self.metadata = metadata
        }
    }

    /// A heading with the given level.
    public struct Heading: Equatable {
        /// The level of the heading.
        ///
        /// This correlates with heading levels in HTML, so a level of 1 is given the most
        /// prominence, and a level of 6 the least prominence.
        public var level: Int

        /// The text in the heading.
        public var text: String

        /// An optional anchor slug that can be used to link to the heading.
        public var anchor: String?

        /// Creates a new heading with the given data.
        public init(level: Int, text: String, anchor: String?) {
            self.level = level
            self.text = text
            self.anchor = anchor
        }
    }

    /// A list that contains ordered items.
    public struct OrderedList: Equatable {
        /// The items in this list.
        public var items: [ListItem]

        /// Creates a new ordered list with the given items.
        public init(items: [ListItem]) {
            self.items = items
        }
    }

    /// A list that contains unordered items.
    public struct UnorderedList: Equatable {
        /// The items in this list.
        public var items: [ListItem]

        /// Creates a new unordered list with the given items.
        public init(items: [ListItem]) {
            self.items = items
        }
    }

    /// A step in a multi-step tutorial.
    public struct TutorialStep: Equatable {
        /// The content inside this tutorial step.
        public var content: [RenderBlockContent]
        /// The caption for the step.
        public var caption: [RenderBlockContent]
        /// An optional media reference to accompany the step.
        public var media: RenderReferenceIdentifier?
        /// The source code file associated with this step.
        public var code: RenderReferenceIdentifier?
        /// A rendering of the tutorial step, if available.
        public var runtimePreview: RenderReferenceIdentifier?

        /// Creates a new tutorial step with the given items.
        public init(content: [RenderBlockContent], caption: [RenderBlockContent], media: RenderReferenceIdentifier? = nil, code: RenderReferenceIdentifier? = nil, runtimePreview: RenderReferenceIdentifier? = nil) {
            self.content = content
            self.caption = caption
            self.media = media
            self.code = code
            self.runtimePreview = runtimePreview
        }
    }
    
    /// An item in a list.
    public struct ListItem: Codable, Equatable {
        /// The item content.
        public var content: [RenderBlockContent]
        
        /// Creates a new list item with the given content.
        public init(content: [RenderBlockContent]) {
            self.content = content
        }
    }
    
    /// A type the describes an aside style.
    public struct AsideStyle: Codable, Equatable {
        private static let specialDisplayNames: [String: String] = [
            "nonmutatingvariant": "Non-Mutating Variant",
            "mutatingvariant": "Mutating Variant",
            "todo": "To Do",
        ]
        
        /// Returns a Boolean value indicating whether two aside styles are equal.
        ///
        /// The comparison uses ``rawValue`` and is case-insensitive.
        ///
        /// - Parameters:
        ///   - lhs: An aside style to compare.
        ///   - rhs: Another aside style to compare.
        public static func ==(lhs: AsideStyle, rhs: AsideStyle) -> Bool {
            lhs.rawValue.caseInsensitiveCompare(rhs.rawValue) == .orderedSame
        }
        
        /// The underlying raw string value.
        public var rawValue: String

        /// The heading text to use when rendering this style of aside.
        public var displayName: String {
            if let value = Self.specialDisplayNames[rawValue.lowercased()] {
                return value
            } else if rawValue.contains(where: \.isUppercase) {
                // If any character is upper-cased, assume the content has
                // specific casing and return the raw value.
                return rawValue
            } else {
                return rawValue.capitalized
            }
        }

        /// The style of aside to use when rendering.
        ///
        /// DocC Render currently has five styles of asides: Note, Tip, Experiment, Important, and Warning. Asides
        /// of these styles can emit their own style into the output, but other styles need to be rendered as one of
        /// these five styles. This property maps aside styles to the render style used in the output.
        var renderKind: String {
            switch rawValue.lowercased() {
            case let lowercasedRawValue
                where [
                    "important",
                    "warning",
                    "experiment",
                    "tip"
                ].contains(lowercasedRawValue):
                return lowercasedRawValue
            default:
                return "note"
            }
        }

        /// Creates an aside type for the specified aside kind.
        /// - Parameter asideKind: The aside kind that provides the display name.
        public init(asideKind: Markdown.Aside.Kind) {
            self.rawValue = asideKind.rawValue
        }
        
        /// Creates an aside style for the specified raw value.
        /// - Parameter rawValue: The heading text to use when rendering this style of aside.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
        
        /// Creates an aside style with the specified display name.
        /// - Parameter displayName: The heading text to use when rendering this style of aside.
        public init(displayName: String) {
            self.rawValue = Self.specialDisplayNames.first(where: { $0.value == displayName })?.key ?? displayName
        }
        
        /// Encodes the aside style into the specified encoder.
        /// - Parameter encoder: The encoder to write data to.
        public func encode(to encoder: Encoder) throws {
            // For backwards compatibility, encode only the display name and
            // not a key-value pair.
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
        
        /// Creates an aside style by decoding the specified decoder.
        /// - Parameter decoder: The decoder to read data from.
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.rawValue = try container.decode(String.self)
        }
    }
    
    /// The table headers style.
    public enum HeaderType: String, Codable, Equatable {
        /// The first row in the table contains column headers.
        case row
        /// The first column in the table contains row headers.
        case column
        /// Both the first row and column contain headers.
        case both
        /// The table doesn't contain headers.
        case none
    }
    
    /// A table row that contains a list of row cells.
    public struct TableRow: Codable, Equatable {
        /// A list of rendering block elements.
        public typealias Cell = [RenderBlockContent]
        /// The list of row cells.
        public let cells: [Cell]
        
        /// Creates a new table row.
        /// - Parameter cells: The list of row cells to use.
        public init(cells: [Cell]) {
            self.cells = cells
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(cells)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            cells = try container.decode([Cell].self)
        }
    }
    
    /// A term definition.
    ///
    /// Includes a named term and its definition, that look like:
    ///  - term: "Generic Types"
    ///  - definition: "Custom classes, structures, and enumerations that can
    ///    work with any type, in a similar way to `Array` and `Dictionary`."
    ///
    /// The term contains a list of inline elements to allow formatting while,
    /// the definition can be any free-form content including images, paragraphs, tables, etc.
    public struct TermListItem: Codable, Equatable {
        /// A term rendered as content.
        public struct Term: Codable, Equatable {
            /// The term content.
            public let inlineContent: [RenderInlineContent]
        }
        /// A definition rendered as a list of block-content elements.
        public struct Definition: Codable, Equatable {
            /// The definition content.
            public let content: [RenderBlockContent]
        }
        
        /// The term in the term-list item.
        public let term: Term
        /// The definition in the term-list item.
        public let definition: Definition
    }
}

// Codable conformance
extension RenderBlockContent: Codable {
    private enum CodingKeys: CodingKey {
        case type
        case inlineContent, content, caption, style, name, syntax, code, level, text, items, media, runtimePreview, anchor, summary, example, metadata
        case request, response
        case header, rows
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(BlockType.self, forKey: .type)
        
        switch type {
        case .paragraph:
            self = try .paragraph(.init(inlineContent: container.decode([RenderInlineContent].self, forKey: .inlineContent)))
        case .aside:
            var style = try container.decode(AsideStyle.self, forKey: .style)
            if style.renderKind == "note", let displayName = try container.decodeIfPresent(String.self, forKey: .name) {
                style = AsideStyle(displayName: displayName)
            }
            self = try .aside(.init(style: style, content: container.decode([RenderBlockContent].self, forKey: .content)))
        case .codeListing:
            self = try .codeListing(.init(
                syntax: container.decodeIfPresent(String.self, forKey: .syntax),
                code: container.decode([String].self, forKey: .code),
                metadata: container.decodeIfPresent(RenderContentMetadata.self, forKey: .metadata)
            ))
        case .heading:
            self = try .heading(.init(level: container.decode(Int.self, forKey: .level), text: container.decode(String.self, forKey: .text), anchor: container.decodeIfPresent(String.self, forKey: .anchor)))
        case .orderedList:
            self = try .orderedList(.init(items: container.decode([ListItem].self, forKey: .items)))
        case .unorderedList:
            self = try .unorderedList(.init(items: container.decode([ListItem].self, forKey: .items)))
        case .step:
            self = try .step(.init(content: container.decode([RenderBlockContent].self, forKey: .content), caption: container.decodeIfPresent([RenderBlockContent].self, forKey: .caption) ?? [], media: container.decode(RenderReferenceIdentifier?.self, forKey: .media), code: container.decode(RenderReferenceIdentifier?.self, forKey: .code), runtimePreview: container.decode(RenderReferenceIdentifier?.self, forKey: .runtimePreview)))
        case .endpointExample:
            self = try .endpointExample(
                summary: container.decodeIfPresent([RenderBlockContent].self, forKey: .summary),
                request: container.decode(CodeExample.self, forKey: .request),
                response: container.decode(CodeExample.self, forKey: .response)
            )
        case .dictionaryExample:
            self = try .dictionaryExample(summary: container.decodeIfPresent([RenderBlockContent].self, forKey: .summary), example: container.decode(CodeExample.self, forKey: .example))
        case .table:
            self = try .table(
                header: container.decode(HeaderType.self, forKey: .header),
                rows: container.decode([TableRow].self, forKey: .rows),
                metadata: container.decodeIfPresent(RenderContentMetadata.self, forKey: .metadata)
            )
        case .termList:
            self = try .termList(items: container.decode([TermListItem].self, forKey: .items))
        }
    }
    
    private enum BlockType: String, Codable {
        case paragraph, aside, codeListing, heading, orderedList, unorderedList, step, endpointExample, dictionaryExample, table, termList
    }
    
    private var type: BlockType {
        switch self {
        case .paragraph: return .paragraph
        case .aside: return .aside
        case .codeListing: return .codeListing
        case .heading: return .heading
        case .orderedList: return .orderedList
        case .unorderedList: return .unorderedList
        case .step: return .step
        case .endpointExample: return .endpointExample
        case .dictionaryExample: return .dictionaryExample
        case .table: return .table
        case .termList: return .termList
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        
        switch self {
        case .paragraph(let p):
            try container.encode(p.inlineContent, forKey: .inlineContent)
        case .aside(let a):
            try container.encode(a.style.renderKind, forKey: .style)
            try container.encode(a.style.displayName, forKey: .name)
            try container.encode(a.content, forKey: .content)
        case .codeListing(let l):
            try container.encode(l.syntax, forKey: .syntax)
            try container.encode(l.code, forKey: .code)
            try container.encodeIfPresent(l.metadata, forKey: .metadata)
        case .heading(let h):
            try container.encode(h.level, forKey: .level)
            try container.encode(h.text, forKey: .text)
            try container.encode(h.anchor, forKey: .anchor)
        case .orderedList(let l):
            try container.encode(l.items, forKey: .items)
        case .unorderedList(let l):
            try container.encode(l.items, forKey: .items)
        case .step(let s):
            try container.encode(s.content, forKey: .content)
            try container.encode(s.caption, forKey: .caption)
            try container.encode(s.media, forKey: .media)
            try container.encode(s.code, forKey: .code)
            try container.encode(s.runtimePreview, forKey: .runtimePreview)
        case .endpointExample(summary: let summary, request: let request, response: let response):
            try container.encodeIfPresent(summary, forKey: .summary)
            try container.encode(request, forKey: .request)
            try container.encode(response, forKey: .response)
        case .dictionaryExample(summary: let summary, example: let example):
            try container.encodeIfPresent(summary, forKey: .summary)
            try container.encode(example, forKey: .example)
        case .table(header: let header, rows: let rows, metadata: let metadata):
            try container.encode(header, forKey: .header)
            try container.encode(rows, forKey: .rows)
            try container.encodeIfPresent(metadata, forKey: .metadata)
        case .termList(items: let items):
            try container.encode(items, forKey: .items)
        }
    }
}
