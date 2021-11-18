/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Foundation
@testable import SwiftDocC
@testable import SwiftDocCUtilities

class StaticHostableTransformerTests: StaticHostingBaseTests {

    /// Creates a DocC archive and then archive then executes and TransformForStaticHostingAction on it to produce static content which is then validated.
    func testStaticHostableTransformerOutput() throws {
        
        // Convert a test bundle as input for the StaticHostableTransformer
        let bundleURL = Bundle.module.url(forResource: "TestBundle", withExtension: "docc", subdirectory: "Test Bundles")!
        let targetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
        
        defer { try? fileManager.removeItem(at: targetURL) }
        
        let templateURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try Folder.emptyHTMLTemplateDirectory.write(to: templateURL)
        defer { try? fileManager.removeItem(at: templateURL) }
        
        let targetBundleURL = targetURL.appendingPathComponent("Result.doccarchive")
        defer { try? fileManager.removeItem(at: targetBundleURL) }
        
        var action = try ConvertAction(
            documentationBundleURL: bundleURL,
            outOfProcessResolver: nil,
            analyze: false,
            targetDirectory: targetBundleURL,
            htmlTemplateDirectory: templateURL,
            emitDigest: false,
            currentPlatforms: nil
        )

        _ = try action.perform(logHandle: .standardOutput)
        
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: outputURL) }

        let testTemplateURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try Folder.testHTMLTemplateDirectory.write(to: testTemplateURL)
        defer { try? fileManager.removeItem(at: testTemplateURL) }

        let basePath =  "test/folder"
        let indexHTML = Folder.testHTMLTemplate(basePath: basePath)
        
        let dataURL = targetBundleURL.appendingPathComponent("data")
        let dataProvider = try LocalFileSystemDataProvider(rootURL: dataURL)
        let transformer = try StaticHostableTransformer(dataProvider: dataProvider, fileManager: fileManager, outputURL: outputURL, htmlTemplate: testTemplateURL, staticHostingBasePath: basePath)
        
        try transformer.transform()
        
        var isDirectory: ObjCBool = false
        
        // Test an output folder exists
        guard fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) else {
            XCTFail("StaticHostableTransformer failed to create output folder")
            return
        }
        
        // Test the output folder really is a folder.
        XCTAssert(isDirectory.boolValue)
        
        // Test the content of the output folder.
        let expectedContent = ["documentation", "tutorials"]
        let output = try fileManager.contentsOfDirectory(atPath: outputURL.path)
        
        XCTAssertEqual(output, expectedContent, "Unexpected output")
        for item in output {
            
            // Test the content of the documentation and tutorial folders match the expected content from the doccarchive.
            switch item {
            case "documentation":
                compareJSONFolder(fileManager: fileManager,
                               output: outputURL.appendingPathComponent("documentation"),
                               input:  dataURL.appendingPathComponent("documentation"),
                               indexHTML: indexHTML)
            case "tutorials":
                compareJSONFolder(fileManager: fileManager,
                               output: outputURL.appendingPathComponent("tutorials"),
                               input:  dataURL.appendingPathComponent("tutorials"),
                               indexHTML: indexHTML)
            default:
                continue
            }
        }
        
    }

    /// Creates a DocC archive and then archive then executes and TransformForStaticHostingAction on it to produce static content which is then validated.
    func testStaticHostableTransformerBasePaths() throws {

        // Convert a test bundle as input for the StaticHostableTransformer
        let bundleURL = Bundle.module.url(forResource: "TestBundle", withExtension: "docc", subdirectory: "Test Bundles")!

        let targetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)

        defer { try? fileManager.removeItem(at: targetURL) }

        let templateURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try Folder.emptyHTMLTemplateDirectory.write(to: templateURL)
        defer { try? fileManager.removeItem(at: templateURL) }

        let targetBundleURL = targetURL.appendingPathComponent("Result.doccarchive")
        defer { try? fileManager.removeItem(at: targetBundleURL) }

        var action = try ConvertAction(
            documentationBundleURL: bundleURL,
            outOfProcessResolver: nil,
            analyze: false,
            targetDirectory: targetBundleURL,
            htmlTemplateDirectory: templateURL,
            emitDigest: false,
            currentPlatforms: nil
        )

        _ = try action.perform(logHandle: .standardOutput)

        let dataURL = targetBundleURL.appendingPathComponent("data")
        let dataProvider = try LocalFileSystemDataProvider(rootURL: dataURL)

        let testTemplateURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try Folder.testHTMLTemplateDirectory.write(to: testTemplateURL)
        defer { try? fileManager.removeItem(at: testTemplateURL) }

        let basePaths = ["test": "test",
                         "/test": "test",
                         "test/": "test",
                         "/test/": "test",
                         "test/test": "test/test",
                         "/test/test": "test/test",
                         "test/test/": "test/test",
                         "/test/test/": "test/test"]

        for (basePath, testValue) in basePaths {

            let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            defer { try? fileManager.removeItem(at: outputURL) }

            let transformer = try StaticHostableTransformer(dataProvider: dataProvider, fileManager: fileManager, outputURL: outputURL, htmlTemplate: testTemplateURL, staticHostingBasePath: basePath)

            try transformer.transform()


            // Test an output folder exists
            guard fileManager.fileExists(atPath: outputURL.path) else {
                XCTFail("StaticHostableTransformer failed to create output folder")
                return
            }

            let indexHTML = Folder.testHTMLTemplate(basePath: testValue)
            try compareIndexHTML(fileManager: fileManager, folder: outputURL, indexHTML: indexHTML)
        }
    }


    private func compareIndexHTML(fileManager: FileManagerProtocol, folder: URL, indexHTML: String) throws {

        for item in try fileManager.contentsOfDirectory(atPath: folder.path) {

            guard item == "index.html" else {
                let subFolder = folder.appendingPathComponent(item)
                try compareIndexHTML(fileManager: fileManager, folder: subFolder, indexHTML: indexHTML)
                continue
            }
            let indexFileURL = folder.appendingPathComponent("index.html")
            let testHTMLString = try String(contentsOf: indexFileURL)
            XCTAssertEqual(testHTMLString, indexHTML, "Unexpected content in index.html at \(indexFileURL)")
        }
    }
}

