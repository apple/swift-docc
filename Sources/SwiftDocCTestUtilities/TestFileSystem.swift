/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021-2024 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import XCTest
@testable @_spi(FileManagerProtocol) import SwiftDocC

/// A Data provider and file manager that accepts pre-built documentation bundles with files on the local filesystem.
///
/// `TestFileSystem` is a file manager that keeps a directory structure in memory including the file data
/// for fast access without hitting the disk. When you create an instance pass all folders to the initializer like so:
/// ```swift
/// let bundle = Folder(name: "unit-test.docc", content: [
///   ... files ...
/// ])
///
/// let testDataProvider = try TestFileSystem(
///   folders: [bundle, Folder.emptyHTMLTemplateDirectory]
/// )
/// ```
/// This will create or copy from disk the `folders` list and you can use the data provider
/// as a `FileManagerProtocol` and `DocumentationWorkspaceDataProvider`.
///
/// ## Expectations
/// This is a simplistic file system implementation aiming to satisfy our current unit test needs.
/// Care was taken that it mimics real file system behavior but if discrepancies are found while adding new tests
/// we will have to make adjustments.
///
/// Aspects of the current implementation worth noting:
/// 1. The in-memory file system is case sensitive (much like Linux)
/// 2. No support for file links
/// 3. No support for relative paths or traversing the tree upwards (e.g. "/root/nested/../other" will not resolve)
///
/// - Note: This class is thread-safe by using a naive locking for each access to the files dictionary.
/// - Warning: Use this type for unit testing.
@_spi(FileManagerProtocol) // This needs to be SPI because it conforms to an SPI protocol
public class TestFileSystem: FileManagerProtocol, DocumentationWorkspaceDataProvider {
    public let currentDirectoryPath = "/"
    
    public var identifier: String = UUID().uuidString
    
    private var _bundles = [DocumentationBundle]()
    public func bundles(options: BundleDiscoveryOptions) throws -> [DocumentationBundle] {
        // Ignore the bundle discovery options, these test bundles are already built.
        return _bundles
    }
    
    /// Thread safe access to the file system.
    private var filesLock = NSRecursiveLock()

    /// A plain index of paths and their contents.
    var files = [String: Data]()
    
    /// Set to `true` to disable write operations for folders and files.
    /// For example use this for large conversions when the output is not of interest.
    var disableWriting = false
    
    /// A data fixture to use in the `files` index to mark folders.
    static let folderFixtureData = "Folder".data(using: .utf8)!
    
    public convenience init(folders: [Folder]) throws {
        self.init()
        
        // Default system paths
        files["/"] = Self.folderFixtureData
        files["/tmp"] = Self.folderFixtureData
 
        // Import given folders
        try updateDocumentationBundles(withFolders: folders)
    }
    
    func updateDocumentationBundles(withFolders folders: [Folder]) throws {
        _bundles.removeAll()
        
        for folder in folders {
            let files = try addFolder(folder)
            
            func asCatalog(_ file: File) -> Folder? {
                if let folder = file as? Folder, URL(fileURLWithPath: folder.name).pathExtension == "docc" {
                    return folder
                }
                return nil
            }
            
            if let catalog = asCatalog(folder) ?? folder.recursiveContent.mapFirst(where: asCatalog(_:)) {
                let files = files.filter({ $0.hasPrefix(catalog.absoluteURL.path) }).compactMap({ URL(fileURLWithPath: $0) })

                let markupFiles = files.filter({ DocumentationBundleFileTypes.isMarkupFile($0) })
                let miscFiles = files.filter({ !DocumentationBundleFileTypes.isMarkupFile($0) })
                let graphs = files.filter({ DocumentationBundleFileTypes.isSymbolGraphFile($0) })
                let customHeader = files.first(where: { DocumentationBundleFileTypes.isCustomHeader($0) })
                let customFooter = files.first(where: { DocumentationBundleFileTypes.isCustomFooter($0) })
                
                let info = try DocumentationBundle.Info(
                    from: try catalog.recursiveContent.mapFirst(where: { $0 as? InfoPlist })?.data(),
                    bundleDiscoveryOptions: nil,
                    derivedDisplayName: URL(fileURLWithPath: catalog.name).deletingPathExtension().lastPathComponent
                )
                
                let bundle = DocumentationBundle(
                    info: info,
                    symbolGraphURLs: graphs,
                    markupURLs: markupFiles,
                    miscResourceURLs: miscFiles,
                    customHeader: customHeader,
                    customFooter: customFooter
                )
                _bundles.append(bundle)
            }
        }
    }

