/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import SymbolKit

private let knownSymbolKinds = SymbolGraph.Symbol.KindIdentifier.allCases.map { $0.identifier }
private let knownLanguagePrefixes = SourceLanguage.knownLanguages.flatMap { [$0.id] + $0.idAliases }.map { $0 + "." }

struct ResolvedIdentifier: Equatable, Hashable {
    private let storage = UUID()
}

// !!!: This file is a draft implementation of a symbol path disambiguation tree.
// It's functionally correct (see tests) but I want to integrate it, to see how the API needs to be adjusted, before cleaning it up, documenting it, and optimizing it.

// TODO: Clean up the draft implementation (inline TODOs and more)
// TODO: Optimize performance (inline TODOs and more)
// TODO: Document (both API and some important implementation aspects)

struct SymbolPathTree {
    
    init(symbolGraphLoader loader: SymbolGraphLoader) {
        var roots: [String: Node] = [:]
        var allNodes: [String: [SymbolPathTree.Node]] = [:]
        
        let symbolGraphs = loader.symbolGraphs
            .sorted(by: { lhs, _ in
                return !lhs.key.lastPathComponent.contains("@")
            })
        
        for (_, graph) in symbolGraphs {
            let moduleName = graph.module.name
            guard loader.hasPrimaryURL(moduleName: moduleName) else { continue }
            
            let moduleNode: Node
            if let existingModuleNode = roots[moduleName] {
                moduleNode = existingModuleNode
            } else {
                let moduleSymbol = SymbolGraph.Symbol(
                    identifier: .init(precise: moduleName, interfaceLanguage: SourceLanguage.swift.id), // TODO: Customizable module language
                    names: SymbolGraph.Symbol.Names(title: moduleName, navigator: nil, subHeading: nil, prose: nil),
                    pathComponents: [moduleName],
                    docComment: nil,
                    accessLevel: SymbolGraph.Symbol.AccessControl(rawValue: "public"),
                    kind: SymbolGraph.Symbol.Kind(parsedIdentifier: .module, displayName: "Framework"), // TODO: Customizable module display name
                    mixins: [:])
                let newModuleNode = SymbolPathTree.Node(value: moduleSymbol)
                roots[moduleName] = newModuleNode
                moduleNode = newModuleNode
                allNodes[moduleName] = [moduleNode]
            }
            
            var nodes: [String: SymbolPathTree.Node] = [:]
            nodes.reserveCapacity(graph.symbols.count)
            for (id, symbol) in graph.symbols {
                let node = SymbolPathTree.Node(value: symbol)
                nodes[id] = node
                allNodes[id, default: []].append(node)
            }
            
            var topLevelCandidates = nodes
            for relationship in graph.relationships where [.memberOf, .requirementOf, .optionalRequirementOf].contains(relationship.kind) {
                guard let sourceNode = nodes[relationship.source] else {
                    continue
                }
                topLevelCandidates.removeValue(forKey: relationship.source)
                if let targetNode = nodes[relationship.target] {
                    if let collidedNodes = targetNode.add(child: sourceNode) {
                        nodes[collidedNodes.0] = nil
                        nodes[collidedNodes.1] = nil
                    }
                } else if let targetNodes = allNodes[relationship.target] {
                    for targetNode in targetNodes {
                        assert(targetNode.value.pathComponents.first != sourceNode.value.pathComponents.first)
                        _ = targetNode.add(child: sourceNode)
                    }
                } else {
                    // TODO: It's possible for a symbol to fall out of the tree if it has no relationships and has multiple path components
                    // I'm not sure what's the right thing to do here.
                    continue
                }
            }
            for relationship in graph.relationships where [.defaultImplementationOf].contains(relationship.kind) {
                guard let sourceNode = nodes[relationship.source], sourceNode.parent == nil else {
                    continue
                }
                topLevelCandidates.removeValue(forKey: relationship.source)
                guard let targetParent = nodes[relationship.target]?.parent else {
                    continue
                }
                if let collidedNodes = targetParent.add(child: sourceNode) {
                    nodes[collidedNodes.0] = nil
                    nodes[collidedNodes.1] = nil
                }
            }
            
            for topLevelNode in topLevelCandidates.values {
                _ = moduleNode.add(child: topLevelNode)
            }
        }
        
        allNodes.removeAll()
        
        // build the lookup list
        var lookup = [ResolvedIdentifier: Node]()
        func descend(_ node: Node) {
            assert(node.identifier == nil)
            node.identifier = ResolvedIdentifier()
            lookup[node.identifier] = node
            allNodes[node.value.identifier.precise, default: []].append(node)
            
            for tree in node.children.values {
                for (_, subtree) in tree.storage {
                    for (_, node) in subtree {
                        descend(node)
                    }
                }
            }
        }
        
        for module in roots.values {
            descend(module)
        }
        
        assert(lookup.allSatisfy({ $0.key == $0.value.identifier}))
        
        self.roots = roots
        self.lookup = lookup
    }
    
