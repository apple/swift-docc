/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest
import SymbolKit
@testable import SwiftDocC

class ExtendedTypesFormatTransformationTests: XCTestCase {
    func testExtendedTypesFormatStructure() throws {
        let contents = twoExtensionBlockSymbolsExtendingSameType(extendedModule: "A", extendedType: "A", withExtensionMembers: true)
                        + twoExtensionBlockSymbolsExtendingSameType(extendedModule: "A", extendedType: "ATwo", withExtensionMembers: true)
                        + twoExtensionBlockSymbolsExtendingSameType(extendedModule: "B", extendedType: "B", withExtensionMembers: true)
        
        var graph = makeSymbolGraph(moduleName: "Module",
                                    symbols: contents.symbols,
                                    relationships: contents.relationships)
        
        XCTAssert(try ExtendedTypesFormatTransformation.transformExtensionBlockFormatToExtendedTypeFormat(&graph))
        
        let extendedModuleA = try XCTUnwrap(graph.symbols.values.first(where: { symbol in symbol.kind.identifier == .extendedModule && symbol.title == "A" }))
        let extendedModuleB = try XCTUnwrap(graph.symbols.values.first(where: { symbol in symbol.kind.identifier == .extendedModule && symbol.title == "B" }))
        
        let extendedTypeA = try XCTUnwrap(graph.symbols.values.first(where: { symbol in symbol.kind.identifier == .extendedStructure && symbol.title == "A" }))
        let extendedTypeATwo = try XCTUnwrap(graph.symbols.values.first(where: { symbol in symbol.kind.identifier == .extendedStructure && symbol.title == "ATwo" }))
        let extendedTypeB = try XCTUnwrap(graph.symbols.values.first(where: { symbol in symbol.kind.identifier == .extendedStructure && symbol.title == "B" }))
        
        let addedMemberSymbolsTypeA = graph.symbols.values.filter({ symbol in symbol.kind.identifier == .property && symbol.pathComponents[symbol.pathComponents.count-2] == "A" })
        XCTAssertEqual(addedMemberSymbolsTypeA.count, 2)
        let addedMemberSymbolsTypeATwo = graph.symbols.values.filter({ symbol in symbol.kind.identifier == .property && symbol.pathComponents[symbol.pathComponents.count-2] == "ATwo" })
        XCTAssertEqual(addedMemberSymbolsTypeATwo.count, 2)
        let addedMemberSymbolsTypeB = graph.symbols.values.filter({ symbol in symbol.kind.identifier == .property && symbol.pathComponents[symbol.pathComponents.count-2] == "B" })
        XCTAssertEqual(addedMemberSymbolsTypeB.count, 2)
        
        [
            SymbolGraph.Relationship(source: addedMemberSymbolsTypeA[0].identifier.precise, target: extendedTypeA.identifier.precise, kind: .memberOf, targetFallback: nil),
            SymbolGraph.Relationship(source: addedMemberSymbolsTypeA[1].identifier.precise, target: extendedTypeA.identifier.precise, kind: .memberOf, targetFallback: nil),
            SymbolGraph.Relationship(source: addedMemberSymbolsTypeATwo[0].identifier.precise, target: extendedTypeATwo.identifier.precise, kind: .memberOf, targetFallback: nil),
            SymbolGraph.Relationship(source: addedMemberSymbolsTypeATwo[1].identifier.precise, target: extendedTypeATwo.identifier.precise, kind: .memberOf, targetFallback: nil),
            SymbolGraph.Relationship(source: addedMemberSymbolsTypeB[0].identifier.precise, target: extendedTypeB.identifier.precise, kind: .memberOf, targetFallback: nil),
            SymbolGraph.Relationship(source: addedMemberSymbolsTypeB[1].identifier.precise, target: extendedTypeB.identifier.precise, kind: .memberOf, targetFallback: nil),
            
            SymbolGraph.Relationship(source: extendedTypeA.identifier.precise, target: extendedModuleA.identifier.precise, kind: .declaredIn, targetFallback: nil),
            SymbolGraph.Relationship(source: extendedTypeATwo.identifier.precise, target: extendedModuleA.identifier.precise, kind: .declaredIn, targetFallback: nil),
            SymbolGraph.Relationship(source: extendedTypeB.identifier.precise, target: extendedModuleB.identifier.precise, kind: .declaredIn, targetFallback: nil),
        ].forEach { test in
            XCTAssert(graph.relationships.contains(where: { sample in
                sample.source == test.source && sample.target == test.target && sample.kind == test.kind
            }))
        }
        
        
        XCTAssertEqual(graph.symbols.count, 2 /* extended modules */ + 3 /* extended types */ + 6 /* added properties */)
        XCTAssertEqual(graph.relationships.count, 3 /* .declaredIn */ + 6 /* .memberOf */)
    }
    
