// fix-bugs: 2026-05-02 06:32 — 0 critical, 1 high, 1 medium, 1 low (3 total)
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

extension Application {
    public struct ContainerExec: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "exec",
            abstract: "Run a new command in a running container")

        @OptionGroup(title: "Process options")
        var processFlags: Flags.Process

        @OptionGroup
        public var logOptions: Flags.Logging

        @Flag(name: .shortAndLong, help: "Run the process and detach from it")
        var detach = false

        @Argument(help: "Container ID")
        var containerId: String

        @Argument(parsing: .captureForPassthrough, help: "New process arguments")
        var arguments: [String]

        public func run() async throws {
            var exitCode: Int32 = 127
            let client = ContainerClient()
            let container = try await client.get(id: containerId)
            try ensureRunning(container: container)

            let stdin = self.processFlags.interactive
            let tty = self.processFlags.tty

            var config = container.configuration.initProcess
            // Flagged #1: HIGH: Force-unwrap of `arguments.first` crashes when no command is supplied
            // `config.executable = arguments.first!` unconditionally force-unwrapped the first element of `arguments`, which is declared as `@Argument(parsing: .captureForPassthrough)` and resolves to a `[String]` that can be empty when the user omits the command after the container ID. Swift force-unwrapping a `nil` Optional terminates the process with a fatal error rather than producing a recoverable error message.
            guard let executable = arguments.first else {
                throw ValidationError("No command specified")
            }
            config.executable = executable
            config.arguments = [String](self.arguments.dropFirst())
            config.terminal = tty
            // Flagged #2: MEDIUM: `--env` / `--env-file` values appended without deduplication against inherited environment
            // `config.environment` was initialised from `container.configuration.initProcess`, which already contains the container's full environment. The code then called `config.environment.append(contentsOf: try Parser.allEnv(imageEnvs: [], ...))`. Passing `imageEnvs: []` excluded the inherited environment from `Parser.allEnv`'s deduplication pass, so any key present in both the container's environment and the user-supplied `--env` flags ended up duplicated in the final array. Behaviour with duplicate environment keys is undefined in POSIX `execve`.
            config.environment = try Parser.allEnv(
                imageEnvs: config.environment,
                envFiles: self.processFlags.envFile,
                envs: self.processFlags.env
            )

            if let cwd = self.processFlags.cwd {
                config.workingDirectory = cwd
            }

            let defaultUser = config.user
            let (user, additionalGroups) = Parser.user(
                user: processFlags.user, uid: processFlags.uid,
                gid: processFlags.gid, defaultUser: defaultUser)
            config.user = user
            config.supplementalGroups.append(contentsOf: additionalGroups)
            // Flagged #3: LOW: `--ulimit` flags silently ignored in `exec`
            // `Flags.Process` exposes a `ulimits: [String]` option and `Parser.rlimits` is available to parse it, but `ContainerExec` never read `processFlags.ulimits` or updated `config.rlimits`. Any `--ulimit` argument passed to `container exec` was accepted by the argument parser and then discarded.
            config.rlimits.append(contentsOf: try Parser.rlimits(processFlags.ulimits))

            do {
                let io = try ProcessIO.create(tty: tty, interactive: stdin, detach: self.detach)
                defer {
                    try? io.close()
                }

                let process = try await client.createProcess(
                    containerId: container.id,
                    processId: UUID().uuidString.lowercased(),
                    configuration: config,
                    stdio: io.stdio
                )

                if self.detach {
                    try await process.start()
                    try io.closeAfterStart()
                    print(containerId)
                    return
                }

                if !self.processFlags.tty {
                    var handler = SignalThreshold(threshold: 3, signals: [SIGINT, SIGTERM])
                    handler.start {
                        print("Received 3 SIGINT/SIGTERM's, forcefully exiting.")
                        Darwin.exit(1)
                    }
                }

                exitCode = try await io.handleProcess(process: process, log: log)
            } catch {
                if error is ContainerizationError {
                    throw error
                }
                throw ContainerizationError(.internalError, message: "failed to exec process \(error)")
            }
            throw ArgumentParser.ExitCode(exitCode)
        }
    }
}