    let roots: [String: Node]
    let lookup: [ResolvedIdentifier: Node]
    
    func caseInsensitiveDisambiguatedPaths() -> [String: String] {
        func descend(_ node: Node, accumulatedPath: String) -> [(String, (String, Bool))] {
            var results: [(String, (String, Bool))] = [(node.value.identifier.precise, (accumulatedPath, node.value.identifier.interfaceLanguage == "swift"))]
            let caseInsensitiveChildren = [String: DisambiguationTree](node.children.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { $0.merge(with: $1) })
            
            for (_, tree) in caseInsensitiveChildren {
                let disambiguatedChildren = tree.disambiguatedValues(includeLanguage: true)
                for (node, disambiguation) in disambiguatedChildren {
                    let path = accumulatedPath + "/" + node.value.pathComponents.last! + disambiguation
                    results += descend(node, accumulatedPath: path)
                }
            }
            return results
        }
        
        var gathered: [(String, (String, Bool))] = []
        
        for (moduleName, node) in roots {
            let path = "/" + moduleName
            gathered += descend(node, accumulatedPath: path)
        }
        
        return [String: (String, Bool)](gathered, uniquingKeysWith: { lhs, rhs in lhs.1 ? lhs : rhs }).mapValues({ $0.0 })
    }
    
    final class Node {
        fileprivate var children: [String: DisambiguationTree]
        
        var parent: Node?
        var value: SymbolGraph.Symbol
        var identifier: ResolvedIdentifier!
        
        init(value: SymbolGraph.Symbol) {
            self.value = value
            self.children = [:]
        }
        
        func add(child: Node) -> (String, String)? {
            let path = child.value.pathComponents.last!
            let kind = child.value.kind.identifier.identifier
            let hash = child.value.identifier.precise.stableHashString
            
            child.parent = self
            return children[path, default: .init()].add(kind, hash, child)
        }
        
        func merge(with other: Node) -> Node {
            let new = Node(value: self.value)
            assert(self.parent?.value == other.parent?.value)
            new.identifier = self.identifier
            new.parent = self.parent
            new.children = self.children.merging(other.children, uniquingKeysWith: { $0.merge(with: $1) })
            
            for (_, tree) in new.children {
                for subtree in tree.storage.values {
                    for node in subtree.values {
                        node.parent = new
                    }
                }
            }
            
            return new
        }
    }
    
    enum Error: Swift.Error {
        case notFound(availableChildren: [String])
        case partialResult(partialResult: ResolvedIdentifier, remainingSubpath: String, availableChildren: [String])
        case lookupCollision(partialResult: ResolvedIdentifier, collisions: [(value: SymbolGraph.Symbol, disambiguation: String)])
    }
        