    func testDocumentationForExtendedTypeSymbolUsesLongestAvailableDocumenation() throws {
        for permutation in allPermutations(of: twoExtensionBlockSymbolsExtendingSameType(sameDocCommentLength: false).symbols, and: twoExtensionBlockSymbolsExtendingSameType(sameDocCommentLength: false).relationships) {
            var graph = makeSymbolGraph(moduleName: "Module", symbols: permutation.symbols, relationships: permutation.relationships)
            _ = try ExtendedTypesFormatTransformation.transformExtensionBlockFormatToExtendedTypeFormat(&graph)
            
            let extendedTypeSymbol = try XCTUnwrap(graph.symbols.values.first(where: { symbol in symbol.kind.identifier == .extendedStructure }))
            XCTAssertEqual(extendedTypeSymbol.docComment?.lines.count, 2)
        }
    }
    
    func testBaseSymbolForExtendedTypeSymbolIsStable() throws {
        for permutation in allPermutations(of: twoExtensionBlockSymbolsExtendingSameType().symbols, and: twoExtensionBlockSymbolsExtendingSameType().relationships) {
            var graph = makeSymbolGraph(moduleName: "Module", symbols: permutation.symbols, relationships: permutation.relationships)
            _ = try ExtendedTypesFormatTransformation.transformExtensionBlockFormatToExtendedTypeFormat(&graph)
            
            let extendedTypeSymbol = try XCTUnwrap(graph.symbols.values.first(where: { symbol in symbol.kind.identifier == .extendedStructure }))
            XCTAssertEqual(extendedTypeSymbol.identifier.precise, "s:e:s:AAlong") // long < short (alphabetically)
        }
    }
    
    func testBaseSymbolForExtendedModuleSymbolIsStable() throws {
        for permutation in allPermutations(of: twoExtensionBlockSymbolsExtendingSameType().symbols, and: twoExtensionBlockSymbolsExtendingSameType().relationships) {
            var graph = makeSymbolGraph(moduleName: "Module", symbols: permutation.symbols, relationships: permutation.relationships)
            _ = try ExtendedTypesFormatTransformation.transformExtensionBlockFormatToExtendedTypeFormat(&graph)
            
            let extendedModuleSymbol = try XCTUnwrap(graph.symbols.values.first(where: { symbol in symbol.kind.identifier == .extendedModule }))
            XCTAssertEqual(extendedModuleSymbol.identifier.precise, "s:m:s:e:s:AAlong") // long < short (alphabetically)
        }
    }
    
    func testDocumentationForExtendedTypeSymbolIsStable() throws {
        for permutation in allPermutations(of: twoExtensionBlockSymbolsExtendingSameType(sameDocCommentLength: true).symbols, and: twoExtensionBlockSymbolsExtendingSameType(sameDocCommentLength: true).relationships) {
            var graph = makeSymbolGraph(moduleName: "Module", symbols: permutation.symbols, relationships: permutation.relationships)
            _ = try ExtendedTypesFormatTransformation.transformExtensionBlockFormatToExtendedTypeFormat(&graph)
            
            let extendedTypeSymbol = try XCTUnwrap(graph.symbols.values.first(where: { symbol in symbol.kind.identifier == .extendedStructure }))
            XCTAssertEqual(extendedTypeSymbol.docComment?.lines.first?.text, "two") // long < short (alphabetically)
        }
    }
    
