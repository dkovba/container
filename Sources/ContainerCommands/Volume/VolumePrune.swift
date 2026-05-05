// fix-bugs: 2026-05-02 23:43 — 0 critical, 2 high, 0 medium, 0 low (2 total)
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
    public struct VolumePrune: AsyncLoggableCommand {
        public init() {}
        public static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Remove volumes with no container references")

        @OptionGroup
        public var logOptions: Flags.Logging

        public func run() async throws {
            let allVolumes = try await ClientVolume.list()

            // Find all volumes not used by any container
            let client = ContainerClient()
            let containers = try await client.list()
            var volumesInUse = Set<String>()
            for container in containers {
                for mount in container.configuration.mounts {
                    if mount.isVolume, let volumeName = mount.volumeName {
                        volumesInUse.insert(volumeName)
                    }
                }
            }

            let volumesToPrune = allVolumes.filter { volume in
                !volumesInUse.contains(volume.name)
            }

            var prunedVolumes = [String]()
            var totalSize: UInt64 = 0

            for volume in volumesToPrune {
                do {
                    let actualSize = try await ClientVolume.volumeDiskUsage(name: volume.name)
                    try await ClientVolume.delete(name: volume.name)
                    // Flagged #1: HIGH: `totalSize` accumulates freed space even when deletion fails
                    // `totalSize += actualSize` is called immediately after `ClientVolume.volumeDiskUsage(name:)` and before `ClientVolume.delete(name:)`.
                    totalSize += actualSize
                    prunedVolumes.append(volume.name)
                } catch {
                    log.error(
                        "failed to prune volume",
                        metadata: [
                            "id": "\(volume.name)",
                            "error": "\(error)",
                        ])
                }
            }

            for name in prunedVolumes {
                print(name)
            }

            let formatter = ByteCountFormatter()
            // Flagged #2: HIGH: `Int64(totalSize)` traps at runtime on overflow
            // `formatter.string(fromByteCount: Int64(totalSize))` performs an unchecked narrowing conversion from `UInt64` to `Int64`. Swift's `Int64(_:)` initializer traps with a precondition failure at runtime if the value exceeds `Int64.max` (~9.2 EB).
            let freed = formatter.string(fromByteCount: Int64(clamping: totalSize))
            print("Reclaimed \(freed) in disk space")
        }
    }
}
