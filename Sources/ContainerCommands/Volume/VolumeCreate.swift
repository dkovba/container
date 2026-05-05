// fix-bugs: 2026-05-02 22:52 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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
import Foundation

extension Application.VolumeCommand {
    public struct VolumeCreate: AsyncLoggableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new volume"
        )

        @Option(name: .customLong("label"), help: "Set metadata for a volume")
        var labels: [String] = []

        @Option(name: .customLong("opt"), help: "Set driver specific options")
        var driverOpts: [String] = []

        // Flagged #1: MEDIUM: `--size` flag is inaccessible; only `-s` short form works
        // `@Option(name: .short, ...)` registers only the single-character flag `-s` for the `size` option. The long form `--size` is never registered, so any invocation using `--size <value>` fails with an unrecognized-option error. The `run()` method's own comment reads `// If --size is specified`, confirming that `--size` was the intended interface.
        @Option(name: .shortAndLong, help: "Size of the volume in bytes, with optional K, M, G, T, or P suffix")
        var size: String?

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Volume name")
        var name: String

        public init() {}

        public func run() async throws {
            var parsedDriverOpts = Utility.parseKeyValuePairs(driverOpts)
            let parsedLabels = Utility.parseKeyValuePairs(labels)

            // If --size is specified, add it to driver options
            if let size = size {
                parsedDriverOpts["size"] = size
            }

            let volume = try await ClientVolume.create(
                name: name,
                driver: "local",
                driverOpts: parsedDriverOpts,
                labels: parsedLabels
            )
            print(volume.name)
        }
    }
}
