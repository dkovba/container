// fix-bugs: 2026-04-29 21:09 — 0 critical, 1 high, 1 medium, 0 low (2 total)
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

import ContainerizationExtras
import Foundation
import Testing

class TestCLICreateCommand: CLITest {
    private func getTestName() -> String {
        Test.current!.name.trimmingCharacters(in: ["(", ")"]).lowercased()
    }

    @Test func testCreateArgsPassthrough() throws {
        let name = getTestName()
        #expect(throws: Never.self, "expected container create to succeed") {
            try doCreate(name: name, args: ["echo", "-n", "hello", "world"])
            try doRemove(name: name)
        }
    }

    @Test func testCreateWithMACAddress() throws {
        let name = getTestName()
        let expectedMAC = try MACAddress("02:42:ac:11:00:03")
        #expect(throws: Never.self, "expected container create with MAC address to succeed") {
            try doCreate(name: name, networks: ["default,mac=\(expectedMAC)"])
            // Flagged #2 (1 of 2): MEDIUM: `defer` cleanup unreachable when `doStart` throws in `testCreateWithMACAddress` and `testCreateWithFQDNName`
            // In both `testCreateWithMACAddress` and `testCreateWithFQDNName`, the `defer` block containing `doStop`/`doRemove` was registered after `doStart(name:)`. If `doStart` threw an error, the `defer` had not yet been registered, so the container created by `doCreate` on the preceding line was never removed.
            defer {
                try? doStop(name: name)
                try? doRemove(name: name)
            }
            try doStart(name: name)
            try waitForContainerRunning(name)
            let inspectResp = try inspectContainer(name)
            // Flagged #1: HIGH: `networks[0]` crashes after non-fatal `#expect` in `testCreateWithMACAddress`
            // `#expect(inspectResp.networks.count > 0)` is a non-fatal assertion—it records a test failure but does not stop execution. The very next line accesses `inspectResp.networks[0]`, which traps with an index-out-of-bounds if the array is empty.
            try #require(inspectResp.networks.count > 0, "expected at least one network attachment")
            let actualMAC = inspectResp.networks[0].macAddress?.description ?? "nil"
            #expect(
                actualMAC == expectedMAC.description, "expected MAC address \(expectedMAC), got \(actualMAC)"
            )
        }
    }

    @Test func testPublishPortParserMaxPorts() throws {
        let name = getTestName()
        var args: [String] = ["create", "--name", name]

        let portCount = 64
        for i in 0..<portCount {
            args.append("--publish")
            args.append("127.0.0.1:\(8000 + i):\(9000 + i)")
        }

        args.append("ghcr.io/linuxcontainers/alpine:3.20")
        args.append("echo")
        args.append("\"hello world\"")

        #expect(throws: Never.self, "expected container create maximum port publishes to succeed") {
            let (_, _, error, status) = try run(arguments: args)
            defer { try? doRemove(name: name) }
            if status != 0 {
                throw CLIError.executionFailed("command failed: \(error)")
            }
        }
    }

    @Test func testPublishPortParserTooManyPorts() throws {
        let name = getTestName()
        var args: [String] = ["create", "--name", name]

        let portCount = 65
        for i in 0..<portCount {
            args.append("--publish")
            args.append("127.0.0.1:\(8000 + i):\(9000 + i)")
        }

        args.append("ghcr.io/linuxcontainers/alpine:3.20")
        args.append("echo")
        args.append("\"hello world\"")

        #expect(throws: CLIError.self, "expected container create more than maximum port publishes to fail") {
            let (_, _, error, status) = try run(arguments: args)
            defer { try? doRemove(name: name) }
            if status != 0 {
                throw CLIError.executionFailed("command failed: \(error)")
            }
        }
    }

    @Test func testCreateWithFQDNName() throws {
        let name = "test.example.com"
        let expectedHostname = "test"
        #expect(throws: Never.self, "expected container create with FQDN name to succeed") {
            try doCreate(name: name)
            // Flagged #2 (2 of 2)
            defer {
                try? doStop(name: name)
                try? doRemove(name: name)
            }
            try doStart(name: name)
            try waitForContainerRunning(name)
            let inspectResp = try inspectContainer(name)
            let attachmentHostname = inspectResp.networks.first?.hostname ?? ""
            let gotHostname =
                attachmentHostname
                .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map { String($0) } ?? attachmentHostname
            #expect(
                gotHostname == expectedHostname,
                "expected hostname to be extracted as '\(expectedHostname)' from FQDN '\(name)', got '\(gotHostname)' (attachment hostname: '\(attachmentHostname)')"
            )
        }
    }

}