    func find(path: String, parent: ResolvedIdentifier? = nil) throws -> SymbolGraph.Symbol {
        return try findNode(path: path, parent: parent).value
    }
    
    func findNode(path rawPath: String, parent: ResolvedIdentifier? = nil) throws -> Node {
        var path = Self.parse(path: rawPath)
        guard !path.isEmpty else {
            throw Error.notFound(availableChildren: [])
        }
        
        let root: Node
        var remaining = path[...]
        if path.first!.0 == "/" {
            // Absolute link
            path = Array(path.dropFirst())
            guard let matchedRoot = roots[path.first!.0] else {
                throw Error.notFound(availableChildren: roots.keys.sorted())
            }
            root = matchedRoot
            remaining = path.dropFirst()
        } else if let parent = parent {
            var parentNode = lookup[parent]!
            let firstPathName = path.first!.0
            lookingForParent: while !parentNode.children.keys.contains(firstPathName) {
                guard let parent = parentNode.parent else {
                    if let moduleMatch = roots[firstPathName] {
                        parentNode = moduleMatch
                        remaining = remaining.dropFirst()
                        break lookingForParent
                    }
                    throw Error.notFound(availableChildren: parentNode.children.keys.sorted())
                }
                parentNode = parent
            }
            root = parentNode
        } else {
            // ???: Allow relative links to skip the module?
            guard let matchedRoot = roots[path.first!.0] else {
                throw Error.notFound(availableChildren: roots.keys.sorted())
            }
            root = matchedRoot
            remaining = path.dropFirst()
        }
        
        if remaining.isEmpty {
            return root
        }
        var node = root
        while true {
            guard let children = node.children[remaining.first!.0] else {
                throw Error.partialResult(
                    partialResult: node.identifier,
                    remainingSubpath: Self.joined(remaining),
                    availableChildren: node.children.keys.sorted()
                )
            }
            
            do {
                guard let child = try children.find(remaining.first!.1, remaining.first!.2) else {
                    throw Error.partialResult(
                        partialResult: node.identifier,
                        remainingSubpath: Self.joined(remaining),
                        availableChildren: node.children.keys.sorted()
                    )
                }
                node = child
                remaining = remaining.dropFirst()
                if remaining.isEmpty {
                    return child
                }
            } catch DisambiguationTree.Error.lookupCollision(let collisions) {
                guard let nextPathComponent = remaining.dropFirst().first else {
                    // Wrap the original collision
                    throw Error.lookupCollision(partialResult: node.identifier, collisions: collisions.map { ($0.node.value, $0.disambiguation) })
                }
                // Check if the collision can be disambiguated by the children
                let possibleMatches = collisions.compactMap {
                    return try? $0.node.children[nextPathComponent.0]?.find(nextPathComponent.1, nextPathComponent.2)
                }
                if possibleMatches.count == 1 {
                    return possibleMatches.first!
                } else {
                    // Wrap the original collision
                    throw Error.lookupCollision(partialResult: node.identifier, collisions: collisions.map { ($0.node.value, $0.disambiguation) })
                }
            }
        }
    }
    
    public static func joined<Components: Sequence>(_ components: Components ) -> String where Components.Element == (String, String?, String?) {
        return components.map {
            path, kind, hash in
            var result = path
            if let kind = kind {
                result += "-\(kind)"
            }
            if let hash = hash {
                result += "-\(hash)"
            }
            return result
        }.joined(separator: "/")
    }
    
