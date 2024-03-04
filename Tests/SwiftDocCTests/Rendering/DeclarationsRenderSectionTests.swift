/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest
@testable import SwiftDocC

class DeclarationsRenderSectionTests: XCTestCase {
    func testDecodingTokens() throws {
        let values: [(DeclarationRenderSection.Token.Kind, String)] = [
            (.keyword, "keyword"),
            (.attribute, "attribute"),
            (.number, "number"),
            (.string, "string"),
            (.identifier, "identifier"),
            (.typeIdentifier, "typeIdentifier"),
            (.genericParameter, "genericParameter"),
            (.text, "text"),
            (.internalParam, "internalParam"),
            (.externalParam, "externalParam"),
            (.label, "label"),
        ]

        for (token, string) in values {
            let jsonData = """
            {
                "kind": "declarations",
                "declarations": [
                    {
                        "platforms": [],
                        "tokens": [
                            {
                                "text": "",
                                "kind": "\(string)"
                            }
                        ],
                        "otherDeclarations": {
                            "declarations": [
                                {
                                    "identifier": "identifier",
                                    "tokens": [
                                        {
                                            "text": "",
                                            "kind": "\(string)"
                                        }
                                    ]
                                }
                            ],
                            "displayIndex": 0
                        }
                    }
                ]
            }
            """.data(using: .utf8)!

            XCTAssertEqual(
                try JSONDecoder().decode(DeclarationsRenderSection.self, from: jsonData),
                DeclarationsRenderSection(declarations: [
                    DeclarationRenderSection(
                        languages: nil,
                        platforms: [],
                        tokens: [.init(text: "", kind: token)],
                        otherDeclarations: DeclarationRenderSection.OtherDeclarations(
                            declarations: [.init(tokens: [.init(text: "", kind: token)], identifier: "identifier")],
                            displayIndex: 0
                        )
                    ),
                ])
            )
        }
    }
    
    func testDoNotEmitOtherDeclarationsIfEmpty() throws {

        let encoder = RenderJSONEncoder.makeEncoder(prettyPrint: true)
        let encodedData = try encoder.encode(
            DeclarationsRenderSection(declarations: [
                DeclarationRenderSection(
                    languages: nil,
                    platforms: [],
                    tokens: [.init(text: "", kind: .string)]
                )]
            )
        )
        
        let encodedJsonString = try XCTUnwrap(String(data: encodedData, encoding: .utf8))
        XCTAssertFalse(encodedJsonString.contains("otherDeclarations"))
        XCTAssertFalse(encodedJsonString.contains("indexInOtherDeclarations"))
    }

    func testRoundTrip() throws {
        let jsonData = """
        {
            "kind": "declarations",
            "declarations": [
                {
                    "platforms": [],
                    "tokens": [
                        {
                            "text": "",
                            "kind": "label"
                        }
                    ],
                    "otherDeclarations": {
                        "declarations": [
                            {
                                "identifier": "identifier",
                                "tokens": [
                                    {
                                        "text": "",
                                        "kind": "label"
                                    }
                                ]
                            }
                        ],
                        "displayIndex": 0
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let value = try JSONDecoder().decode(DeclarationsRenderSection.self, from: jsonData)
        try assertRoundTripCoding(value)
    }

    func testAlternateDeclarations() throws {
        let (bundle, context) = try testBundleAndContext(named: "AlternateDeclarations")
        let reference = ResolvedTopicReference(
            bundleIdentifier: bundle.identifier,
            path: "/documentation/AlternateDeclarations/MyClass/present(completion:)",
            sourceLanguage: .swift
        )
        let symbol = try XCTUnwrap(context.entity(with: reference).semantic as? Symbol)
        var translator = RenderNodeTranslator(
            context: context,
            bundle: bundle,
            identifier: reference,
            source: nil
        )
        let renderNode = try XCTUnwrap(translator.visitSymbol(symbol) as? RenderNode)
        let declarationsSection = try XCTUnwrap(renderNode.primaryContentSections.compactMap({ $0 as? DeclarationsRenderSection }).first)

        XCTAssertEqual(declarationsSection.declarations.count, 2)
        XCTAssert(declarationsSection.declarations.allSatisfy({ $0.platforms == [.macOS] }))
    }
}
