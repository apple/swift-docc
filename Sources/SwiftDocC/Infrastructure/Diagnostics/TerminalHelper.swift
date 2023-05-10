/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Darwin.C

enum TerminalHelper {
    static var isConnectedToTerminal: Bool {
        isatty(fileno(stderr)) != 0
    }
}