    public func contentsOfURL(_ url: URL) throws -> Data {
        filesLock.lock()
        defer { filesLock.unlock() }

        guard let file = files[url.path] else {
            throw makeFileNotFoundError(url)
        }
        return file
    }
    
    public func contents(of url: URL) throws -> Data {
        try contentsOfURL(url)
    }
    
    func filesIn(folder: Folder, at: URL) throws -> [String: Data] {
        filesLock.lock()
        defer { filesLock.unlock() }

        var result = [String: Data]()
        for file in folder.content {
            switch file {
                case let folder as Folder:
                    result[at.appendingPathComponent(folder.name).path] = Self.folderFixtureData
                    result.merge(try filesIn(folder: folder, at: at.appendingPathComponent(folder.name)), uniquingKeysWith: +)
                case let file as File & DataRepresentable:
                    result[at.appendingPathComponent(file.name).path] = try file.data()
                    if let copy = file as? CopyOfFile {
                        result[copy.original.path] = try file.data()
                    }
                default: break
            }
        }
        return result
    }
    
    @discardableResult
    func addFolder(_ folder: Folder) throws -> [String] {
        guard !disableWriting else { return [] }
        
        filesLock.lock()
        defer { filesLock.unlock() }

        let rootURL = URL(fileURLWithPath: "/\(folder.name)")
        files[rootURL.path] = Self.folderFixtureData
        let fileList = try filesIn(folder: folder, at: rootURL)
        files.merge(fileList, uniquingKeysWith: +)
        return Array(fileList.keys)
    }
    
    public func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        filesLock.lock()
        defer { filesLock.unlock() }
        
        guard let data = files[path] else {
            isDirectory?.initialize(to: ObjCBool(false))
            return false
        }
        
