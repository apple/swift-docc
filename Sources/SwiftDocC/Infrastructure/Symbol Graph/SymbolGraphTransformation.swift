//
//  SymbolGraphTransformation.swift
//  
//
//  Created by Max Obermeier on 6/21/22.
//

import Foundation
import SymbolKit

enum SymbolGraphTransformation { }

extension SymbolGraphTransformation {
    static func transformExtensionBlockFormatToExtendedTypeFormat(_ symbolGraph: inout SymbolGraph, moduleName: String) throws {
        prependModuleNameToPathComponentsOfAllSymbols(&symbolGraph, moduleName)
        
        let extensionBlockSymbols = extractExtensionBlockSymbols(from: &symbolGraph)
        var (extensionToRelationships,
             memberOfRelationships,
             conformsToRelationships) = extractRelationshipsTouchingExtensionBlockSymbols(from: &symbolGraph, using: extensionBlockSymbols)
        
        var (extendedTypeSymbols,
             extensionBlockToExtendedTypeMapping,
             extendedTypeToExtensionBlockMapping) = synthesizeExtendedTypeSymbols(using: extensionBlockSymbols, extensionToRelationships)

        var docCommentOfExtensionBlockUsed: [String: Bool] = [:]
        docCommentOfExtensionBlockUsed.reserveCapacity(extensionBlockSymbols.count)
        
        // TODO: attach comments to conformsToRelationships once differentiating between local and inherited documentation
        // is possible and frontend can display documentation for relationships.
//        attachDocComments(to: &conformsToRelationships, using: { (target) -> [SymbolGraph.Symbol] in
//            if let extensionBlockSymbol = extensionBlockSymbols[target.source] {
//                docCommentOfExtensionBlockUsed[extensionBlockSymbol.identifier.precise] = true
//                return [extensionBlockSymbol]
//            } else {
//                return []
//            }
//        })
        
        redirect(\.target, of: &memberOfRelationships, using: extensionBlockToExtendedTypeMapping)
        
        redirect(\.source, of: &conformsToRelationships, using: extensionBlockToExtendedTypeMapping)
        
        attachDocComments(to: &extendedTypeSymbols.values, using: { (target) -> [SymbolGraph.Symbol] in
            guard let relevantExtensionBlockSymbols = extendedTypeToExtensionBlockMapping[target.identifier.precise]?.compactMap({ id in extensionBlockSymbols[id] }).filter({ symbol in symbol.docComment != nil }) else {
                return []
            }
            
            let extensionBlockSymbolsWithCommentsNotInConformsToRelationship = relevantExtensionBlockSymbols.filter({ symbol in
                !(docCommentOfExtensionBlockUsed[symbol.identifier.precise] ?? false)
            })
            
            let candidateSymbols = extensionBlockSymbolsWithCommentsNotInConformsToRelationship.isEmpty ? relevantExtensionBlockSymbols : extensionBlockSymbolsWithCommentsNotInConformsToRelationship
            
            if let winner = candidateSymbols.max(by: { a, b in (a.docComment?.lines.count ?? 0) < (b.docComment?.lines.count ?? 0) }) {
                return [winner]
            } else {
                return []
            }
        })
        
        symbolGraph.relationships.append(contentsOf: memberOfRelationships)
        symbolGraph.relationships.append(contentsOf: conformsToRelationships)
        extendedTypeSymbols.values.forEach { symbol in symbolGraph.symbols[symbol.identifier.precise] = symbol }
        
        try synthesizeExtendedModuleSymbolsAndDeclaredInRelationships(on: &symbolGraph, using: extendedTypeSymbols.values.map(\.identifier.precise))
    }

