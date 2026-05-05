// fix-bugs: 2026-05-09 14:19 — 0 critical, 1 high, 0 medium, 0 low (1 total)
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

import Testing

@testable import DNSServer

struct NxDomainResolverTest {
    @Test func testUnsupportedQuestionType() async throws {
        let handler: NxDomainResolver = NxDomainResolver()

        let query = Message(
            id: UInt16(1),
            type: .query,
            questions: [
                Question(name: "foo.", type: .host6)
            ])

        let response = try await handler.answer(query: query)

        // Flagged #1: HIGH: `testUnsupportedQuestionType` asserts the wrong return code for non-A queries
        // The test expected `.notImplemented` as the return code when `NxDomainResolver` handles a non-A query (e.g. AAAA/`host6`). `NxDomainResolver` is a catch-all fallback resolver whose contract is to return NXDOMAIN for every query that reaches it, regardless of record type. The production implementation's `default` branch was returning `.notImplemented` (a bug in the source), and this test was written to match that buggy behavior rather than the correct behavior.
        #expect(.nonExistentDomain == response?.returnCode)
        #expect(1 == response?.id)
        #expect(.response == response?.type)
        #expect(1 == response?.questions.count)
        #expect(0 == response?.answers.count)
    }

    @Test func testHostNotPresent() async throws {
        let handler: NxDomainResolver = NxDomainResolver()

        let query = Message(
            id: UInt16(1),
            type: .query,
            questions: [
                Question(name: "bar.", type: .host)
            ])

        let response = try await handler.answer(query: query)

        #expect(.nonExistentDomain == response?.returnCode)
        #expect(1 == response?.id)
        #expect(.response == response?.type)
        #expect(1 == response?.questions.count)
        #expect(0 == response?.answers.count)
    }
}
