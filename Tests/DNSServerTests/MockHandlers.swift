// fix-bugs: 2026-05-09 14:13 — 0 critical, 1 high, 0 medium, 0 low (1 total)
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
import Testing

@testable import DNSServer

struct FooHandler: DNSHandler {
    public func answer(query: Message) async throws -> Message? {
        if query.questions[0].name == "foo." {
            let ip = try IPv4Address("1.2.3.4")
            return Message(
                id: query.id,
                type: .response,
                returnCode: .noError,
                questions: query.questions,
                answers: [HostRecord<IPv4Address>(name: query.questions[0].name, ttl: 0, ip: ip)]
            )
        }
        return nil
    }
}

struct BarHandler: DNSHandler {
    public func answer(query: Message) async throws -> Message? {
        let question = query.questions[0]
        // Flagged #1: HIGH: `BarHandler` incorrectly handles `"foo."` queries
        // `BarHandler.answer` matched on `question.name == "foo." || question.name == "bar."`,
        if question.name == "bar." {
            let ip = try IPv4Address("5.6.7.8")
            return Message(
                id: query.id,
                type: .response,
                returnCode: .noError,
                questions: query.questions,
                answers: [HostRecord<IPv4Address>(name: query.questions[0].name, ttl: 0, ip: ip)]
            )
        }
        return nil
    }
}