    private static func attachDocComments<T: MutableCollection, S: DocCommentMixinHost>(to targets: inout T,
                                                 using source: (T.Element) -> [S],
                                                 onConflict resolveConflict: (_ old: T.Element, _ new: S)
                                                 -> SymbolGraph.LineList? = { _, _ in nil })
    where T.Element: DocCommentMixinHost {
        for index in targets.indices {
            var target = targets[index]
            
            guard target.docComment == nil else {
                continue
            }
            
            for source in source(target) {
                if case (.some(_), .some(_)) =  (target.docComment, source.docComment) {
                    target.docComment = resolveConflict(target, source)
                } else {
                    target.docComment = target.docComment ?? source.docComment
                }
            }
            
            targets[index] = target
        }
    }
    
    private static func prependModuleNameToPathComponentsOfAllSymbols(_ symbolGraph: inout SymbolGraph, _ moduleName: String) {
        for (key, symbol) in symbolGraph.symbols {
            symbolGraph.symbols[key] = symbol.replacing(\.pathComponents, with: [moduleName] + symbol.pathComponents)
        }
    }

    private static func extractExtensionBlockSymbols(from symbolGraph: inout SymbolGraph) -> [String: SymbolGraph.Symbol] {
        var extensionBlockSymbols: [String: SymbolGraph.Symbol] = [:]
        
        symbolGraph.apply(compactMap: { symbol in
            guard symbol.kind.identifier == SymbolGraph.Symbol.KindIdentifier.extension else {
                return symbol
            }
            
            extensionBlockSymbols[symbol.identifier.precise] = symbol
            return nil
        })
        
        return extensionBlockSymbols
    }

    private static func extractRelationshipsTouchingExtensionBlockSymbols(from symbolGraph: inout SymbolGraph,
                                                           using extensionBlockSymbols: [String: SymbolGraph.Symbol])
        -> (extensionToRelationships: [SymbolGraph.Relationship],
            memberOfRelationships: [SymbolGraph.Relationship],
            conformsToRelationships: [SymbolGraph.Relationship]) {
            
        var extensionToRelationships: [SymbolGraph.Relationship] = []
        var memberOfRelationships: [SymbolGraph.Relationship] = []
        var conformsToRelationships: [SymbolGraph.Relationship] = []
        
        symbolGraph.relationships = symbolGraph.relationships.compactMap { relationship in
            switch relationship.kind {
            case .extensionTo:
                if extensionBlockSymbols[relationship.source] != nil {
                    extensionToRelationships.append(relationship)
                    return nil
                }
            case .memberOf:
                if extensionBlockSymbols[relationship.target] != nil {
                    memberOfRelationships.append(relationship)
                    return nil
                }
            case .conformsTo:
                if extensionBlockSymbols[relationship.source] != nil {
                    conformsToRelationships.append(relationship)
                    return nil
                }
            default:
                break
            }
            return relationship
        }
        
        return (extensionToRelationships, memberOfRelationships, conformsToRelationships)
    }

