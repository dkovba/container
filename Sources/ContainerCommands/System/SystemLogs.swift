// fix-bugs: 2026-05-02 21:31 — 0 critical, 0 high, 0 medium, 2 low (2 total)
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

import ArgumentParser
import ContainerAPIClient
import ContainerizationError
import ContainerizationOS
import Foundation
import OSLog

extension Application {
    public struct SystemLogs: AsyncLoggableCommand {
        public static let subsystem = "com.apple.container"

        public static let configuration = CommandConfiguration(
            commandName: "logs",
            abstract: "Fetch system logs for `container` services"
        )

        @Flag(name: .shortAndLong, help: "Follow log output")
        var follow: Bool = false

        @Option(
            name: .long,
            help: "Fetch logs starting from the specified time period (minus the current time); supported formats: m, h, d"
        )
        var last: String = "5m"

        @OptionGroup
        public var logOptions: Flags.Logging

        public init() {}

        public func run() async throws {
            let process = Process()
            let sigHandler = AsyncSignalHandler.create(notify: [SIGINT, SIGTERM])

            Task {
                for await _ in sigHandler.signals {
                    process.terminate()
                    Darwin.exit(0)
                }
            }

            do {
                var args = ["log"]
                args.append(self.follow ? "stream" : "show")
                args.append(contentsOf: ["--info", logOptions.debug ? "--debug" : nil].compactMap { $0 })
                if !self.follow {
                    args.append(contentsOf: ["--last", last])
                }
                args.append(contentsOf: ["--predicate", "subsystem = 'com.apple.container'"])

                process.launchPath = "/usr/bin/env"
                process.arguments = args

                process.standardOutput = FileHandle.standardOutput
                process.standardError = FileHandle.standardError

                try process.run()
                process.waitUntilExit()
            } catch {
                // Flagged #1: LOW: Wrong error code wraps process launch failure as a user argument error
                // `ContainerizationError(.invalidArgument, ...)` is thrown when `process.run()` fails to launch `/usr/bin/env log`. `.invalidArgument` signals that the caller supplied a bad argument, but a failure to exec the `log` binary is a system-level condition entirely outside the caller's control.
                throw ContainerizationError(
                    .internalError,
                    // Flagged #2: LOW: Garbled error message omits the verb "fetch"
                    // The error message reads `"failed to system logs: \(error)"`, which is grammatically broken — the verb is missing, making the message unparseable to users and log consumers.
                    message: "failed to fetch system logs: \(error)"
                )
            }
            throw ArgumentParser.ExitCode(process.terminationStatus)
        }
    }
}
