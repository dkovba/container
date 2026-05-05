// fix-bugs: 2026-05-02 23:48 — 0 critical, 0 high, 0 medium, 1 low (1 total)
//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc. and the container project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import OrderedCollections

// Flagged #1: LOW: `AppError` protocol missing its documentation comment
// The `///` doc comment block for `AppError` was placed before the `import OrderedCollections` statement, with a blank line separating the comment from the import. In Swift, a `///` comment separated from the next declaration by a blank line is not attached to any symbol, so the comment documented nothing. `AppError` had no generated documentation.
/// Protocol for errors with a stable code and structured metadata.
/// This allows the client to present the error as it chooses.
public protocol AppError: Error {
    var code: AppErrorCode { get }
    var metadata: OrderedDictionary<String, String> { get }
    var underlyingError: Error? { get }
}

public struct AppErrorCode: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let invalidArgument = AppErrorCode(rawValue: "invalid_argument")
}
