/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2022 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

extension URL {
    /// Returns true if the scheme is not `nil` , not `file:`, not `ResolvedTopicReference.urlScheme`.
    ///
    /// - Returns: A Boolean value indicating whether the url is an absolute web URL.
    var isAbsoluteWebURL: Bool {
        guard !isFileURL,
              let scheme ,
              !scheme.isEmpty,
              scheme != ResolvedTopicReference.urlScheme else {
            return false
        }
        return true
    }
}
