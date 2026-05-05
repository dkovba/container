// fix-bugs: 2026-05-04 13:29 — 0 critical, 1 high, 1 medium, 0 low (2 total)
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

/// A DNS message (query or response).
///
/// Wire format (RFC 1035):
/// ```
/// +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// |                      ID                       |
/// +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// |QR|   Opcode  |AA|TC|RD|RA|   Z    |   RCODE   |
/// +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// |                    QDCOUNT                    |
/// +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// |                    ANCOUNT                    |
/// +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// |                    NSCOUNT                    |
/// +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// |                    ARCOUNT                    |
/// +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
/// ```
public struct Message: Sendable {
    /// Header size in bytes.
    public static let headerSize = 12

    /// Transaction ID.
    public var id: UInt16

    /// Message type (query or response).
    public var type: MessageType

    /// Operation code.
    public var operationCode: OperationCode

    /// Authoritative answer flag.
    public var authoritativeAnswer: Bool

    /// Truncation flag.
    public var truncation: Bool

    /// Recursion desired flag.
    public var recursionDesired: Bool

    /// Recursion available flag.
    public var recursionAvailable: Bool

    /// Response code.
    public var returnCode: ReturnCode

    /// Questions in this message.
    public var questions: [Question]

    /// Answer resource records.
    public var answers: [ResourceRecord]

    /// Authority resource records.
    public var authorities: [ResourceRecord]

    /// Additional resource records.
    public var additional: [ResourceRecord]

    /// Creates a new DNS message.
    public init(
        id: UInt16 = 0,
        type: MessageType = .query,
        operationCode: OperationCode = .query,
        authoritativeAnswer: Bool = false,
        truncation: Bool = false,
        recursionDesired: Bool = false,
        recursionAvailable: Bool = false,
        returnCode: ReturnCode = .noError,
        questions: [Question] = [],
        answers: [ResourceRecord] = [],
        authorities: [ResourceRecord] = [],
        additional: [ResourceRecord] = []
    ) {
        self.id = id
        self.type = type
        self.operationCode = operationCode
        self.authoritativeAnswer = authoritativeAnswer
        self.truncation = truncation
        self.recursionDesired = recursionDesired
        self.recursionAvailable = recursionAvailable
        self.returnCode = returnCode
        self.questions = questions
        self.answers = answers
        self.authorities = authorities
        self.additional = additional
    }

