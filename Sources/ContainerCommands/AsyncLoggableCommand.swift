// fix-bugs: 2026-05-05 13:06 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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

import ArgumentParser
import ContainerAPIClient
import ContainerLog
// Flagged #1 (1 of 2): MEDIUM: `log` property ignores `CONTAINER_DEBUG` environment variable
// The `log` computed property only checks `logOptions.debug` to decide the log level, ignoring the `CONTAINER_DEBUG` environment variable.
import Foundation
import Logging

public protocol AsyncLoggableCommand: AsyncParsableCommand {
    var logOptions: Flags.Logging { get }
}

extension AsyncLoggableCommand {
    /// A shared logger instance configured based on the command's options
    public var log: Logger {
        var logger = Logger(label: "container", factory: { _ in StderrLogHandler() })

        // Flagged #1 (2 of 2)
        let debugEnvVar = ProcessInfo.processInfo.environment["CONTAINER_DEBUG"]
        logger.logLevel = (logOptions.debug || debugEnvVar != nil) ? .debug : .info

        return logger
    }
}
