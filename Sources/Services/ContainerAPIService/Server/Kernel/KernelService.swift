// fix-bugs: 2026-04-28 15:24 — 0 critical, 1 high, 1 medium, 1 low (3 total)
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

import ContainerAPIClient
import Containerization
import ContainerizationArchive
import ContainerizationError
import ContainerizationExtras
import Foundation
import Logging
import TerminalProgress

public actor KernelService {
    private static let defaultKernelNamePrefix: String = "default.kernel-"

    private let log: Logger
    private let kernelDirectory: URL

    public init(log: Logger, appRoot: URL) throws {
        self.log = log
        self.kernelDirectory = appRoot.appending(path: "kernels")
        try FileManager.default.createDirectory(at: self.kernelDirectory, withIntermediateDirectories: true)
    }

    /// Copies a kernel binary from a local path on disk into the managed kernels directory
    /// as the default kernel for the provided platform.
    public func installKernel(kernelFile url: URL, platform: SystemPlatform = .linuxArm, force: Bool) throws {
        log.debug(
            "KernelService: enter",
            metadata: [
                "func": "\(#function)",
                "kernelFile": "\(url)",
                "platform": "\(String(describing: platform))",
            ]
        )
        defer {
            log.debug(
                "KernelService: exit",
                metadata: [
                    "func": "\(#function)",
                    "kernelFile": "\(url)",
                    "platform": "\(String(describing: platform))",
                ]
            )
        }

        let kFile = url.resolvingSymlinksInPath()
        let destPath = self.kernelDirectory.appendingPathComponent(kFile.lastPathComponent)
        if force {
            do {
                try FileManager.default.removeItem(at: destPath)
            } catch let error as NSError {
                guard error.code == NSFileNoSuchFileError else {
                    throw error
                }
            }
        }
        try FileManager.default.copyItem(at: kFile, to: destPath)
        do {
            // Flagged #3: LOW: `installKernel` does not clean up copied file on task cancellation
            // `try Task.checkCancellation()` sits between `copyItem(at:to:)` and the `do-catch` block whose `catch` clause removes `destPath`. If the task is cancelled after the copy succeeds, the `CancellationError` is thrown before entering the `do` block, so the `catch` cleanup never runs and the orphaned file at `destPath` is leaked on disk.
            try Task.checkCancellation()
            try self.setDefaultKernel(name: kFile.lastPathComponent, platform: platform)
        } catch {
            try? FileManager.default.removeItem(at: destPath)
            throw error
        }
    }

    /// Copies a kernel binary from inside of tar file into the managed kernels directory
    /// as the default kernel for the provided platform.
    /// The parameter `tar` maybe a location to a local file on disk, or a remote URL.
    public func installKernelFrom(tar: URL, kernelFilePath: String, platform: SystemPlatform, progressUpdate: ProgressUpdateHandler?, force: Bool) async throws {
        log.debug(
            "KernelService: enter",
            metadata: [
                "func": "\(#function)",
                "tar": "\(tar)",
                "kernelFilePath": "\(kernelFilePath)",
                "platform": "\(String(describing: platform))",
            ]
        )
        defer {
            log.debug(
                "KernelService: exit",
                metadata: [
                    "func": "\(#function)",
                    "tar": "\(tar)",
                    "kernelFilePath": "\(kernelFilePath)",
                    "platform": "\(String(describing: platform))",
                ]
            )
        }

        let tempDir = FileManager.default.uniqueTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        await progressUpdate?([
            .setDescription("Downloading kernel")
        ])
        let taskManager = ProgressTaskCoordinator()
        let downloadTask = await taskManager.startTask()
        var tarFile = tar
        // Flagged #2 (1 of 2): MEDIUM: `installKernelFrom` uses `absoluteString` instead of `path` for local-file detection
        // `FileManager.default.fileExists(atPath: tar.absoluteString)` passes a URL's `absoluteString` (which includes the `file://` scheme prefix, e.g. `file:///path/to/file.tar`) to `fileExists(atPath:)`, which expects a plain filesystem path. The check always returns `false` for local file URLs, so (1) a local tar file is unnecessarily re-downloaded from itself on line 117, and (2) the cleanup guard on line 134 incorrectly attempts to delete the original local tar file.
        if !FileManager.default.fileExists(atPath: tar.path) {
            self.log.debug("KernelService: start download", metadata: ["tar": "\(tar)"])
            tarFile = tempDir.appendingPathComponent(tar.lastPathComponent)
            var downloadProgressUpdate: ProgressUpdateHandler?
            if let progressUpdate {
                downloadProgressUpdate = ProgressTaskCoordinator.handler(for: downloadTask, from: progressUpdate)
            }
            try await ContainerAPIClient.FileDownloader.downloadFile(url: tar, to: tarFile, progressUpdate: downloadProgressUpdate)
        }
        await taskManager.finish()

        await progressUpdate?([
            .setDescription("Unpacking kernel")
        ])
        let kernelFile = try self.extractFile(tarFile: tarFile, at: kernelFilePath, to: tempDir)
        try self.installKernel(kernelFile: kernelFile, platform: platform, force: force)

        // Flagged #2 (2 of 2)
        if !FileManager.default.fileExists(atPath: tar.path) {
            try FileManager.default.removeItem(at: tarFile)
        }
    }

    private func setDefaultKernel(name: String, platform: SystemPlatform) throws {
        log.debug(
            "KernelService: enter",
            metadata: [
                "func": "\(#function)",
                "name": "\(name)",
                "platform": "\(String(describing: platform))",
            ]
        )
        defer {
            log.debug(
                "KernelService: exit",
                metadata: [
                    "func": "\(#function)",
                    "name": "\(name)",
                    "platform": "\(String(describing: platform))",
                ]
            )
        }

        let kernelPath = self.kernelDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: kernelPath.path) else {
            throw ContainerizationError(.notFound, message: "kernel not found at \(kernelPath)")
        }
        let name = "\(Self.defaultKernelNamePrefix)\(platform.architecture)"
        let defaultKernelPath = self.kernelDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: defaultKernelPath)
        try FileManager.default.createSymbolicLink(at: defaultKernelPath, withDestinationURL: kernelPath)
    }

    public func getDefaultKernel(platform: SystemPlatform = .linuxArm) async throws -> Kernel {
        log.debug(
            "KernelService: enter",
            metadata: [
                "func": "\(#function)",
                "platform": "\(String(describing: platform))",
            ]
        )
        defer {
            log.debug(
                "KernelService: exit",
                metadata: [
                    "func": "\(#function)",
                    "platform": "\(String(describing: platform))",
                ]
            )
        }

        let name = "\(Self.defaultKernelNamePrefix)\(platform.architecture)"
        let defaultKernelPath = self.kernelDirectory.appendingPathComponent(name).resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: defaultKernelPath.path) else {
            throw ContainerizationError(.notFound, message: "default kernel not found at \(defaultKernelPath)")
        }
        return Kernel(path: defaultKernelPath, platform: platform)
    }

    private func extractFile(tarFile: URL, at: String, to directory: URL) throws -> URL {
        var target = at
        var archiveReader = try ArchiveReader(file: tarFile)
        var (entry, data) = try archiveReader.extractFile(path: target)

        // if the target file is a symlink, get the data for the actual file
        if entry.fileType == .symbolicLink, let symlinkRelative = entry.symlinkTarget {
            // the previous extractFile changes the underlying file pointer, so we need to reopen the file
            // to ensure we traverse all the files in the archive
            archiveReader = try ArchiveReader(file: tarFile)
            // Flagged #1 (1 of 2): HIGH: `extractFile` symlink resolution turns relative archive paths into absolute filesystem paths
            // `URL(filePath: target)` resolves a relative tar-internal path (e.g. `boot/vmlinux`) against the current working directory, producing an absolute URL like `file:///cwd/boot/vmlinux`. After `deletingLastPathComponent()`, `appending(path:)`, and `.standardized`, the resulting `.relativePath` (identical to `.path` when no base URL exists) is an absolute filesystem path such as `/cwd/kernel/vmlinux-6.1`. The subsequent `archiveReader.extractFile(path:)` call fails to match any archive entry because tar entries use relative paths.
            let isRelative = !target.hasPrefix("/")
            let absTarget = isRelative ? "/" + target : target
            let symlinkTarget = URL(filePath: absTarget).deletingLastPathComponent().appending(path: symlinkRelative)

            // standardize so that we remove any and all ../ and ./ in the path since symlink targets
            // are relative paths to the target file from the symlink's parent dir itself
            // Flagged #1 (2 of 2)
            target = symlinkTarget.standardized.path
            if isRelative {
                target = String(target.dropFirst())
            }
            let (_, targetData) = try archiveReader.extractFile(path: target)
            data = targetData
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let fileName = URL(filePath: target).lastPathComponent
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}