    /// Deserialize a DNS message from raw data.
    public init(deserialize data: Data) throws {
        var buffer = Array(data)
        var offset = 0

        // Read ID
        guard let (newOffset, rawId) = buffer.copyOut(as: UInt16.self, offset: offset) else {
            throw DNSBindError.unmarshalFailure(type: "Message", field: "id")
        }
        self.id = UInt16(bigEndian: rawId)
        offset = newOffset

        // Read flags
        guard let (newOffset, rawFlags) = buffer.copyOut(as: UInt16.self, offset: offset) else {
            throw DNSBindError.unmarshalFailure(type: "Message", field: "flags")
        }
        let flags = UInt16(bigEndian: rawFlags)
        offset = newOffset

        // Parse flags
        self.type = (flags & 0x8000) != 0 ? .response : .query
        guard let opCode = OperationCode(rawValue: UInt8((flags >> 11) & 0x0F)) else {
            throw DNSBindError.unsupportedValue(type: "Message", field: "opcode")
        }
        self.operationCode = opCode
        self.authoritativeAnswer = (flags & 0x0400) != 0
        self.truncation = (flags & 0x0200) != 0
        self.recursionDesired = (flags & 0x0100) != 0
        self.recursionAvailable = (flags & 0x0080) != 0
        guard let returnCode = ReturnCode(rawValue: UInt8(flags & 0x000F)) else {
            throw DNSBindError.unsupportedValue(type: "Message", field: "rcode")
        }
        self.returnCode = returnCode

        // Read counts
        guard let (newOffset, rawQdCount) = buffer.copyOut(as: UInt16.self, offset: offset) else {
            throw DNSBindError.unmarshalFailure(type: "Message", field: "qdcount")
        }
        let qdCount = UInt16(bigEndian: rawQdCount)
        offset = newOffset

        guard let (newOffset, rawAnCount) = buffer.copyOut(as: UInt16.self, offset: offset) else {
            throw DNSBindError.unmarshalFailure(type: "Message", field: "ancount")
        }
        let anCount = UInt16(bigEndian: rawAnCount)
        offset = newOffset

        guard let (newOffset, rawNsCount) = buffer.copyOut(as: UInt16.self, offset: offset) else {
            throw DNSBindError.unmarshalFailure(type: "Message", field: "nscount")
        }
        // nsCount not used for now, but we need to read past it
        _ = UInt16(bigEndian: rawNsCount)
        offset = newOffset

        guard let (newOffset, rawArCount) = buffer.copyOut(as: UInt16.self, offset: offset) else {
            throw DNSBindError.unmarshalFailure(type: "Message", field: "arcount")
        }
        // arCount not used for now, but we need to read past it
        _ = UInt16(bigEndian: rawArCount)
        offset = newOffset

        // Read questions
        self.questions = []
        for _ in 0..<qdCount {
            var question = Question(name: "")
            offset = try question.bindBuffer(&buffer, offset: offset, messageStart: 0)
            self.questions.append(question)
        }

        // Read answers (simplified - skip for now as we only need to parse queries)
        self.answers = []
        self.authorities = []
        self.additional = []

        // Skip answer parsing for now - we primarily receive queries and send responses
        _ = anCount
    }

