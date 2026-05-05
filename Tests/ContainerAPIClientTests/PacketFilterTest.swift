// fix-bugs: 2026-05-09 03:10 — 0 critical, 1 high, 0 medium, 0 low (1 total)
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

import ContainerizationError
import ContainerizationExtras
import Foundation
import Testing

@testable import ContainerAPIClient

struct PacketFilterTest {
    @Test
    func testRedirectRuleUpdate() async throws {
        let fm = FileManager.default
        let tempURL = try fm.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: .temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let configURL = tempURL.appending(path: "pf.conf")

        let pf = PacketFilter(configURL: configURL, anchorsURL: tempURL)
        let from1 = try! IPAddress("203.0.113.113")
        let domain1 = "aaa.com"
        let to = try! IPAddress("127.0.0.1")
        try pf.createRedirectRule(from: from1, to: to, domain: domain1)

        let anchorURL = tempURL.appending(path: "com.apple.container")
        var actualAnchorText = try String(contentsOf: anchorURL, encoding: .utf8)
        var expectedAnchorTest = """
            rdr inet from any to \(from1) -> \(to) # \(domain1)\n
            """

        #expect(actualAnchorText == expectedAnchorTest)

        let from2 = try! IPAddress("172.31.72.1")
        let domain2 = "bbb.com"
        try pf.createRedirectRule(from: from2, to: to, domain: domain2)

        actualAnchorText = try String(contentsOf: anchorURL, encoding: .utf8)
        expectedAnchorTest += """
            rdr inet from any to \(from2) -> \(to) # \(domain2)\n
            """
        #expect(actualAnchorText == expectedAnchorTest)

        let actualConfigText = try String(contentsOf: configURL, encoding: .utf8)
        let expectedConfigText = try Regex(
            #"""
            scrub-anchor "([^"]+)"
            nat-anchor "([^"]+)"
            rdr-anchor "([^"]+)"
            dummynet-anchor "([^"]+)"
            anchor "([^"]+)"
            load anchor "([^"]+)" from "[^"]+"
            """#
        )

        #expect(actualConfigText.contains(expectedConfigText))

        try pf.removeRedirectRule(from: from1, to: to, domain: domain1)
        try pf.removeRedirectRule(from: from2, to: to, domain: domain2)

        #expect(!fm.fileExists(atPath: anchorURL.path))
        let configText = try String(contentsOf: configURL, encoding: .utf8)
        #expect(configText == "")
    }

    @Test
    func testPacketFilterReinitialize() async throws {
        // Flagged #1: HIGH: `testPacketFilterReinitialize` always expects a throw, failing when run as root
        // `#expect(throws: ContainerizationError.self) { try pf.reinitialize() }` unconditionally requires `reinitialize()` to throw. When the test is run as root, `pfctl -n -f /etc/pf.conf` and `pfctl -f /etc/pf.conf` both succeed, so `reinitialize()` returns normally and no error is thrown, causing the `#expect(throws:)` assertion to record a test failure.
        guard getuid() != 0 else { return }
        let pf = PacketFilter()
        #expect(throws: ContainerizationError.self) {
            try pf.reinitialize()
        }
    }
}