    private static func synthesizeExtendedTypeSymbols<RS: Sequence>(using extensionBlockSymbols: [String: SymbolGraph.Symbol],
                                                     _ extensionToRelationships: RS)
    -> (extendedTypeSymbols: [String: SymbolGraph.Symbol],
        extensionBlockToExtendedTypeMapping: [String: String],
        extendedTypeToExtensionBlockMapping: [String: [String]])
    where RS.Element == SymbolGraph.Relationship {
            
        var extendedTypeSymbols: [String: SymbolGraph.Symbol] = [:]
        var extensionBlockToExtendedTypeMapping: [String: String] = [:]
        var extendedTypeToExtensionBlockMapping: [String: [String]] = [:]
        
        extensionBlockToExtendedTypeMapping.reserveCapacity(extensionBlockSymbols.count)
        
        let createExtendedTypeSymbol = { (extensionBlockSymbol: SymbolGraph.Symbol, id: String) -> SymbolGraph.Symbol in
            var newMixins = [String: Mixin]()
            
            if var swiftExtension = extensionBlockSymbol[mixin: SymbolGraph.Symbol.Swift.Extension.self] {
                swiftExtension.constraints = []
                newMixins[SymbolGraph.Symbol.Swift.Extension.mixinKey] = swiftExtension
            }
            
            if let declarationFragments = extensionBlockSymbol[mixin: SymbolGraph.Symbol.DeclarationFragments.self]?.declarationFragments {
                var prefixWithoutWhereClause: [SymbolGraph.Symbol.DeclarationFragments.Fragment] = Array(declarationFragments[..<3])
                
            outer: for fragement in declarationFragments[3...] {
                    switch (fragement.kind, fragement.spelling) {
                    case (.typeIdentifier, _),
                         (.identifier, _),
                         (.text, "."):
                        prefixWithoutWhereClause.append(fragement)
                    default:
                        break outer
                    }
                }
                
                newMixins[SymbolGraph.Symbol.DeclarationFragments.mixinKey] = SymbolGraph.Symbol.DeclarationFragments(declarationFragments: Array(prefixWithoutWhereClause))
            }
            
            return SymbolGraph.Symbol(identifier: .init(precise: id,
                                                        interfaceLanguage: extensionBlockSymbol.identifier.interfaceLanguage),
                                      names: extensionBlockSymbol.names,
                                      pathComponents: extensionBlockSymbol.pathComponents,
                                      docComment: nil,
                                      accessLevel: extensionBlockSymbol.accessLevel,
                                      kind: .extendedType(for: extensionBlockSymbol),
                                      mixins: newMixins)
        }
        
        for extensionTo in extensionToRelationships {
            guard let extensionBlockSymbol = extensionBlockSymbols[extensionTo.source] else {
                continue
            }
            
            let extendedSymbolId = extensionTo.target.withExtensionPrefix
            
            let symbol: SymbolGraph.Symbol = extendedTypeSymbols[extendedSymbolId]?.replacing(\.accessLevel) { oldSymbol in
                max(oldSymbol.accessLevel, extensionBlockSymbol.accessLevel)
            } ?? createExtendedTypeSymbol(extensionBlockSymbol, extendedSymbolId)
            
            extendedTypeSymbols[symbol.identifier.precise] = symbol
            
            extensionBlockToExtendedTypeMapping[extensionTo.source] = symbol.identifier.precise
            extendedTypeToExtensionBlockMapping[symbol.identifier.precise]
            = (extendedTypeToExtensionBlockMapping[symbol.identifier.precise] ?? []) + [extensionBlockSymbol.identifier.precise]
        }
        
        return (extendedTypeSymbols, extensionBlockToExtendedTypeMapping, extendedTypeToExtensionBlockMapping)
    }

    private static func redirect<RC: MutableCollection>(_ anchor: WritableKeyPath<SymbolGraph.Relationship, String>,
                                  of relationships: inout RC,
                                  using keyMap: [String: String]) where RC.Element == SymbolGraph.Relationship {
        for index in relationships.indices {
            let relationship = relationships[index]
            
            guard let newId = keyMap[relationship[keyPath: anchor]] else {
                continue
            }
            
            relationships[index] = relationship.replacing(anchor, with: newId)
        }
    }

    private static func synthesizeExtendedModuleSymbolsAndDeclaredInRelationships<S: Sequence>(on symbolGraph: inout SymbolGraph, using extendedTypeSymbolIds: S) throws
    where S.Element == String {
        for extendedTypeSymbolId in extendedTypeSymbolIds {
            guard let extendedTypeSymbol = symbolGraph.symbols[extendedTypeSymbolId] else {
                continue
            }
            
            guard let extensionMixin = extendedTypeSymbol[mixin: SymbolGraph.Symbol.Swift.Extension.self] else {
                continue
            }
            
            let id = try extendedTypeSymbol.identifier.precise.modulePrefix(for: extensionMixin.extendedModule)
            
            
            let symbol = symbolGraph.symbols[id]?.replacing(\.accessLevel) { oldSymbol in
                max(oldSymbol.accessLevel, extendedTypeSymbol.accessLevel)
            } ?? SymbolGraph.Symbol(identifier: .init(precise: id, interfaceLanguage: extendedTypeSymbol.identifier.interfaceLanguage),
                                    names: .init(title: extensionMixin.extendedModule, navigator: nil, subHeading: nil, prose: nil),
                                    pathComponents: [extensionMixin.extendedModule],
                                    docComment: nil,
                                    accessLevel: extendedTypeSymbol.accessLevel,
                                    kind: .init(parsedIdentifier: .extendedModule, displayName: "Extended Module"),
                                    mixins: [:])
            
            symbolGraph.symbols[id] = symbol
            
            let relationship = SymbolGraph.Relationship(source: extendedTypeSymbol.identifier.precise, target: symbol.identifier.precise, kind: .declaredIn, targetFallback: symbol.names.title)
            
            symbolGraph.relationships.append(relationship)
        }
    }
}