    /// Serialize this message to raw data.
    public func serialize() throws -> Data {
        // Calculate exact buffer size.
        var bufferSize = Self.headerSize
        for question in questions {
            // name + type + class
            let n = question.name.hasSuffix(".") ? String(question.name.dropLast()) : question.name
            bufferSize += (try DNSName(labels: n.isEmpty ? [] : n.split(separator: ".", omittingEmptySubsequences: false).map(String.init))).size + 4
        }
        for answer in answers {
            // name + type + class + ttl + rdlen + rdata
            let n = answer.name.hasSuffix(".") ? String(answer.name.dropLast()) : answer.name
            let rdataSize = answer.type == .host ? 4 : 16
            bufferSize += (try DNSName(labels: n.isEmpty ? [] : n.split(separator: ".", omittingEmptySubsequences: false).map(String.init))).size + 10 + rdataSize
        }
        // Flagged #1 (1 of 2): HIGH: `serialize()` allocates a buffer too small to hold authority and additional records
        // `bufferSize` is computed by summing the header size plus the encoded sizes of `questions` and `answers`, but the method subsequently writes `authorities` and `additional` records into the same pre-allocated buffer. Because those sections are not counted, every `copyIn` call for an authority or additional record receives a buffer whose remaining capacity is zero, causing each guard to fire and throw `DNSBindError.marshalFailure`. Even if the writes somehow succeeded, the final `guard offset == bufferSize` check would throw `DNSBindError.unexpectedOffset` because `offset` would exceed `bufferSize`.
        for authority in authorities {
            let n = authority.name.hasSuffix(".") ? String(authority.name.dropLast()) : authority.name
            let rdataSize = authority.type == .host ? 4 : 16
            bufferSize += (try DNSName(labels: n.isEmpty ? [] : n.split(separator: ".", omittingEmptySubsequences: false).map(String.init))).size + 10 + rdataSize
        }
        // Flagged #1 (2 of 2)
        for record in additional {
            let n = record.name.hasSuffix(".") ? String(record.name.dropLast()) : record.name
            let rdataSize = record.type == .host ? 4 : 16
            bufferSize += (try DNSName(labels: n.isEmpty ? [] : n.split(separator: ".", omittingEmptySubsequences: false).map(String.init))).size + 10 + rdataSize
        }

        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var offset = 0

        // Write ID
        guard let newOffset = buffer.copyIn(as: UInt16.self, value: id.bigEndian, offset: offset) else {
            throw DNSBindError.marshalFailure(type: "Message", field: "id")
        }
        offset = newOffset

        // Build and write flags
        var flags: UInt16 = 0
        flags |= type == .response ? 0x8000 : 0
        flags |= UInt16(operationCode.rawValue) << 11
        flags |= authoritativeAnswer ? 0x0400 : 0
        flags |= truncation ? 0x0200 : 0
        flags |= recursionDesired ? 0x0100 : 0
        flags |= recursionAvailable ? 0x0080 : 0
        // Flagged #2: MEDIUM: `serialize()` writes RCODE without masking to 4 bits, corrupting adjacent flags
        // `flags |= UInt16(returnCode.rawValue)` ORs the full raw value of `returnCode` into the flags word without masking it to `0x000F`. The standard DNS header RCODE field occupies only bits 3–0 (RFC 1035). `ReturnCode` includes extended values above 15 (e.g. `badSignature = 16`, `badKey = 17`, up to `badCookie = 23`). For any such value, bits 4–7 of the flags word are set, overwriting the CD, AD, and Z fields. The deserializer correctly masks with `flags & 0x000F` before constructing a `ReturnCode`, so a serialize/deserialize round-trip for any `ReturnCode` with `rawValue > 15` silently produces `.noError` instead of the intended code.
        flags |= UInt16(returnCode.rawValue) & 0x000F

        guard let newOffset = buffer.copyIn(as: UInt16.self, value: flags.bigEndian, offset: offset) else {
            throw DNSBindError.marshalFailure(type: "Message", field: "flags")
        }
        offset = newOffset

        // Write counts
        guard questions.count <= UInt16.max else {
            throw DNSBindError.marshalFailure(type: "Message", field: "qdcount")
        }
        guard answers.count <= UInt16.max else {
            throw DNSBindError.marshalFailure(type: "Message", field: "ancount")
        }
        guard authorities.count <= UInt16.max else {
            throw DNSBindError.marshalFailure(type: "Message", field: "nscount")
        }
        guard additional.count <= UInt16.max else {
            throw DNSBindError.marshalFailure(type: "Message", field: "arcount")
        }

        guard let newOffset = buffer.copyIn(as: UInt16.self, value: UInt16(questions.count).bigEndian, offset: offset) else {
            throw DNSBindError.marshalFailure(type: "Message", field: "qdcount")
        }
        offset = newOffset

        guard let newOffset = buffer.copyIn(as: UInt16.self, value: UInt16(answers.count).bigEndian, offset: offset) else {
            throw DNSBindError.marshalFailure(type: "Message", field: "ancount")
        }
        offset = newOffset

        guard let newOffset = buffer.copyIn(as: UInt16.self, value: UInt16(authorities.count).bigEndian, offset: offset) else {
            throw DNSBindError.marshalFailure(type: "Message", field: "nscount")
        }
        offset = newOffset

        guard let newOffset = buffer.copyIn(as: UInt16.self, value: UInt16(additional.count).bigEndian, offset: offset) else {
            throw DNSBindError.marshalFailure(type: "Message", field: "arcount")
        }
        offset = newOffset

        // Write questions
        for question in questions {
            offset = try question.appendBuffer(&buffer, offset: offset)
        }

        // Write answers
        for answer in answers {
            offset = try answer.appendBuffer(&buffer, offset: offset)
        }

        // Write authorities
        for authority in authorities {
            offset = try authority.appendBuffer(&buffer, offset: offset)
        }

        // Write additional
        for record in additional {
            offset = try record.appendBuffer(&buffer, offset: offset)
        }

        guard offset == bufferSize else {
            throw DNSBindError.unexpectedOffset(type: "Message", expected: bufferSize, actual: offset)
        }
        return Data(buffer[0..<offset])
    }
}