    func testCrossModuleNestedTypeExtensionsHandling() throws {
        let aAtB = (graph: makeSymbolGraph(moduleName: "A", symbols: [
            .init(identifier: .init(precise: "s:m:s:e:s:Bone", interfaceLanguage: "swift"),
                  names: .init(title: "B", navigator: nil, subHeading: nil, prose: nil),
                  pathComponents: ["B"],
                  docComment: nil,
                  accessLevel: .public,
                  kind: .init(parsedIdentifier: .extendedModule, displayName: "Extended Module"),
                  mixins: [:])
        ]), url: URL(fileURLWithPath: "A@B.symbols.json"))
        
        let aAtC = (graph: makeSymbolGraph(moduleName: "A", symbols: [
            .init(identifier: .init(precise: "s:m:s:e:s:Btwo", interfaceLanguage: "swift"),
                  names: .init(title: "B", navigator: nil, subHeading: nil, prose: nil),
                  pathComponents: ["B"],
                  docComment: nil,
                  accessLevel: .public,
                  kind: .init(parsedIdentifier: .extendedModule, displayName: "Extended Module"),
                  mixins: [:]),
            .init(identifier: .init(precise: "s:m:s:e:s:C", interfaceLanguage: "swift"),
                  names: .init(title: "C", navigator: nil, subHeading: nil, prose: nil),
                  pathComponents: ["C"],
                  docComment: nil,
                  accessLevel: .public,
                  kind: .init(parsedIdentifier: .extendedModule, displayName: "Extended Module"),
                  mixins: [:])
        ]), url: URL(fileURLWithPath: "A@C.symbols.json"))
        
        for files in allPermutations(of: [aAtB, aAtC]) {
            let unifiedGraph = try XCTUnwrap(UnifiedSymbolGraph(fromSingleGraph: makeSymbolGraph(moduleName: "A"), at: .init(fileURLWithPath: "A.symbols.json")))
            for file in files {
                unifiedGraph.mergeGraph(graph: file.graph, at: file.url)
            }
            
            ExtendedTypesFormatTransformation.mergeExtendedModuleSymbolsFromDifferentFiles(unifiedGraph)
            
            let extendedModuleSymbols = unifiedGraph.symbols.values.filter({ symbol in symbol.kindIdentifier == "swift." + SymbolGraph.Symbol.KindIdentifier.extendedModule.identifier })
            XCTAssertEqual(extendedModuleSymbols.count, 2)
            
            let extendedModuleSymbolForB = try XCTUnwrap(extendedModuleSymbols.first(where: { symbol in symbol.title == "B" }))
            XCTAssertEqual(extendedModuleSymbolForB.uniqueIdentifier, "s:m:s:e:s:Bone") // one < two (alphabetically)
        }
    }
    
    // MARK: Helpers
    
    private struct SymbolGraphContents {
        let symbols: [SymbolGraph.Symbol]
        let relationships: [SymbolGraph.Relationship]
    
        static func +(lhs: Self, rhs: Self) -> Self {
            SymbolGraphContents(symbols: lhs.symbols + rhs.symbols, relationships: lhs.relationships + rhs.relationships)
        }
    }
    