        isDirectory?.initialize(to: data == Self.folderFixtureData ? ObjCBool(true) : ObjCBool(false))
        return true
    }
    
    public func fileExists(atPath path: String) -> Bool {
        filesLock.lock()
        defer { filesLock.unlock() }

        return files.keys.contains(path)
    }
    
    public func copyItem(at srcURL: URL, to dstURL: URL) throws {
        guard !disableWriting else { return }
        
        filesLock.lock()
        defer { filesLock.unlock() }
        
        try ensureParentDirectoryExists(for: dstURL)
        
        let srcPath = srcURL.path
        let dstPath = dstURL.path
        
        files[dstPath] = files[srcPath]
        for (path, data) in files where path.hasPrefix(srcPath) {
            files[path.replacingOccurrences(of: srcPath, with: dstPath)] = data
        }
    }
    
    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        guard !disableWriting else { return }
        
        filesLock.lock()
        defer { filesLock.unlock() }

        let srcPath = srcURL.path

        try copyItem(at: srcURL, to: dstURL)
        files.removeValue(forKey: srcPath)
        
        for (path, _) in files where path.hasPrefix(srcPath) {
            files.removeValue(forKey: path)
        }
    }
    
    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        guard !disableWriting else { return }
        
        filesLock.lock()
        defer { filesLock.unlock() }

        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        if parent.pathComponents.count > 1 {
            // If it's not the root folder, check if parents exist
            if createIntermediates == false {
                try ensureParentDirectoryExists(for: url)
            } else {
                // Create missing parent directories
                try createDirectory(atPath: parent.path, withIntermediateDirectories: true)
            }
        }
        
        files[path] = Self.folderFixtureData
    }
    
    public func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        guard !disableWriting else { return }
        
        filesLock.lock()
        defer { filesLock.unlock() }

        try createDirectory(atPath: url.path, withIntermediateDirectories: createIntermediates)
    }
    
    public func contentsEqual(atPath path1: String, andPath path2: String) -> Bool {
        filesLock.lock()
        defer { filesLock.unlock() }

        return files[path1] == files[path2]
    }
    
    public func removeItem(at: URL) throws {
        guard !disableWriting else { return }
        
        filesLock.lock()
        defer { filesLock.unlock() }

        files.removeValue(forKey: at.path)
        for (path, _) in files where path.hasPrefix(at.path) {
            files.removeValue(forKey: path)
        }
    }
    
    public func createFile(at url: URL, contents: Data) throws {
        filesLock.lock()
        defer { filesLock.unlock() }

        try ensureParentDirectoryExists(for: url)
        
        if !disableWriting {
            files[url.path] = contents
        }
    }
    
    public func createFile(at url: URL, contents: Data, options: NSData.WritingOptions?) throws {
        try createFile(at: url, contents: contents)
    }
    
    public func contents(atPath: String) -> Data? {
        filesLock.lock()
        defer { filesLock.unlock() }

        return files[atPath]
    }
    
    public func contentsOfDirectory(atPath path: String) throws -> [String] {
        filesLock.lock()
        defer { filesLock.unlock() }
        
        var results = Set<String>()
        let path = path.appendingTrailingSlash
        
        for subpath in files.keys where subpath.hasPrefix(path) {
            let relativePath = subpath.dropFirst(path.count).removingLeadingSlash
            guard !relativePath.isEmpty else { continue }
            // only need to split twice because we only care about the first component and about identifying multiple components
            let pathParts = relativePath.split(separator: "/", maxSplits: 2)
            if pathParts.count == 1 {
                results.insert(String(pathParts[0]))
            }
        }
        return Array(results)
    }

    public func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options mask: FileManager.DirectoryEnumerationOptions) throws -> [URL] {

        if let keys = keys {
            XCTAssertTrue(keys.isEmpty, "includingPropertiesForKeys is not implemented in contentsOfDirectory in TestFileSystem")
        }
        
        if !mask.isSubset(of: [.skipsHiddenFiles]) {
            XCTFail("The given directory enumeration option(s) \(mask.rawValue) have not been implemented in the test file system: \(mask)")
        }

        let skipHiddenFiles = mask == .skipsHiddenFiles
        let contents = try contentsOfDirectory(atPath: url.path)
        let output: [URL] = contents.filter({ skipHiddenFiles ? !$0.hasPrefix(".") : true}).map {
            url.appendingPathComponent($0)
        }

        return output
    }

    public func uniqueTemporaryDirectory() -> URL {
        URL(fileURLWithPath: "/tmp/\(ProcessInfo.processInfo.globallyUniqueString)", isDirectory: true)
    }
    
    enum Errors: DescribedError {
        case invalidPath(String)
        var errorDescription: String {
            switch self { 
                case .invalidPath(let path): return "Invalid path \(path.singleQuoted)"
            }
        }
    }
    
    /// Returns a stable string representation of the file system from a given subpath.
    ///
    /// - Parameter path: The path to the sub hierarchy to dump to a string representation.
    /// - Returns: A stable string representation that can be checked in tests.
    public func dump(subHierarchyFrom path: String = "/") -> String {
        filesLock.lock()
        defer { filesLock.unlock() }
        
        let relevantFilePaths: [String]
        if path == "/" {
            relevantFilePaths = Array(files.keys)
        } else {
            let lengthToRemove = path.distance(from: path.startIndex, to: path.lastIndex(of: "/")!) + 1
            
            relevantFilePaths = files.keys
                .filter { $0.hasPrefix(path) }
                .map { String($0.dropFirst(lengthToRemove)) }
        }
        return Folder.makeStructure(
            filePaths: relevantFilePaths,
            isEmptyDirectoryCheck: { files[$0] == Self.folderFixtureData }
        )
        .map { $0.dump() }
        .joined(separator: "\n")
    }
    
    // This is a convenience utility for testing, not FileManagerProtocol API
    public func recursiveContentsOfDirectory(atPath path: String) throws -> [String] {
        var allSubpaths = try contentsOfDirectory(atPath: path)
        
        for subpath in allSubpaths { // This is iterating over a copy
            let innerContents = try recursiveContentsOfDirectory(atPath: "\(path)/\(subpath)")
            allSubpaths.append(contentsOf: innerContents.map({ "\(subpath)/\($0)" }))
        }
        return allSubpaths
    }
    
    private func ensureParentDirectoryExists(for url: URL) throws {
        let parentURL = url.deletingLastPathComponent()
        guard directoryExists(atPath: parentURL.path) else {
            throw makeFileNotFoundError(parentURL)
        }
    }
    
    private func makeFileNotFoundError(_ url: URL) -> Error {
        return CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
    }
}

private extension File {
    /// A URL of the file node if it was located in the root of the file system.
    var absoluteURL: URL { return URL(string: "/\(name)")! }
}
