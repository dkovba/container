// fix-bugs: 2026-05-02 22:05 — 1 critical, 3 high, 0 medium, 0 low (4 total)
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
import ContainerPersistence
import ContainerPlugin
import ContainerXPC
import ContainerizationError
import Foundation
import SystemPackage
import TerminalProgress

extension Application {
    public struct SystemStart: AsyncLoggableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start `container` services"
        )

        @Option(
            name: .shortAndLong,
            help: "Path to the root directory for application data",
            transform: { URL(filePath: $0) })
        var appRoot = ApplicationRoot.defaultURL

        @Option(
            name: .long,
            help: "Path to the root directory for application executables and plugins",
            transform: { URL(filePath: $0) })
        var installRoot = InstallRoot.defaultURL

        @Option(
            name: .long,
            help: "Path to the root directory for log data, using macOS log facility if not set",
            transform: { FilePath($0) })
        var logRoot: FilePath? = nil

        @Flag(
            name: .long,
            inversion: .prefixedEnableDisable,
            help: "Specify whether the default kernel should be installed or not (default: prompt user)")
        var kernelInstall: Bool?

        @Option(
            help: "Number of seconds to wait for API service to become responsive",
            transform: {
                guard let timeoutSeconds = Double($0) else {
                    throw ValidationError("Invalid timeout value: \($0)")
                }
                return .seconds(timeoutSeconds)
            }
        )
        var timeout: Duration = XPCClient.xpcRegistrationTimeout

        @OptionGroup
        public var logOptions: Flags.Logging

        public init() {}

        public func run() async throws {
            // Without the true path to the binary in the plist, `container-apiserver` won't launch properly.
            // TODO: Can we use the plugin loader to bootstrap the API server?
            let executableUrl = CommandLine.executablePathUrl
                .deletingLastPathComponent()
                .appendingPathComponent("container-apiserver")
                .resolvingSymlinksInPath()

            var args = [executableUrl.absolutePath()]

            args.append("start")
            if logOptions.debug {
                args.append("--debug")
            }

            let apiServerDataUrl = appRoot.appending(path: "apiserver")
            // Flagged #1: CRITICAL: `try!` crashes the process on directory creation failure
            // `try! FileManager.default.createDirectory(at:withIntermediateDirectories:)` uses a force-try, which unconditionally terminates the process with a fatal error if the call throws — for example due to a permissions error or a read-only filesystem.
            try FileManager.default.createDirectory(at: apiServerDataUrl, withIntermediateDirectories: true)

            var env = PluginLoader.filterEnvironment()
            env[ApplicationRoot.environmentName] = appRoot.path(percentEncoded: false)
            env[InstallRoot.environmentName] = installRoot.path(percentEncoded: false)
            if let logRoot {
                env[LogRoot.environmentName] =
                    logRoot.isAbsolute
                    ? logRoot.string
                    : FilePath(FileManager.default.currentDirectoryPath).appending(logRoot.components).string
            }
            let plist = LaunchPlist(
                label: "com.apple.container.apiserver",
                arguments: args,
                environment: env,
                limitLoadToSessionType: [.Aqua, .Background, .System],
                runAtLoad: true,
                machServices: ["com.apple.container.apiserver"]
            )

            let plistURL = apiServerDataUrl.appending(path: "apiserver.plist")
            let data = try plist.encode()
            try data.write(to: plistURL)

            print("Registering API server with launchd...")
            try ServiceManager.register(plistPath: plistURL.path)

            // Now ping our friendly daemon. Fail if we don't get a response.
            do {
                print("Verifying apiserver is running...")
                _ = try await ClientHealthCheck.ping(timeout: timeout)
            } catch {
                throw ContainerizationError(
                    .internalError,
                    message: "failed to get a response from apiserver: \(error)"
                )
            }

            if await !initImageExists() {
                // Flagged #2: HIGH: `try?` silently discards errors from `installInitialFilesystem()`
                // `try? await installInitialFilesystem()` silently swallows any error the function throws. In particular, `installInitialFilesystem()` begins with `try ImagePull.parse()`, which can throw; that error is completely lost by `try?`, leaving the caller with no indication that the initial filesystem installation failed and no way to surface the failure to the user.
                try await installInitialFilesystem()
            }

            guard await !kernelExists() else {
                return
            }
            try await installDefaultKernel()
        }

        private func installInitialFilesystem() async throws {
            let dep = Dependencies.initFs
            // Flagged #4: HIGH: `ImagePull.parse()` parses the wrong process arguments in `installInitialFilesystem()`
            // `var pullCommand = try ImagePull.parse()` calls ArgumentParser's `parse()` with no arguments, which causes it to read from `CommandLine.arguments` — the arguments of the running `SystemStart` process (e.g. `["system", "start", ...]`). `ImagePull` expects a single positional `reference` argument followed by no other positional arguments, so feeding it SystemStart's arguments causes parsing to fail: the first token (`"system"`) is consumed as `reference`, and the next token (`"start"`) is an unexpected positional, producing a parse error. Even if parsing happened to succeed, the immediately following line `pullCommand.reference = dep.source` overwrites whatever `reference` was set to, making the `parse()` call pointless as a means of setting that value.
            var pullCommand = ImagePull(reference: dep.source)
            pullCommand.reference = dep.source
            print("Installing base container filesystem...")
            do {
                try await pullCommand.run()
            } catch {
                log.error("failed to install base container filesystem", metadata: ["error": "\(error)"])
                // Flagged #3: HIGH: `do-catch` in `installInitialFilesystem()` silently swallows `pullCommand.run()` errors
                // Inside `installInitialFilesystem()`, the `do-catch` block catches any error thrown by `try await pullCommand.run()`, logs it via `log.error(...)`, and then returns normally without re-throwing. The function is declared `throws`, so callers expect a thrown error to signal failure. Because the error is swallowed here, even a caller that uses `try await installInitialFilesystem()` receives a normal return and has no indication that the image pull failed.
                throw error
            }
        }

        private func installDefaultKernel() async throws {
            let kernelDependency = Dependencies.kernel
            let defaultKernelURL = kernelDependency.source
            let defaultKernelBinaryPath = DefaultsStore.get(key: .defaultKernelBinaryPath)

            var shouldInstallKernel = false
            if kernelInstall == nil {
                print("No default kernel configured.")
                print("Install the recommended default kernel from [\(kernelDependency.source)]? [Y/n]: ", terminator: "")
                guard let read = readLine(strippingNewline: true) else {
                    throw ContainerizationError(.internalError, message: "failed to read user input")
                }
                guard read.lowercased() == "y" || read.count == 0 else {
                    print("Please use the `container system kernel set --recommended` command to configure the default kernel")
                    return
                }
                shouldInstallKernel = true
            } else {
                shouldInstallKernel = kernelInstall ?? false
            }
            guard shouldInstallKernel else {
                return
            }
            print("Installing kernel...")
            try await KernelSet.downloadAndInstallWithProgressBar(tarRemoteURL: defaultKernelURL, kernelFilePath: defaultKernelBinaryPath, force: true)
        }

        private func initImageExists() async -> Bool {
            do {
                let img = try await ClientImage.get(reference: Dependencies.initFs.source)
                let _ = try await img.getSnapshot(platform: .current)
                return true
            } catch {
                return false
            }
        }

        private func kernelExists() async -> Bool {
            do {
                try await ClientKernel.getDefaultKernel(for: .current)
                return true
            } catch {
                return false
            }
        }
    }

    private enum Dependencies: String {
        case kernel
        case initFs

        var source: String {
            switch self {
            case .initFs:
                return DefaultsStore.get(key: .defaultInitImage)
            case .kernel:
                return DefaultsStore.get(key: .defaultKernelURL)
            }
        }
    }
}
