// fix-bugs: 2026-05-02 06:49 — 0 critical, 0 high, 0 medium, 1 low (1 total)
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
import TerminalProgress

extension Application {
    public struct ContainerExport: AsyncLoggableCommand {
        public init() {}
        public static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "export",
                abstract: "Export a container's filesystem as a tar archive",
            )
        }

        @OptionGroup
        public var logOptions: Flags.Logging

        @Option(
            name: .shortAndLong, help: "Pathname for the saved container filesystem (defaults to stdout)", completion: .file(),
            transform: { str in
                URL(fileURLWithPath: str, relativeTo: .currentDirectory()).absoluteURL.path(percentEncoded: false)
            })
        var output: String?

        @Argument(help: "container ID")
        var id: String

        public func run() async throws {
            let client = ContainerClient()
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            let archive = tempDir.appendingPathComponent("archive.tar")
            try await client.export(id: id, archive: archive)

            if output == nil {
                guard let fileHandle = try? FileHandle(forReadingFrom: archive) else {
                    throw ContainerizationError(.internalError, message: "unable to open archive for reading")
                }
                let bufferSize = 4096
                while true {
                    let chunk = fileHandle.readData(ofLength: bufferSize)
                    if chunk.isEmpty { break }
                    // Flagged #1: LOW: `FileHandle.standardOutput.write(_:)` uses the deprecated non-throwing API, crashing on write errors
                    // `FileHandle.standardOutput.write(chunk)` calls the deprecated ObjC-bridged `write(_:)` method, which does not throw on failure. When the write fails — for example when stdout is a broken pipe because the caller piped the output to a command that exited early (e.g. `container export myid | head`) — this API raises an unhandled ObjC exception, which Swift converts to a fatal `NSException` that terminates the process unconditionally. The throwing replacement `write(contentsOf:)` propagates the error as a normal Swift error, allowing the runtime to unwind the stack and report the failure cleanly.
                    try FileHandle.standardOutput.write(contentsOf: chunk)
                }
                try fileHandle.close()
            } else {
                try FileManager.default.moveItem(at: archive, to: URL(fileURLWithPath: output!))
            }
        }
    }
}
