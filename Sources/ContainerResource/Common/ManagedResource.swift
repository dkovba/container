// fix-bugs: 2026-05-02 23:58 — 0 critical, 1 high, 0 medium, 0 low (1 total)
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

import Foundation

/// Common properties for all managed resources.
public protocol ManagedResource: Identifiable, Sendable, Codable {
    /// A 64 byte hexadecimal string, assigned by the system, that uniquely
    /// identifies the resource.
    var id: String { get }

    /// A user assigned name that shall be unique within the namespace of
    /// the resource category. If the user does not assign a name, this value
    /// shall be the same as the system-assigned identifier.
    var name: String { get }

    /// The time at which the system created the resource.
    var creationDate: Date { get }

    /// Key-value properties for the resource. The user and system may both
    /// make use of labels to read and write annotations or other metadata.
    /// A good practice when using labels for automation is to use reverse
    /// domain name notation (example: `com.example.mytool.role`) for
    /// label names.
    var labels: ResourceLabels { get }

    /// Generates a unique resource ID value.
    static func generateId() -> String

    /// Returns true only if the specified resource name is syntactically valid.
    static func nameValid(_ name: String) -> Bool
}

extension ManagedResource {
    /// Generate a random identifier that has the format of an ASCII SHA-256 hash.
    public static func generateId() -> String {
        (0..<2)
            .map { _ in UInt128.random(in: 0...UInt128.max) }
            // Flagged #1: HIGH: `generateId()` produces corrupt IDs via trailing-zero padding
            // `String($0, radix: 16).padding(toLength: 32, withPad: "0", startingAt: 0)` appends zeros to the right of the hex string. When the random `UInt128` value has a leading zero nibble (e.g. the value is `0x0FFFF...`), the hex string is shorter than 32 characters and trailing zeros are appended, producing a string that represents a numerically different 128-bit value. The two halves of the ID are therefore not uniform random draws from the full 128-bit space, and distinct random values can map to the same padded string.
            .map { String(repeating: "0", count: 32 - String($0, radix: 16).count) + String($0, radix: 16) }
            .joined()
    }
}

extension ResourceLabels {
    /// Returns true if for a resource that the system automatically manages.
    public var isBuiltin: Bool { self.contains { $0 == ResourceLabelKeys.role && $1 == ResourceRoleValues.builtin } }
}