    private func twoExtensionBlockSymbolsExtendingSameType(extendedModule: String = "A", extendedType: String = "A", withExtensionMembers: Bool = false, sameDocCommentLength: Bool = true) -> SymbolGraphContents {
        SymbolGraphContents(symbols: [.init(identifier: .init(precise: "s:e:s:\(extendedModule)\(extendedType)long", interfaceLanguage: "swift"),
              names: .init(title: "\(extendedType)", navigator: nil, subHeading: nil, prose: nil),
              pathComponents: ["\(extendedType)"],
              docComment: .init([
                .init(text: "two", range: nil)
              ] + (sameDocCommentLength ? [] : [.init(text: "lines", range: nil)])),
              accessLevel: .public,
              kind: .init(parsedIdentifier: .extension, displayName: "Extension"),
              mixins: [
                SymbolGraph.Symbol.Swift.Extension.mixinKey: SymbolGraph.Symbol.Swift.Extension(extendedModule: "\(extendedModule)", constraints: [], typeKind: .struct)
              ]),
        .init(identifier: .init(precise: "s:e:s:\(extendedModule)\(extendedType)short", interfaceLanguage: "swift"),
              names: .init(title: "\(extendedType)", navigator: nil, subHeading: nil, prose: nil),
              pathComponents: ["\(extendedType)"],
              docComment: .init([
                .init(text: "one line", range: nil)
              ]),
              accessLevel: .public,
              kind: .init(parsedIdentifier: .extension, displayName: "Extension"),
              mixins: [
                SymbolGraph.Symbol.Swift.Extension.mixinKey: SymbolGraph.Symbol.Swift.Extension(extendedModule: "\(extendedModule)", constraints: [], typeKind: .struct)
              ])
        ] + (withExtensionMembers ? [
        .init(identifier: .init(precise: "s:\(extendedModule)\(extendedType)long", interfaceLanguage: "swift"),
              names: .init(title: "long", navigator: nil, subHeading: nil, prose: nil),
              pathComponents: ["\(extendedType)", "long"],
              docComment: nil,
              accessLevel: .public,
              kind: .init(parsedIdentifier: .property, displayName: "Property"),
              mixins: [
                SymbolGraph.Symbol.Swift.Extension.mixinKey: SymbolGraph.Symbol.Swift.Extension(extendedModule: "\(extendedModule)", constraints: [], typeKind: .struct)
              ]),
        .init(identifier: .init(precise: "s:\(extendedModule)\(extendedType)short", interfaceLanguage: "swift"),
              names: .init(title: "short", navigator: nil, subHeading: nil, prose: nil),
              pathComponents: ["\(extendedType)", "short"],
              docComment: nil,
              accessLevel: .public,
              kind: .init(parsedIdentifier: .property, displayName: "Property"),
              mixins: [
                SymbolGraph.Symbol.Swift.Extension.mixinKey: SymbolGraph.Symbol.Swift.Extension(extendedModule: "\(extendedModule)", constraints: [], typeKind: .struct)
              ])
        ] : [])
        , relationships: [
            .init(source: "s:e:s:\(extendedModule)\(extendedType)long", target: "s:\(extendedModule)\(extendedType)", kind: .extensionTo, targetFallback: "\(extendedModule).\(extendedType)"),
            .init(source: "s:e:s:\(extendedModule)\(extendedType)short", target: "s:\(extendedModule)\(extendedType)", kind: .extensionTo, targetFallback: "\(extendedModule).\(extendedType)")
        ] + (withExtensionMembers ? [
            .init(source: "s:\(extendedModule)\(extendedType)long", target: "s:e:s:\(extendedModule)\(extendedType)long", kind: .memberOf, targetFallback: "\(extendedModule).\(extendedType)"),
            .init(source: "s:\(extendedModule)\(extendedType)short", target: "s:e:s:\(extendedModule)\(extendedType)short", kind: .memberOf, targetFallback: "\(extendedModule).\(extendedType)")
        ] : []))
    }
    
    private func allPermutations(of symbols: [SymbolGraph.Symbol], and relationships: [SymbolGraph.Relationship]) -> [(symbols: [SymbolGraph.Symbol], relationships: [SymbolGraph.Relationship])] {
        let symbolPermutations = allPermutations(of: symbols)
        let relationshipPermutations = allPermutations(of: relationships)
        
        var permutations: [([SymbolGraph.Symbol], [SymbolGraph.Relationship])] = []
        
        for sp in symbolPermutations {
            for rp in relationshipPermutations {
                permutations.append((sp, rp))
            }
        }
        
        return permutations
    }
    
    private func allPermutations<C: Collection>(of a: C) -> [[C.Element]] {
        var a = Array(a)
        var p: [[C.Element]] = []
        p.reserveCapacity(Int(pow(Double(2), Double(a.count))))
        permutations(a.count, &a, calling: { p.append($0) })
        return p
    }

    // https://en.wikipedia.org/wiki/Heap's_algorithm
    private func permutations<C: MutableCollection>(_ n:Int, _ a: inout C, calling report: (C) -> Void) where C.Index == Int {
        if n == 1 {
            report(a)
            return
        }
        for i in 0..<n-1 {
            permutations(n-1, &a, calling: report)
            let temp = a[n-1]
            a[n-1] = a[(n%2 == 1) ? 0 : i]
            a[(n%2 == 1) ? 0 : i] = temp
        }
        permutations(n-1, &a, calling: report)
    }
}
