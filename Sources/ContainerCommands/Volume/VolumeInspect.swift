// fix-bugs: 2026-05-02 23:13 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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
import Foundation

extension Application.VolumeCommand {
    public struct VolumeInspect: AsyncLoggableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "inspect",
            abstract: "Display information about one or more volumes"
        )

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Volumes to inspect")
        var names: [String]

        public init() {}

        public func run() async throws {
            var volumes: [Volume] = []

            for name in names {
                let volume = try await ClientVolume.inspect(name)
                volumes.append(volume)
            }

            // Flagged #1: MEDIUM: `VolumeInspect.run()` encodes dates in ISO 8601 format, inconsistent with the rest of the volume subsystem
            // `JSONOptions` was constructed with `dateEncodingStrategy: .iso8601`, causing `volume inspect` to emit dates as ISO 8601 strings (e.g. `"2024-01-15T12:00:00Z"`) while every other volume command — including `volume list --format json` — emits dates as Unix timestamps via the default `.deferredToDate` strategy. The server also serializes `Volume` objects with a plain `JSONEncoder()` (default strategy), so the inspect output was the only path in the entire volume subsystem using a different date representation.
            try Output.emit(Output.renderJSON(volumes, options: .prettySorted))
        }
    }
}
