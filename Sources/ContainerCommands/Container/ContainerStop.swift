// fix-bugs: 2026-05-02 17:07 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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
import ContainerResource
import ContainerizationError
import ContainerizationOS
import Foundation
import Logging

extension Application {
    public struct ContainerStop: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop one or more running containers")

        @Flag(name: .shortAndLong, help: "Stop all running containers")
        var all = false

        @Option(name: .shortAndLong, help: "Signal to send to the containers")
        var signal: String = "SIGTERM"

        @Option(name: .shortAndLong, help: "Seconds to wait before killing the containers")
        var time: Int32 = 5

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Container IDs")
        var containerIds: [String] = []

        public func validate() throws {
            if containerIds.count == 0 && !all {
                throw ContainerizationError(.invalidArgument, message: "no containers specified and --all not supplied")
            }
            if containerIds.count > 0 && all {
                throw ContainerizationError(
                    .invalidArgument, message: "explicitly supplied container IDs conflict with the --all flag")
            }
        }

        public mutating func run() async throws {
            let client = ContainerClient()

            let containers: [String]
            if self.all {
                // Flagged #1: MEDIUM: `--all` flag stops non-running containers instead of only running ones
                // When `--all` is passed, `client.list()` returns every container regardless of state. The resulting IDs are then passed to `stopContainers`, so the command attempts to stop containers that are already stopped or in other non-running states. `ContainerKill --all` correctly filters to running containers via `ContainerListFilters(status: .running)`, but `ContainerStop --all` did not apply the same filter.
                containers = try await client.list(filters: ContainerListFilters(status: .running)).map { $0.id }
            } else {
                containers = containerIds
            }

            let opts = ContainerStopOptions(
                timeoutInSeconds: self.time,
                signal: try Signals.parseSignal(self.signal)
            )
            try await Self.stopContainers(
                client: client,
                containers: containers,
                stopOptions: opts
            )
        }

        static func stopContainers(client: ContainerClient, containers: [String], stopOptions: ContainerStopOptions) async throws {
            var errors: [any Error] = []
            await withTaskGroup(of: (any Error)?.self) { group in
                for container in containers {
                    group.addTask {
                        do {
                            try await client.stop(id: container, opts: stopOptions)
                            print(container)
                            return nil
                        } catch {
                            return error
                        }
                    }
                }

                for await error in group {
                    if let error {
                        errors.append(error)
                    }
                }
            }

            if !errors.isEmpty {
                throw AggregateError(errors)
            }
        }
    }
}
