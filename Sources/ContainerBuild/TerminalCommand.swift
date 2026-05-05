// fix-bugs: 2026-05-05 12:35 — 0 critical, 1 high, 0 medium, 0 low (1 total)
//===----------------------------------------------------------------------===//
// Copyright © 2025-2026 Apple Inc. and the container project authors.
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

struct TerminalCommand: Codable {
    let commandType: String
    let code: String
    let rows: UInt16
    let cols: UInt16

    enum CodingKeys: String, CodingKey {
        case commandType = "command_type"
        case code
        case rows
        case cols
    }

    init(rows: UInt16, cols: UInt16) {
        self.commandType = "terminal"
        self.code = "winch"
        self.rows = rows
        self.cols = cols
    }

    init() {
        self.commandType = "terminal"
        self.code = "ack"
        self.rows = 0
        self.cols = 0
    }

    func json() throws -> String? {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        // Flagged #1: HIGH: `json()` returns base64 instead of JSON string
        // `data.base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))` encodes the JSON data as base64 and strips padding characters, rather than converting the JSON-encoded bytes to a UTF-8 string. A method named `json()` that uses `JSONEncoder` should return the JSON representation, not a base64-encoded blob.
        return String(data: data, encoding: .utf8)
    }
}