    public static func parse(path: String) -> [(String, String?, String?)] {
        guard !path.isEmpty else { return [] }
        var path = path
        if path.starts(with: "/documentation/") {
            path = String(path.dropFirst("/documentation".count)) // keep the slash before the module name
        } else if path.starts(with: "documentation/") {
            path = String(path.dropFirst("documentation".count)) // keep the slash before the module name
        }
        var urlComponents = URLComponents()
        urlComponents.path = path
        guard let components = urlComponents.url?.pathComponents else { return [] }
        
        return components.map {
            guard $0.contains("-") else {
                return ($0, nil, nil)
            }
            
            var s = $0[...]
            var kind, hash: String?
            
            if let dashIndex = s.lastIndex(of: "-") {
                hash = String(s[dashIndex...].dropFirst())
                s = s[..<dashIndex]
                if knownSymbolKinds.contains(hash!) {
                    return (String(s), hash, nil)
                }
                if let languagePrefix = knownLanguagePrefixes.first(where: { hash!.starts(with: $0) }) {
                    return (String(s), String(hash!.dropFirst(languagePrefix.count)), nil)
                }
            }
            if let dashIndex = s.lastIndex(of: "-") {
                kind = String(s[dashIndex...].dropFirst())
                s = s[..<dashIndex]
                if let languagePrefix = knownLanguagePrefixes.first(where: { kind!.starts(with: $0) }) {
                    return (String(s), String(kind!.dropFirst(languagePrefix.count)), hash)
                }
            }
            
            return (String(s), kind, hash)
        }
    }
}

// MARK: Integration shim

// TODO: Remove the need for these.
extension SymbolPathTree {
    func toTopicReference(_ identifier: ResolvedIdentifier, context: DocumentationContext) -> ResolvedTopicReference {
        return context.symbolIndex[self.lookup[identifier]!.value.identifier.precise]!.reference
    }
    
    func fromTopicReference(_ reference: ResolvedTopicReference, context: DocumentationContext) -> ResolvedIdentifier? {
        guard !reference.path.isEmpty, reference.path != "/" else { return nil }
        
        do {
            return try findNode(path: reference.path).identifier
        } catch {
            if let moduleName = context.parents(of: reference).first?.pathComponents[2] {
                return roots[moduleName]?.identifier
            }
            return nil
        }
    }
    
    func traversePreOrder(_ observe: (Node) -> Void) {
        lookup.values.forEach(observe)
    }
    
    func topLevelSymbols() -> [ResolvedIdentifier] {
        var result: Set<ResolvedIdentifier> = []
        for root in roots.values {
            for (_, tree) in root.children {
                for subtree in tree.storage.values {
                    result.formUnion(subtree.values.map(\.identifier))
                }
            }
        }
        return Array(result)
    }
}

// MARK: Dump

private struct DumpableNode {
    var name: String
    var children: [DumpableNode]
}

private extension SymbolPathTree.Node {
    func dumpableNode() -> DumpableNode {
        return DumpableNode(
            name: "{ \(value.identifier.precise) : \(value.identifier.interfaceLanguage).\(value.kind.identifier.identifier) }",
            children: children.sorted(by: \.key).map { (key, disambiguationTree) -> DumpableNode in
                DumpableNode(
                    name: key,
                    children: disambiguationTree.storage.sorted(by: \.key).map { (kind, kindTree) -> DumpableNode in
                        DumpableNode(
                            name: kind,
                            children: kindTree.sorted(by: \.key).map { (usr, node) -> DumpableNode in
                                DumpableNode(
                                    name: usr,
                                    children: [node.dumpableNode()]
                                )
                            }
                        )
                    }
                )
            }
        )
    }
}

extension SymbolPathTree {
    func dump() -> String {
        let root = DumpableNode(name: ".", children: roots.sorted(by: \.key).map { $0.value.dumpableNode() })
        return Self.dump(root)
    }
    
    fileprivate static func dump(_ node: DumpableNode, decorator: String = "") -> String {
        var result = ""
        result.append("\(decorator) \(node.name)\n")
        
        let children = node.children
        for (index, child) in children.enumerated() {
            var decorator = decorator
            if decorator.hasSuffix("├") {
                decorator = decorator.dropLast() + "│"
            }
            if decorator.hasSuffix("╰") {
                decorator = decorator.dropLast() + " "
            }
            let newDecorator = decorator + " " + (index == children.count-1 ? "╰" : "├")
            result.append(dump(child, decorator: newDecorator))
        }
        return result
    }
}

