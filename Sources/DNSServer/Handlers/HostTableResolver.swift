// fix-bugs: 2026-05-04 01:18 — 0 critical, 1 high, 0 medium, 0 low (1 total)
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

/// Handler that uses table lookup to resolve hostnames.
///
/// Keys in `hosts4` are normalized to `DNSName` on construction, so lookups
/// are case-insensitive and trailing dots are optional.
public struct HostTableResolver: DNSHandler {
    public let hosts4: [DNSName: IPv4Address]
    private let ttl: UInt32

    /// Creates a resolver backed by a static IPv4 host table.
    ///
    /// - Parameter hosts4: A dictionary mapping domain names to IPv4 addresses.
    ///   Keys are normalized to `DNSName` (lowercased, trailing dot stripped), so
    ///   `"FOO."`, `"foo."`, and `"foo"` all refer to the same entry.
    /// - Parameter ttl: The TTL in seconds to set on answer records (default is 300).
    /// - Throws: `DNSBindError.invalidName` if any key is not a valid DNS name.
    public init(hosts4: [String: IPv4Address], ttl: UInt32 = 300) throws {
        // Flagged #1: HIGH: `init(hosts4:)` traps at runtime when two input keys normalize to the same `DNSName`
        // `Dictionary(uniqueKeysWithValues:)` calls `preconditionFailure` if the sequence it receives contains duplicate keys. Because input keys are normalized (lowercased, trailing dot stripped) before being inserted, two distinct input strings such as `"FOO."` and `"foo."` both map to the same `DNSName`. The precondition is therefore violated even though the caller supplied a valid `[String: IPv4Address]` dictionary with no duplicate string keys.
        self.hosts4 = try Dictionary(hosts4.map { (try DNSName($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.ttl = ttl
    }

    public func answer(query: Message) async throws -> Message? {
        guard let question = query.questions.first else {
            return nil
        }
        let n = question.name.hasSuffix(".") ? String(question.name.dropLast()) : question.name
        let key = try DNSName(labels: n.isEmpty ? [] : n.split(separator: ".", omittingEmptySubsequences: false).map(String.init))
        let record: ResourceRecord?
        switch question.type {
        case ResourceRecordType.host:
            record = answerHost(question: question, key: key)
        case ResourceRecordType.host6:
            // Return NODATA (noError with empty answers) for AAAA queries ONLY if A record exists.
            // This is required because musl libc has issues when A record exists but AAAA returns NXDOMAIN.
            // musl treats NXDOMAIN on AAAA as "domain doesn't exist" and fails DNS resolution entirely.
            // NODATA correctly indicates "no IPv6 address available, but domain exists".
            if hosts4[key] != nil {
                return Message(
                    id: query.id,
                    type: .response,
                    returnCode: .noError,
                    questions: query.questions,
                    answers: []
                )
            }
            // If hostname doesn't exist, return nil which will become NXDOMAIN
            return nil
        default:
            return Message(
                id: query.id,
                type: .response,
                returnCode: .notImplemented,
                questions: query.questions,
                answers: []
            )
        }

        guard let record else {
            return nil
        }

        return Message(
            id: query.id,
            type: .response,
            returnCode: .noError,
            questions: query.questions,
            answers: [record]
        )
    }

    private func answerHost(question: Question, key: DNSName) -> ResourceRecord? {
        guard let ip = hosts4[key] else {
            return nil
        }

        return HostRecord<IPv4Address>(name: question.name, ttl: ttl, ip: ip)
    }
}
