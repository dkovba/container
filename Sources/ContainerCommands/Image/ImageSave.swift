// fix-bugs: 2026-05-02 19:18 — 0 critical, 1 high, 2 medium, 0 low (3 total)
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
import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import TerminalProgress

extension Application {
    public struct ImageSave: AsyncLoggableCommand {
        public init() {}
        public static let configuration = CommandConfiguration(
            commandName: "save",
            abstract: "Save one or more images as an OCI compatible tar archive"
        )

        @Option(
            name: .shortAndLong,
            help: "Architecture for the saved image"
        )
        var arch: String?

        @Option(
            help: "OS for the saved image"
        )
        var os: String?

        @Option(
            name: .shortAndLong, help: "Pathname for the saved image", completion: .file(),
            transform: { str in
                URL(fileURLWithPath: str, relativeTo: .currentDirectory()).absoluteURL.path(percentEncoded: false)
            })
        var output: String?

        @Option(
            help: "Platform for the saved image (format: os/arch[/variant], takes precedence over --os and --arch) [environment: CONTAINER_DEFAULT_PLATFORM]"
        )
        var platform: String?

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument var references: [String]

        public func run() async throws {
            let p = try DefaultPlatform.resolve(platform: platform, os: os, arch: arch, log: log)

            let progressConfig = try ProgressConfig(
                description: "Saving image(s)"
            )
            let progress = ProgressBar(config: progressConfig)
            defer {
                progress.finish()
            }
            progress.start()

            var images: [ImageDescription] = []
            for reference in references {
                do {
                    images.append(try await ClientImage.get(reference: reference).description)
                } catch {
                    // Flagged #2: MEDIUM: Image-fetch error diagnostic written to stdout instead of stderr
                    // When `ClientImage.get` fails for a reference, the error message is emitted via `print(...)`, which writes to stdout. In the stdout-streaming path (`output == nil`), stdout is expected to carry a binary tar archive; any text written there before the tar data corrupts the stream for downstream consumers.
                    FileHandle.standardError.write(
                        Data("failed to get image for reference \(reference): \(error)\n".utf8))
                }
            }

            guard images.count == references.count else {
                throw ContainerizationError(.invalidArgument, message: "failed to save image(s)")
            }

            if let p {
                for (reference, description) in zip(references, images) {
                    let image = ClientImage(description: description)
                    do {
                        _ = try await image.manifest(for: p)
                    } catch {
                        var available: [String] = []
                        if let index = try? await image.index() {
                            available = index.manifests
                                .compactMap { $0.platform?.description }
                                .filter { $0 != "unknown/unknown" }
                        }
                        let availableStr = available.isEmpty ? "none" : available.joined(separator: ", ")
                        throw ContainerizationError(
                            .invalidArgument,
                            message: "image \(reference) has no content for platform \(p.description); available platforms: \(availableStr)"
                        )
                    }
                }
            }

            // Write to stdout; otherwise write to the output file
            if output == nil {
                let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).tar")
                defer {
                    try? FileManager.default.removeItem(at: tempFile)
                }

                // Flagged #3 (1 of 2): MEDIUM: Percent-encoded temp-file path causes file-not-found when streaming to stdout
                // `URL.path()` is called with its default argument `percentEncoded: true`, which returns a percent-encoded string (e.g. `/private/var/folders/my%20dir/T/uuid.tar` when the temp directory path contains a space). That encoded string is passed verbatim to `FileManager.createFile(atPath:)` and to `ClientImage.save(out:)`, so the file is created and written at the literal percent-encoded path. Immediately afterward, `FileHandle(forReadingFrom: tempFile)` uses the URL directly; Foundation decodes the URL to the actual POSIX path. The two paths differ, so the `FileHandle` open fails with file-not-found and the save operation aborts with an internal error.
                guard FileManager.default.createFile(atPath: tempFile.path(percentEncoded: false), contents: nil) else {
                    throw ContainerizationError(.internalError, message: "unable to create temporary file")
                }

                // Flagged #3 (2 of 2)
                try await ClientImage.save(references: references, out: tempFile.path(percentEncoded: false), platform: p)

                guard let fileHandle = try? FileHandle(forReadingFrom: tempFile) else {
                    throw ContainerizationError(.internalError, message: "unable to open temporary file for reading")
                }

                let bufferSize = 4096
                while true {
                    let chunk = fileHandle.readData(ofLength: bufferSize)
                    if chunk.isEmpty { break }
                    FileHandle.standardOutput.write(chunk)
                }
                try fileHandle.close()
            } else {
                try await ClientImage.save(references: references, out: output!, platform: p)
            }

            progress.finish()
            // Flagged #1: HIGH: `print(reference)` corrupts tar archive written to stdout
            // After saving the archive, reference name strings are unconditionally printed to stdout via `print(reference)`. When `output == nil` (the user has not specified `--output` and the tar archive is being streamed to stdout), these strings are appended to the binary tar stream, producing malformed output that no tar reader can parse.
            if output != nil {
                for reference in references {
                    print(reference)
                }
            }
        }
    }
}
