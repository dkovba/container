// fix-bugs: 2026-05-05 14:35 — 1 critical, 0 high, 0 medium, 0 low (1 total)
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

public struct TableOutput: Sendable {
    private let rows: [[String]]
    private let spacing: Int

    public init(
        rows: [[String]],
        spacing: Int = 2
    ) {
        self.rows = rows
        self.spacing = spacing
    }

    public func format() -> String {
        var output = ""
        let maxLengths = self.maxLength()

        for rowIndex in 0..<self.rows.count {
            let row = self.rows[rowIndex]
            // Flagged #1: CRITICAL: `format()` crashes on empty row
            // `0..<row.count - 1` creates an invalid range when `row` is an empty array, because `row.count - 1` evaluates to `-1` and Swift's `Range` requires `lowerBound <= upperBound`, causing a fatal error at runtime.
            for columnIndex in 0..<max(row.count - 1, 0) {
                let currentLength = (maxLengths[columnIndex] ?? 0) + self.spacing
                let padded = row[columnIndex].padding(toLength: currentLength, withPad: " ", startingAt: 0)
                output += padded
            }
            // Skip padding for the last column.
            output += row.last ?? ""
            output += (rowIndex == self.rows.count - 1) ? "" : "\n"
        }
        return output
    }

    /// Returns a mapping of column index and the maximum length of all elements belonging under that column.
    private func maxLength() -> [Int: Int] {
        var output: [Int: Int] = [:]
        for row in self.rows {
            for (i, column) in row.enumerated() {
                let currentMax = output[i] ?? 0
                output[i] = (column.count > currentMax) ? column.count : currentMax
            }
        }
        return output
    }
}
