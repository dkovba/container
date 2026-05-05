// fix-bugs: 2026-05-02 15:05 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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
import ContainerizationError
import Foundation

extension Application {
    public struct ContainerPrune: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Remove all stopped containers"
        )

        @OptionGroup
        public var logOptions: Flags.Logging

        public func run() async throws {
            let client = ContainerClient()
            let containersToPrune = try await client.list().filter { $0.status == .stopped }

            var prunedContainerIds = [String]()
            var totalSize: UInt64 = 0

            for container in containersToPrune {
                do {
                    let actualSize = try await client.diskUsage(id: container.id)
                    try await client.delete(id: container.id)
                    // Flagged #1: MEDIUM: Freed-space total inflated when container deletion fails
                    // `totalSize += actualSize` was executed immediately after a successful `diskUsage` call but *before* `client.delete`. If `delete` threw an error, the container was not removed, yet its size had already been added to `totalSize`. The subsequent `print("Reclaimed \(freed) in disk space")` would therefore report a larger reclaimed value than actually freed.
                    totalSize += actualSize
                    prunedContainerIds.append(container.id)
                } catch {
                    log.error(
                        "failed to prune container",
                        metadata: [
                            "id": "\(container.id)",
                            "error": "\(error)",
                        ])
                }
            }

            let formatter = ByteCountFormatter()
            let freed = formatter.string(fromByteCount: Int64(totalSize))

            for name in prunedContainerIds {
                print(name)
            }
            print("Reclaimed \(freed) in disk space")
        }
    }
}
