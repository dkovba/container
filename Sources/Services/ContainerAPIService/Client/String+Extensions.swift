// fix-bugs: 2026-04-28 22:01 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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

extension String {
    public func fromISO8601DateString(to: String) -> String? {
        if let date = fromISO8601Date() {
            let dateformatTo = DateFormatter()
            dateformatTo.dateFormat = to
            return dateformatTo.string(from: date)
        }
        return nil
    }

    public func fromISO8601Date() -> Date? {
        let iso8601DateFormatter = ISO8601DateFormatter()
        iso8601DateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Flagged #1: MEDIUM: `fromISO8601Date()` fails to parse valid ISO 8601 dates without fractional seconds
        // `.withFractionalSeconds` option makes the formatter reject any ISO 8601 date string that does not contain fractional seconds (e.g., `"2024-01-01T00:00:00Z"` returns `nil`).
        if let date = iso8601DateFormatter.date(from: self) {
            return date
        }
        iso8601DateFormatter.formatOptions = [.withInternetDateTime]
        return iso8601DateFormatter.date(from: self)
    }

    public func isAbsolutePath() -> Bool {
        self.starts(with: "/")
    }

    /// Trim all `char` characters from the left side of the string. Stops when encountering a character that
    /// doesn't match `char`.
    mutating public func trimLeft(char: Character) {
        if self.isEmpty {
            return
        }
        var trimTo = 0
        for c in self {
            if char != c {
                break
            }
            trimTo += 1
        }
        if trimTo != 0 {
            let index = self.index(self.startIndex, offsetBy: trimTo)
            self = String(self[index...])
        }
    }
}
