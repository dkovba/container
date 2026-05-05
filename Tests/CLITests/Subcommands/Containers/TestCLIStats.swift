// fix-bugs: 2026-04-30 12:41 — 0 critical, 0 high, 2 medium, 0 low (2 total)
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

import ContainerResource
import Foundation
import Testing

class TestCLIStatsCommand: CLITest {
    private func getTestName() -> String {
        Test.current!.name.trimmingCharacters(in: ["(", ")"]).lowercased()
    }

    @Test func testStatsNoStreamJSONFormat() throws {
        let name = getTestName()
        #expect(throws: Never.self, "expected stats command to succeed") {
            // Flagged #1 (1 of 5): MEDIUM: `defer` cleanup unreachable when `doLongRun` throws
            // In five test methods (`testStatsNoStreamJSONFormat`, `testStatsIdleCPUPercentage`, `testStatsHighCPUPercentage`, `testStatsTableFormat`, `testStatsAllContainers`), the `defer` block containing `doStop`/`doRemove` is registered after the `doLongRun` call(s). If `doLongRun` throws, the `defer` has not yet been registered, so containers created by a partially-successful run are never stopped or removed. The `testStatsAllContainers` case is the worst: the `defer` is registered after both `doLongRun` calls, so if the second one throws, the container successfully created by the first `doLongRun` is orphaned.
            defer {
                try? doStop(name: name)
                try? doRemove(name: name)
            }
            try doLongRun(name: name)
            try waitForContainerRunning(name)

            let (data, _, error, status) = try run(arguments: [
                "stats",
                "--format", "json",
                "--no-stream",
                name,
            ])

            try #require(status == 0, "stats command should succeed, error: \(error)")

            let decoder = JSONDecoder()
            let stats = try decoder.decode([ContainerStats].self, from: data)

            // Flagged #2 (1 of 3): MEDIUM: `#expect` instead of `#require` before collection subscript causes index-out-of-bounds crash
            // In three test methods (`testStatsNoStreamJSONFormat`, `testStatsIdleCPUPercentage`, `testStatsHighCPUPercentage`), the collection size is validated with `#expect` (a non-fatal assertion that records a failure but continues execution) immediately before accessing the collection by index. In `testStatsNoStreamJSONFormat` (line 48), `#expect(stats.count == 1, ...)` is followed by `stats[0]` accesses on subsequent lines. In `testStatsIdleCPUPercentage` (line 85) and `testStatsHighCPUPercentage` (line 130), `#expect(columns.count >= 2, ...)` is followed by `columns[1]` access. If the collection is empty or too short, `#expect` logs the failure but does not stop execution, so the subscript access crashes with an index-out-of-bounds error.
            try #require(stats.count == 1, "expected stats for one container")
            #expect(stats[0].id == name, "container ID should match")
            let memoryUsageBytes = try #require(stats[0].memoryUsageBytes)
            let numProcesses = try #require(stats[0].numProcesses)
            #expect(memoryUsageBytes > 0, "memory usage should be non-zero")
            #expect(numProcesses >= 1, "should have at least one process")
        }
    }

    @Test func testStatsIdleCPUPercentage() throws {
        let name = getTestName()
        #expect(throws: Never.self, "expected stats to show low CPU for idle container") {
            // Flagged #1 (2 of 5)
            defer {
                try? doStop(name: name)
                try? doRemove(name: name)
            }
            try doLongRun(name: name, containerArgs: ["sleep", "3600"])
            try waitForContainerRunning(name)

            // Get stats in table format
            let (_, output, _, status) = try run(arguments: [
                "stats",
                "--no-stream",
                name,
            ])
            try #require(status == 0, "stats command should succeed")

            // Parse the table output
            let lines = output.components(separatedBy: .newlines)
            #expect(lines.count >= 2, "should have at least header and one data row")

            // Find the data row (not the header)
            let dataLine = lines.first { $0.contains(name) }
            try #require(dataLine != nil, "should find container data row")

            // Extract CPU percentage - it should be in the second column
            let columns = dataLine!.split(separator: " ").filter { !$0.isEmpty }
            // Flagged #2 (2 of 3)
            try #require(columns.count >= 2, "should have at least 2 columns")

            // Second column is CPU%
            let cpuString = String(columns[1])
            #expect(cpuString.hasSuffix("%"), "CPU column should end with %")

            // Parse the percentage
            let cpuValue = Double(cpuString.dropLast())
            try #require(cpuValue != nil, "should be able to parse CPU percentage")

            // Idle container should use very little CPU (less than 5%)
            #expect(cpuValue! < 5.0, "idle container CPU should be < 5%, got \(cpuValue!)%")
        }
    }

    @Test func testStatsHighCPUPercentage() throws {
        let name = getTestName()
        #expect(throws: Never.self, "expected stats to show high CPU for busy container") {
            // Run a container with a busy loop
            // Flagged #1 (3 of 5)
            defer {
                try? doStop(name: name)
                try? doRemove(name: name)
            }
            try doLongRun(name: name, containerArgs: ["sh", "-c", "while true; do :; done"])
            try waitForContainerRunning(name)

            // Get stats in table format
            let (_, output, _, status) = try run(arguments: [
                "stats",
                "--no-stream",
                name,
            ])
            try #require(status == 0, "stats command should succeed")

            // Parse the table output
            let lines = output.components(separatedBy: .newlines)
            #expect(lines.count >= 2, "should have at least header and one data row")

            // Find the data row (not the header)
            let dataLine = lines.first { $0.contains(name) }
            try #require(dataLine != nil, "should find container data row")

            // Extract CPU percentage - it should be in the second column
            // Format is like: "container_id   95.23%   ..."
            let columns = dataLine!.split(separator: " ").filter { !$0.isEmpty }
            // Flagged #2 (3 of 3)
            try #require(columns.count >= 2, "should have at least 2 columns")

            // Second column is CPU%
            let cpuString = String(columns[1])
            #expect(cpuString.hasSuffix("%"), "CPU column should end with %")

            // Parse the percentage
            let cpuValue = Double(cpuString.dropLast())
            try #require(cpuValue != nil, "should be able to parse CPU percentage")

            // Busy loop should use significant CPU (at least 50% of one core)
            #expect(cpuValue! > 50.0, "busy container CPU should be > 50%, got \(cpuValue!)%")
            // Should not exceed reasonable limits (one core doing while loop = ~100%)
            #expect(cpuValue! < 150.0, "single busy loop should not exceed 150%, got \(cpuValue!)%")
        }
    }

    @Test func testStatsTableFormat() throws {
        let name = getTestName()
        #expect(throws: Never.self, "expected stats table format to work") {
            // Flagged #1 (4 of 5)
            defer {
                try? doStop(name: name)
                try? doRemove(name: name)
            }
            try doLongRun(name: name)
            try waitForContainerRunning(name)

            // Get stats in table format
            let (_, output, error, status) = try run(arguments: [
                "stats",
                "--no-stream",
                name,
            ])

            try #require(status == 0, "stats command should succeed, error: \(error)")
            #expect(output.contains("Container ID"), "output should contain table header")
            #expect(output.contains("Cpu %"), "output should contain CPU column")
            #expect(output.contains("Memory Usage"), "output should contain Memory column")
            #expect(output.contains(name), "output should contain container name")
        }
    }

    @Test func testStatsAllContainers() throws {
        let name1 = getTestName() + "-1"
        let name2 = getTestName() + "-2"
        #expect(throws: Never.self, "expected stats for all containers") {
            // Flagged #1 (5 of 5)
            defer {
                try? doStop(name: name1)
                try? doStop(name: name2)
                try? doRemove(name: name1)
                try? doRemove(name: name2)
            }
            try doLongRun(name: name1)
            try doLongRun(name: name2)
            try waitForContainerRunning(name1)
            try waitForContainerRunning(name2)

            // Get stats for all containers (no name specified)
            let (data, _, error, status) = try run(arguments: [
                "stats",
                "--format", "json",
                "--no-stream",
            ])

            try #require(status == 0, "stats command should succeed, error: \(error)")

            let stats = try JSONDecoder().decode([ContainerStats].self, from: data)

            // Should have stats for both containers
            try #require(stats.count >= 2, "should have stats for at least 2 containers")

            let containerIds = stats.map { $0.id }
            #expect(containerIds.contains(name1), "should include first container")
            #expect(containerIds.contains(name2), "should include second container")
        }
    }

    @Test func testStatsNonExistentContainer() throws {
        #expect(throws: Never.self, "expected stats to fail for non-existent container") {
            let (_, _, _, status) = try run(arguments: [
                "stats",
                "--no-stream",
                "nonexistent-container-xyz",
            ])

            #expect(status != 0, "stats command should fail for non-existent container")
        }
    }
}
