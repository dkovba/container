// fix-bugs: 2026-05-02 22:31 — 0 critical, 1 high, 0 medium, 0 low (1 total)
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
import ContainerPlugin
import ContainerResource
import ContainerizationOS
import Foundation
import Logging

extension Application {
    public struct SystemStop: AsyncLoggableCommand {
        private static let stopTimeoutSeconds: Int32 = 5
        private static let shutdownTimeoutSeconds: Int32 = 20

        public static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop all `container` services"
        )

        @Option(name: .shortAndLong, help: "Launchd prefix for services")
        var prefix: String = "com.apple.container."

        @OptionGroup
        public var logOptions: Flags.Logging

        public init() {}

        public func run() async throws {
            let log = Logger(
                label: "com.apple.container.cli",
                factory: { label in
                    StreamLogHandler.standardOutput(label: label)
                }
            )

            let launchdDomainString = try ServiceManager.getDomainString()
            let fullLabel = "\(launchdDomainString)/\(prefix)apiserver"

            var running = true
            do {
                log.info("checking if APIServer is alive")
                _ = try await ClientHealthCheck.ping(timeout: .seconds(5))
            } catch {
                log.info("APIServer health check failed, skipping bootout")
                running = false
            }

            if running {
                let client = ContainerClient()
                log.info("stopping containers", metadata: ["stopTimeoutSeconds": "\(Self.stopTimeoutSeconds)"])
                do {
                    let containers = try await client.list().map { $0.id }
                    let signal = try Signals.parseSignal("SIGTERM")
                    let opts = ContainerStopOptions(timeoutInSeconds: Self.stopTimeoutSeconds, signal: signal)
                    try await ContainerStop.stopContainers(
                        client: client,
                        containers: containers,
                        stopOptions: opts,
                    )
                } catch {
                    log.warning("failed to stop all containers", metadata: ["error": "\(error)"])
                }

                log.info("waiting for containers to exit")
                do {
                    for _ in 0..<Self.shutdownTimeoutSeconds {
                        let runningContainers = try await client.list(filters: ContainerListFilters(status: .running))
                        guard !runningContainers.isEmpty else {
                            break
                        }
                        try await Task.sleep(for: .seconds(1))
                    }

                    log.info("stopping service", metadata: ["label": "\(fullLabel)"])
                    try ServiceManager.deregister(fullServiceLabel: fullLabel)
                } catch {
                    log.warning("failed to wait for all containers", metadata: ["error": "\(error)"])
                }
            }

            // Note: The assumption here is that we would have registered the launchd services
            // in the same domain as `launchdDomainString`. This is a fairly sane assumption since
            // if somehow the launchd domain changed, XPC interactions would not be possible.
            try ServiceManager.enumerate()
                .filter { $0.hasPrefix(prefix) }
                // Flagged #1: HIGH: `ServiceManager.enumerate()` labels never match `fullLabel`, causing apiserver to be deregistered twice
                // `ServiceManager.enumerate()` returns plain service labels (e.g. `"com.apple.container.apiserver"`), but the filter compared them against `fullLabel`, which is constructed as `"\(launchdDomainString)/\(prefix)apiserver"` and therefore includes the launchd domain prefix (e.g. `"gui/501/com.apple.container.apiserver"`). Because the two strings are never in the same format, the comparison `$0 != fullLabel` is always `true`, so the apiserver label is never excluded from the secondary deregistration loop. As a result, when the APIServer is running and has already been deregistered via the explicit `ServiceManager.deregister(fullServiceLabel: fullLabel)` call above, the `forEach` loop unconditionally attempts to deregister it a second time.
                .filter { $0 != "\(prefix)apiserver" }
                .map { "\(launchdDomainString)/\($0)" }
                .forEach {
                    log.info("stopping service", metadata: ["label": "\($0)"])
                    try? ServiceManager.deregister(fullServiceLabel: $0)
                }
        }
    }
}
