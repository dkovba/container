// fix-bugs: 2026-05-05 14:44 — 0 critical, 0 high, 0 medium, 1 low (1 total)
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

import Foundation
import Logging
import os

import struct Logging.Logger

public struct OSLogHandler: LogHandler {
    private let logger: os.Logger

    public var logLevel: Logger.Level = .info
    private var formattedMetadata: String?

    public var metadata = Logger.Metadata() {
        didSet {
            self.formattedMetadata = self.formatMetadata(self.metadata)
        }
    }

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    public init(label: String, category: String) {
        self.logger = os.Logger(subsystem: label, category: category)
    }
}

extension OSLogHandler {
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        var formattedMetadata = self.formattedMetadata
        if let metadataOverride = metadata, !metadataOverride.isEmpty {
            formattedMetadata = self.formatMetadata(
                self.metadata.merging(metadataOverride) {
                    $1
                }
            )
        }

        var finalMessage = message.description
        if let formattedMetadata {
            finalMessage += " " + formattedMetadata
        }

        self.logger.log(
            level: level.toOSLogLevel(),
            "\(finalMessage, privacy: .public)"
        )
    }

    private func formatMetadata(_ metadata: Logger.Metadata) -> String? {
        if metadata.isEmpty {
            return nil
        }
        return metadata.map {
            "[\($0)=\($1)]"
        }.joined(separator: " ")
    }
}

extension Logger.Level {
    func toOSLogLevel() -> OSLogType {
        switch self {
        case .debug, .trace:
            return .debug
        case .info:
            return .info
        // Flagged #1 (1 of 2): LOW: `.warning` log level mapped to wrong OSLogType severity
        // `.warning` was grouped with `.notice` in the `toOSLogLevel()` switch, causing both to return `.default`. This breaks the severity ordering since warning is more severe than notice but was emitted at the same OS log level, making it impossible to filter warnings from notices using OS log facilities.
        case .notice:
            return .default
        // Flagged #1 (2 of 2)
        case .warning, .error:
            return .error
        case .critical:
            return .fault
        }
    }
}
