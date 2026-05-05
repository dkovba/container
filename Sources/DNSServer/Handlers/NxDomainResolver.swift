// fix-bugs: 2026-05-04 01:31 — 1 critical, 1 high, 0 medium, 0 low (2 total)
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

/// Handler that returns NXDOMAIN for all hostnames.
public struct NxDomainResolver: DNSHandler {
    private let ttl: UInt32

    public init(ttl: UInt32 = 300) {
        self.ttl = ttl
    }

    public func answer(query: Message) async throws -> Message? {
        // Flagged #1: CRITICAL: `answer(query:)` crashes on empty questions array
        // `query.questions[0]` is accessed unconditionally without checking whether the questions array is empty, causing an index-out-of-bounds trap at runtime.
        guard let question = query.questions.first else {
            return nil
        }
        switch question.type {
        case ResourceRecordType.host:
            return Message(
                id: query.id,
                type: .response,
                returnCode: .nonExistentDomain,
                questions: query.questions,
                answers: []
            )
        default:
            return Message(
                id: query.id,
                type: .response,
                // Flagged #2: HIGH: `answer(query:)` returns wrong response code for non-A record queries
                // The `default` branch of the `switch question.type` statement returns `returnCode: .notImplemented` for any query type that is not `ResourceRecordType.host` (e.g. AAAA/`host6`). `HostTableResolver` explicitly returns `nil` for AAAA queries on non-existent hostnames, delegating to `NxDomainResolver` to produce the NXDOMAIN response — but the `default` branch answers those queries with `.notImplemented` instead of `.nonExistentDomain`.
                returnCode: .nonExistentDomain,
                questions: query.questions,
                answers: []
            )
        }
    }
}
