// fix-bugs: 2026-04-28 15:04 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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
import ContainerXPC
import Containerization
import ContainerizationError
import Foundation
import Logging

public struct KernelHarness: Sendable {
    private let log: Logging.Logger
    private let service: KernelService

    public init(service: KernelService, log: Logging.Logger) {
        self.log = log
        self.service = service
    }

    @Sendable
    public func install(_ message: XPCMessage) async throws -> XPCMessage {
        let kernelFilePath = try message.kernelFilePath()
        let platform = try message.platform()
        let force = try message.kernelForce()

        guard let kernelTarUrl = try message.kernelTarURL() else {
            // We have been given a path to a kernel binary on disk
            // Flagged #1: MEDIUM: `install()` constructs file URL with `URL(string:)` instead of `URL(fileURLWithPath:)`
            // `URL(string: kernelFilePath)` is used to create a URL from a filesystem path. `URL(string:)` expects a full URL with a scheme (e.g. `http://`, `file://`) and will return `nil` for typical filesystem paths containing spaces or other characters that are invalid in unescaped URL strings. This causes valid kernel file paths to be rejected with an "invalid kernel file path" error instead of being installed.
            let kernelFile = URL(fileURLWithPath: kernelFilePath)
            try await self.service.installKernel(kernelFile: kernelFile, platform: platform, force: force)
            return message.reply()
        }

        let progressUpdateService = ProgressUpdateService(message: message)
        try await self.service.installKernelFrom(
            tar: kernelTarUrl, kernelFilePath: kernelFilePath, platform: platform, progressUpdate: progressUpdateService?.handler, force: force)
        return message.reply()
    }

    @Sendable
    public func getDefaultKernel(_ message: XPCMessage) async throws -> XPCMessage {
        guard let platformData = message.dataNoCopy(key: .systemPlatform) else {
            throw ContainerizationError(.invalidArgument, message: "missing SystemPlatform")
        }
        let platform = try JSONDecoder().decode(SystemPlatform.self, from: platformData)
        let kernel = try await self.service.getDefaultKernel(platform: platform)
        let reply = message.reply()
        let data = try JSONEncoder().encode(kernel)
        reply.set(key: .kernel, value: data)
        return reply
    }
}

extension XPCMessage {
    fileprivate func platform() throws -> SystemPlatform {
        guard let platformData = self.dataNoCopy(key: .systemPlatform) else {
            throw ContainerizationError(.invalidArgument, message: "missing SystemPlatform in XPC Message")
        }
        let platform = try JSONDecoder().decode(SystemPlatform.self, from: platformData)
        return platform
    }

    fileprivate func kernelFilePath() throws -> String {
        guard let kernelFilePath = self.string(key: .kernelFilePath) else {
            throw ContainerizationError(.invalidArgument, message: "missing kernel file path in XPC Message")
        }
        return kernelFilePath
    }

    fileprivate func kernelTarURL() throws -> URL? {
        guard let kernelTarURLString = self.string(key: .kernelTarURL) else {
            return nil
        }
        guard let k = URL(string: kernelTarURLString) else {
            throw ContainerizationError(.invalidArgument, message: "cannot parse URL from \(kernelTarURLString)")
        }
        return k
    }

    fileprivate func kernelForce() throws -> Bool {
        self.bool(key: .kernelForce)
    }
}