fileprivate struct DisambiguationTree {
    typealias Value = SymbolPathTree.Node
    // TODO: I have some ideas for how to optimize this. The tree is known to be small and be fixed depth.
    var storage: [String: [String: Value]] = [:]
    
    @discardableResult
    mutating func add(_ kind: String, _ usr: String, _ value: Value) -> (String, String)? {
        if let existing = storage[kind]?[usr] {
            storage[kind, default: [:]][usr] = existing.merge(with: value)
            return (existing.value.identifier.precise, value.value.identifier.precise)
        } else {
            storage[kind, default: [:]][usr] = value
            return nil
        }
    }
    
    func merge(with other: DisambiguationTree) -> DisambiguationTree {
        return DisambiguationTree(storage: self.storage.merging(other.storage, uniquingKeysWith: { lhs, rhs in
            lhs.merging(rhs, uniquingKeysWith: {
                lhsValue, rhsValue in
                assert(lhsValue.value == rhsValue.value)
                return lhsValue
            })
        }))
    }
    
    enum Error: Swift.Error {
        case lookupCollision([(node: SymbolPathTree.Node, disambiguation: String)])
    }
    
    func find(_ kind: String?, _ usr: String?) throws -> Value? {
        if let kind = kind {
            guard let first = storage[kind] else { return nil }
            if let usr = usr {
                return first[usr]
            } else if first.count == 1 {
                return first.values.first
            } else {
                // Disambiguate by their USR
                throw Error.lookupCollision(first.map { ($0.value, $0.key) })
            }
        } else if storage.count == 1, let first = storage.values.first {
            if let usr = usr {
                return first[usr]
            } else if first.count == 1 {
                return first.values.first
            } else {
                // Disambiguate by their USR
                throw Error.lookupCollision(first.map { ($0.value, $0.key) })
            }
        } else if let usr = usr {
            let kinds = storage.filter { $0.value.keys.contains(usr) }
            if kinds.isEmpty {
                return nil
            } else if kinds.count == 1 {
                return kinds.first!.value[usr]
            } else {
                // Disambiguate by their kind
                throw Error.lookupCollision(kinds.map { ($0.value[usr]!, $0.key) })
            }
        }
        // Disambiguate by a mix of kinds and USRs
        throw Error.lookupCollision(self.disambiguatedValues().map { ($0.value, String($0.disambiguation.dropFirst())) })
    }
    
    func disambiguatedValues(includeLanguage: Bool = false) -> [(value: Value, disambiguation: String)] {
        if storage.count == 1 {
            let tree = storage.values.first!
            if tree.count == 1 {
                return [(tree.values.first!, "")]
            }
        }
        
        var collisions: [(value: Value, disambiguation: String)] = []
        for (kind, kindTree) in storage {
            if kindTree.count == 1 {
                // No other match has this kind
                if includeLanguage {
                    collisions.append((value: kindTree.first!.value, disambiguation: "-\(kindTree.first!.value.value.identifier.interfaceLanguage).\(kind)"))
                } else {
                    collisions.append((value: kindTree.first!.value, disambiguation: "-"+kind))
                }
                continue
            }
            for (usr, value) in kindTree {
                let kinds = storage.filter { $0.value.keys.contains(usr) }
                if kinds.count == 1 {
                    // No other match has this USR
                    collisions.append((value: value, disambiguation: "-"+usr))
                } else {
                    // This needs to be disambiguated by both kind and USR
                    if includeLanguage {
                        collisions.append((value: value, disambiguation: "-\(value.value.identifier.interfaceLanguage).\(kind)-\(usr)"))
                    } else {
                        collisions.append((value: value, disambiguation: "-\(kind)-\(usr)"))
                    }
                }
            }
        }
        return collisions
    }
}
