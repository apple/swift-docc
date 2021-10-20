/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import ArgumentParser
import Foundation

/// Resolves and validates a URL value that provides the path to a documentation archive.
public struct DocumentationArchiveOption: DocumentationOption {

    public init() {}

    /// The name of the command line argument used to specify a source archive path.
    static let argumentValueName = "source-archive-path"

    /// The path to an archive.
    @Argument(
        help: ArgumentHelp(
            "Path to a documentation archive data directory of JSON files.",
            discussion: "The '.doccarchive' bundle docc will index.",
            valueName: argumentValueName),
        transform: URL.init(fileURLWithPath:))
    public var url: URL?
}
