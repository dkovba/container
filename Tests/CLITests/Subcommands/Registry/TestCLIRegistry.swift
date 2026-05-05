// fix-bugs: 2026-04-30 14:15 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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
import Testing

class TestCLIRegistry: CLITest {
    @Test func testListDefaultFormat() throws {
        let (_, output, error, status) = try run(arguments: ["registry", "list"])
        #expect(status == 0, "registry list should succeed, stderr: \(error)")

        let requiredHeaders = ["HOSTNAME", "USERNAME", "MODIFIED", "CREATED"]
        #expect(
            requiredHeaders.allSatisfy { output.contains($0) },
            "output should contain all required headers"
        )
    }

    @Test func testListJSONFormat() throws {
        let (data, _, error, status) = try run(arguments: ["registry", "list", "--format", "json"])
        // Flagged #1 (1 of 2): MEDIUM: `#expect` instead of `#require` for status checks allows dependent code to execute after command failure
        // Two test methods (`testListJSONFormat`, `testListQuietMode`) used `#expect(status == 0, ...)` which is non-fatal, then executed code that depends on the command having succeeded. When the command fails, `#expect` records a failure but continues execution: in `testListJSONFormat`, `JSONSerialization.jsonObject(with: data)` throws a confusing JSON-parsing error on empty data; in `testListQuietMode`, the negative assertions `!output.contains("HOSTNAME")` and `!output.contains("USERNAME")` pass trivially on empty output, producing false passes that mask the real failure.
        try #require(status == 0, "registry list --format json should succeed, stderr: \(error)")

        let json = try JSONSerialization.jsonObject(with: data, options: [])
        #expect(json is [Any], "JSON output should be an array")
    }

    @Test func testListQuietMode() throws {
        let (_, output, error, status) = try run(arguments: ["registry", "list", "-q"])
        // Flagged #1 (2 of 2)
        try #require(status == 0, "registry list -q should succeed, stderr: \(error)")

        #expect(!output.contains("HOSTNAME"), "quiet mode should not contain headers")
        #expect(!output.contains("USERNAME"), "quiet mode should not contain headers")
    }
}