// MARK: Custom Kind Identifiers

extension SymbolGraph.Symbol.KindIdentifier {
    static let extendedProtocol = Self(rawValue: "protocol.extension")
    
    static let extendedStructure = Self(rawValue: "struct.extension")
    
    static let extendedClass = Self(rawValue: "class.extension")
    
    static let extendedEnumeration = Self(rawValue: "enum.extension")
    
    init?(extending other: Self) {
        switch other {
        case .struct:
            self = .extendedStructure
        case .protocol:
            self = .extendedProtocol
        case .class:
            self = .extendedClass
        case .enum:
            self = .extendedEnumeration
        default:
            return nil
        }
    }
    
    static func extendedType(for extensionBlock: SymbolGraph.Symbol) -> Self? {
        guard let extensionMixin = extensionBlock.mixins[SymbolGraph.Symbol.Swift.Extension.mixinKey] as? SymbolGraph.Symbol.Swift.Extension else {
            return nil
        }
        
        guard let typeKind = extensionMixin.typeKind else {
            return nil
        }
        
        return Self(extending: typeKind)
    }
}

extension SymbolGraph.Symbol.Kind {
    static func extendedType(for extensionBlock: SymbolGraph.Symbol) -> Self {
        let id = SymbolGraph.Symbol.KindIdentifier.extendedType(for: extensionBlock)
        switch id {
        case .some(.extendedProtocol):
            return Self(parsedIdentifier: .extendedProtocol, displayName: "Extended Protocol")
        case .some(.extendedStructure):
            return Self(parsedIdentifier: .extendedStructure, displayName: "Extended Structure")
        case .some(.extendedClass):
            return Self(parsedIdentifier: .extendedClass, displayName: "Extended Class")
        case .some(.extendedEnumeration):
            return Self(parsedIdentifier: .extendedEnumeration, displayName: "Extended Enumeration")
        default:
            return Self(rawIdentifier: "unknown.extension", displayName: "Extended Type")
        }
    }
}

extension SymbolGraph.Symbol.KindIdentifier {
    static let extendedModule = Self(rawValue: "module.extension")
}

extension SymbolGraph.Relationship.Kind {
    static let declaredIn = Self(rawValue: "declaredIn")
}

// MARK: USR

private typealias USR = String

private extension USR {
    func modulePrefix(for moduleName: String) throws -> USR {
        if moduleName == "Swift" {
            if self.hasPrefix("s:e:s:") {
                return "s:e:s:"
            } else if self.hasPrefix("s:") {
                return "s:".withExtensionPrefix
            } else {
                throw IllegalUSRFormatException.noSwiftLanguagePrefix(self)
            }
        } else {
            if let range = self.range(of: moduleName) {
                return String(self[self.startIndex..<range.upperBound]).withExtensionPrefix
            } else {
                throw IllegalUSRFormatException.moduleNameNotIncluded(self, moduleName)
            }
        }
    }
    
    var withExtensionPrefix: USR {
        guard !self.hasPrefix("s:e:") else {
            return self
        }
        
        return "s:e:" + self
    }
    
    enum IllegalUSRFormatException: Error {
        case noSwiftLanguagePrefix(String)
        case moduleNameNotIncluded(String, String)
    }
}

// MARK: Apply to SymbolGraph

