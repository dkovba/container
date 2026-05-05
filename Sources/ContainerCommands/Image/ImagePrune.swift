// fix-bugs: 2026-05-02 18:27 — 0 critical, 1 high, 1 medium, 0 low (2 total)
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
// Flagged #1 (1 of 2): HIGH: `prune` deletes infrastructure images
// `ClientImage.list()` returns all images including internal infrastructure images, but `ImagePrune` applied no filter to exclude them. Both `ImageDelete` and `ImageList` guard against this with `Utility.isInfraImage(name:)`, but `ImagePrune` did not, so every code path (dangling-only and `--all`) could select and delete infra images.
import Containerization
import ContainerizationOCI
import Foundation

extension Application {
    public struct ImagePrune: AsyncLoggableCommand {
        public init() {}
        public static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Remove all dangling images. If -a is specified, also remove all images not referenced by any container.")

        @OptionGroup
        public var logOptions: Flags.Logging

        @Flag(name: .shortAndLong, help: "Remove all unused images, not just dangling ones")
        var all: Bool = false

        public func run() async throws {
            // Flagged #1 (2 of 2)
            let allImages = try await ClientImage.list().filter { !Utility.isInfraImage(name: $0.reference) }

            let imagesToPrune: [ClientImage]
            if all {
                // Find all images not used by any container
                let client = ContainerClient()
                let containers = try await client.list()
                var imagesInUse = Set<String>()
                for container in containers {
                    imagesInUse.insert(container.configuration.image.reference)
                }
                imagesToPrune = allImages.filter { image in
                    !imagesInUse.contains(image.reference)
                }
            } else {
                // Find dangling images (images with no tag)
                imagesToPrune = allImages.filter { image in
                    !hasTag(image.reference)
                }
            }

            var prunedImages = [String]()

            for image in imagesToPrune {
                do {
                    try await ClientImage.delete(reference: image.reference, garbageCollect: false)
                    prunedImages.append(image.reference)
                } catch {
                    log.error(
                        "failed to prune image",
                        metadata: [
                            "ref": "\(image.reference)",
                            "error": "\(error)",
                        ])
                }
            }

            let (deletedDigests, size) = try await ClientImage.cleanUpOrphanedBlobs()

            // Flagged #2: MEDIUM: `prune` reports untagged output for images that failed deletion
            // The output loop iterated over `imagesToPrune` (all images selected for pruning) instead of `prunedImages` (images successfully deleted). Any image whose `ClientImage.delete` call threw an error was still printed as "untagged" even though it was never removed.
            for image in prunedImages {
                print("untagged \(image)")
            }
            for digest in deletedDigests {
                print("deleted \(digest)")
            }

            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let freed = formatter.string(fromByteCount: Int64(size))
            print("Reclaimed \(freed) in disk space")
        }

        private func hasTag(_ reference: String) -> Bool {
            do {
                let ref = try ContainerizationOCI.Reference.parse(reference)
                return ref.tag != nil && !ref.tag!.isEmpty
            } catch {
                return false
            }
        }
    }
}
