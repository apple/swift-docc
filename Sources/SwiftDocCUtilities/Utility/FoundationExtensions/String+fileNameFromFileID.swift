/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension String {
    /// Returns the name of the file in the given Swift `#fileID`.
    ///
    /// See https://docs.swift.org/swift-book/ReferenceManual/Expressions.html#ID389
    /// for details on Swift's `#fileID` expression.
    var fileNameFromFileID: Substring {
        let trailingSlash = lastIndex(of: "/").map(index(after:)) ?? startIndex
        let trailingPeriod = self[trailingSlash...].lastIndex(of: ".") ?? endIndex
        return self[trailingSlash..<trailingPeriod]
    }
}