private extension SymbolGraph {
    mutating func apply<S: Sequence>(oneToManyMapping map: (SymbolGraph.Symbol) throws -> S) rethrows where S.Element == SymbolGraph.Symbol {
        for (key, symbol) in self.symbols {
            self.symbols.removeValue(forKey: key)
            for newSymbol in try map(symbol) {
                self.symbols[newSymbol.identifier.precise] = newSymbol
            }
        }
    }
    
    mutating func apply(compactMap include: (SymbolGraph.Symbol) throws -> SymbolGraph.Symbol?) rethrows {
        for (key, symbol) in self.symbols {
            self.symbols.removeValue(forKey: key)
            if let newSymbol = try include(symbol) {
                self.symbols[newSymbol.identifier.precise] = newSymbol
            }
        }
    }
}

// MARK: Replacing Convenience

private extension SymbolGraph.Symbol {
    func replacing<V>(_ keyPath: WritableKeyPath<Self, V>, with value: V) -> Self {
        var new = self
        new[keyPath: keyPath] = value
        return new
    }
    
    func replacing<V>(_ keyPath: WritableKeyPath<Self, V>, with closue: (Self) -> V) -> Self {
        var new = self
        new[keyPath: keyPath] = closue(self)
        return new
    }
}

private extension SymbolGraph.Relationship {
    func replacing<V>(_ keyPath: WritableKeyPath<Self, V>, with value: V) -> Self {
        var new = self
        new[keyPath: keyPath] = value
        return new
    }
}

// MARK: AccessControl+Comparable

extension SymbolGraph.Symbol.AccessControl: Comparable {
    
    public static var `private`: Self { Self(rawValue: "private") }
    
    public static var filePrivate: Self { Self(rawValue: "fileprivate") }
    
    public static var `internal`: Self { Self(rawValue: "internal") }
    
    public static var `public`: Self { Self(rawValue: "public") }
    
    public static var open: Self { Self(rawValue: "open") }
    
    public static func < (lhs: SymbolGraph.Symbol.AccessControl, rhs: SymbolGraph.Symbol.AccessControl) -> Bool {
        switch (lhs, rhs) {
        case (Self.private, Self.private):
            return false
        case (Self.private, Self.filePrivate):
            return true
        case (Self.private, Self.internal):
            return true
        case (Self.private, Self.public):
            return true
        case (Self.private, Self.open):
            return true
        case (Self.filePrivate, Self.private):
            return false
        case (Self.filePrivate, Self.filePrivate):
            return false
        case (Self.filePrivate, Self.internal):
            return true
        case (Self.filePrivate, Self.public):
            return true
        case (Self.filePrivate, Self.open):
            return true
        case (Self.internal, Self.private):
            return false
        case (Self.internal, Self.filePrivate):
            return false
        case (Self.internal, Self.internal):
            return false
        case (Self.internal, Self.public):
            return true
        case (Self.internal, Self.open):
            return true
        case (Self.public, Self.private):
            return false
        case (Self.public, Self.filePrivate):
            return false
        case (Self.public, Self.internal):
            return false
        case (Self.public, Self.public):
            return false
        case (Self.public, Self.open):
            return true
        case (Self.open, Self.private):
            return false
        case (Self.open, Self.filePrivate):
            return false
        case (Self.open, Self.internal):
            return false
        case (Self.open, Self.public):
            return false
        case (Self.open, Self.open):
            return false
        default:
            assertionFailure("Unknown AccessControl case was used in comparison.")
            return false
        }
    }
}

// MARK: DocCommentMixinHost

private protocol DocCommentMixinHost {
    var docComment: SymbolGraph.LineList? { get set }
}

extension SymbolGraph.Symbol: DocCommentMixinHost { }

extension SymbolGraph.Relationship: DocCommentMixinHost {
    fileprivate var docComment: SymbolGraph.LineList? {
        get {
            self[mixin: SymbolGraph.LineList.self]
        }
        set {
            self[mixin: SymbolGraph.LineList.self] = newValue
        }
    }
}

// MARK: LineList+Mixin

extension SymbolGraph.LineList: Mixin {
    public static let mixinKey: String = "docComment"
}
