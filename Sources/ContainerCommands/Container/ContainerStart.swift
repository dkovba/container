// fix-bugs: 2026-05-02 15:48 — 0 critical, 0 high, 2 medium, 0 low (2 total)
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
import TerminalProgress

extension Application {
    public struct ContainerStart: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start a container")

        @Flag(name: .shortAndLong, help: "Attach stdout/stderr")
        var attach = false

        @Flag(name: .shortAndLong, help: "Attach stdin")
        var interactive = false

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Container ID")
        var containerId: String

        public func run() async throws {
            var exitCode: Int32 = 127

            let progressConfig = try ProgressConfig(
                description: "Starting container"
            )
            let progress = ProgressBar(config: progressConfig)
            defer {
                progress.finish()
            }
            progress.start()

            let detach = !self.attach && !self.interactive
            let client = ContainerClient()
            let container = try await client.get(id: containerId)

            // Bootstrap and process start are both idempotent and don't fail the second time
            // around, however not doing an rpc is always faster :). The other bit is we don't
            // support attach currently, so we can't do `start -a` a second time and have it succeed.
            if container.status == .running {
                if !detach {
                    throw ContainerizationError(
                        .invalidArgument,
                        message: "attach is currently unsupported on already running containers"
                    )
                }
                print(containerId)
                return
            }

            for mount in container.configuration.mounts where mount.isVirtiofs {
                if !FileManager.default.fileExists(atPath: mount.source) {
                    throw ContainerizationError(.invalidState, message: "mount source path '\(mount.source)' does not exist")
                }
            }

            do {
                let io = try ProcessIO.create(
                    tty: container.configuration.initProcess.terminal,
                    interactive: self.interactive,
                    detach: detach
                )
                defer {
                    try? io.close()
                }

                var env: [String: String] = [:]
                // Flagged #1: MEDIUM: `SSH_AUTH_SOCK` forwarded unconditionally, ignoring container's `ssh` configuration
                // `SSH_AUTH_SOCK` was read from the host process environment and unconditionally inserted into `dynamicEnv` whenever the variable existed, with no check against the container's stored `ssh` field. `ContainerConfiguration.ssh` records whether SSH agent forwarding was requested at container creation time, but `container start` ignored it entirely.
                if container.configuration.ssh {
                    if let sshAuthSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
                        env["SSH_AUTH_SOCK"] = sshAuthSock
                    }
                }

                let process = try await client.bootstrap(id: container.id, stdio: io.stdio, dynamicEnv: env)
                progress.finish()

                if detach {
                    try await process.start()
                    try io.closeAfterStart()
                    print(self.containerId)
                    return
                }

                // Flagged #2: MEDIUM: Signal threshold handler missing in non-TTY attach mode
                // `ContainerStart` omitted the `SignalThreshold` handler that both `ContainerRun` and `ContainerExec` install when attaching to a non-TTY process. Neither `--attach` nor `--interactive` mode set up a handler to force-exit after three SIGINT/SIGTERM signals; the `exitCode = try await io.handleProcess(process:log:)` call was reached with no signal escape hatch in place.
                if !container.configuration.initProcess.terminal {
                    var handler = SignalThreshold(threshold: 3, signals: [SIGINT, SIGTERM])
                    handler.start {
                        print("Received 3 SIGINT/SIGTERM's, forcefully exiting.")
                        Darwin.exit(1)
                    }
                }

                exitCode = try await io.handleProcess(process: process, log: log)
            } catch {
                try? await client.stop(id: container.id)

                if error is ContainerizationError {
                    throw error
                }
                throw ContainerizationError(.internalError, message: "failed to start container: \(error)")
            }
            throw ArgumentParser.ExitCode(exitCode)
        }
    }
}
