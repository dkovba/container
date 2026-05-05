// fix-bugs: 2026-05-09 00:37 — 0 critical, 1 high, 0 medium, 0 low (1 total)
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

/// A theme for progress bar.
public protocol ProgressTheme: Sendable {
    /// The icons used to represent a spinner.
    var spinner: [String] { get }
    /// The icon used to represent a progress bar.
    var bar: String { get }
    /// The icon used to indicate that a progress bar finished.
    var done: String { get }
}

public struct DefaultProgressTheme: ProgressTheme {
    public let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    public let bar = "█"
    public let done = "✔"
}

extension ProgressTheme {
    func getSpinnerIcon(_ iteration: Int) -> String {
        // Flagged #1: HIGH: `getSpinnerIcon` crashes with a division-by-zero trap when `spinner` is empty
        // `spinner[iteration % spinner.count]` performs integer modulo with `spinner.count` as the divisor. When a conforming type returns an empty `spinner` array, `spinner.count` is `0`, and Swift traps on integer division by zero at runtime before the array subscript is even reached.
        guard !spinner.isEmpty else { return "" }
        return spinner[iteration % spinner.count]
    }
}
