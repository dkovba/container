// fix-bugs: 2026-05-02 05:39 — 0 critical, 1 high, 1 medium, 1 low (3 total)
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
import ContainerBuild
import ContainerPersistence
import ContainerResource
import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOCI
import Foundation
import Logging
import TerminalProgress

extension Application {
    public struct BuilderStart: AsyncLoggableCommand {
        static let defaultCPUs = 2
        static let defaultMemoryInBytes: UInt64 = 2048.mib()

        public static var configuration: CommandConfiguration {
            var config = CommandConfiguration()
            config.commandName = "start"
            config.abstract = "Start the builder container"
            return config
        }

        @Option(name: .shortAndLong, help: "Number of CPUs to allocate to the builder container")
        var cpus: Int64?

        @Option(
            name: .shortAndLong,
            help: "Amount of builder container memory (1MiByte granularity), with optional K, M, G, T, or P suffix"
        )
        var memory: String?

        @OptionGroup
        public var dns: Flags.DNS

        @OptionGroup
        public var logOptions: Flags.Logging

        public init() {}

        public func run() async throws {
            let progressConfig = try ProgressConfig(
                showTasks: true,
                showItems: true,
                totalTasks: 4
            )
            let progress = ProgressBar(config: progressConfig)
            defer {
                progress.finish()
            }
            progress.start()
            try await Self.start(
                cpus: self.cpus,
                memory: self.memory,
                log: log,
                dnsNameservers: self.dns.nameservers,
                dnsDomain: self.dns.domain,
                dnsSearchDomains: self.dns.searchDomains,
                dnsOptions: self.dns.options,
                progressUpdate: progress.handler
            )
            progress.finish()
        }

        static func start(
            cpus: Int64?,
            memory: String?,
            log: Logger,
            dnsNameservers: [String] = [],
            dnsDomain: String? = nil,
            dnsSearchDomains: [String] = [],
            dnsOptions: [String] = [],
            progressUpdate: @escaping ProgressUpdateHandler
        ) async throws {
            await progressUpdate([
                .setDescription("Fetching BuildKit image"),
                .setItemsName("blobs"),
            ])
            let taskManager = ProgressTaskCoordinator()
            let fetchTask = await taskManager.startTask()

            let builderImage: String = DefaultsStore.get(key: .defaultBuilderImage)
            let systemHealth = try await ClientHealthCheck.ping(timeout: .seconds(10))
            let exportsMount: String = systemHealth.appRoot
                .appendingPathComponent(Application.BuilderCommand.builderResourceDir)
                .absolutePath()

            if !FileManager.default.fileExists(atPath: exportsMount) {
                try FileManager.default.createDirectory(
                    atPath: exportsMount,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }

            let builderPlatform = ContainerizationOCI.Platform(arch: "arm64", os: "linux", variant: "v8")

            var targetEnvVars: [String] = []
            if let buildkitColors = ProcessInfo.processInfo.environment["BUILDKIT_COLORS"] {
                targetEnvVars.append("BUILDKIT_COLORS=\(buildkitColors)")
            }
            if ProcessInfo.processInfo.environment["NO_COLOR"] != nil {
                targetEnvVars.append("NO_COLOR=true")
            }
            targetEnvVars.sort()

            let client = ContainerClient()
            let existingContainer = try? await client.get(id: "buildkit")
            if let existingContainer {
                let existingImage = existingContainer.configuration.image.reference
                let existingResources = existingContainer.configuration.resources
                let existingEnv = existingContainer.configuration.initProcess.environment
                let existingDNS = existingContainer.configuration.dns

                let existingManagedEnv = existingEnv.filter { envVar in
                    envVar.hasPrefix("BUILDKIT_COLORS=") || envVar.hasPrefix("NO_COLOR=")
                }.sorted()

                let envChanged = existingManagedEnv != targetEnvVars

                // Check if we need to recreate the builder due to different image
                let imageChanged = existingImage != builderImage
                let resolvedResources = try Parser.resources(
                    cpus: cpus,
                    memory: memory,
                    cpuPropertyKey: .defaultBuildCPUs,
                    memoryPropertyKey: .defaultBuildMemory,
                    defaultCPUs: Self.defaultCPUs,
                    defaultMemoryInBytes: Self.defaultMemoryInBytes
                )
                let cpuChanged = existingResources.cpus != resolvedResources.cpus
                let memChanged = existingResources.memoryInBytes != resolvedResources.memoryInBytes
                // Flagged #2: MEDIUM: `dnsChanged` closure short-circuits on first non-empty DNS field, silently ignoring the rest
                // The closure used a chain of `if !field.isEmpty { return field != existing }` statements. Each branch returned immediately when it found the first non-empty/non-nil DNS parameter, so any subsequent DNS fields were never evaluated. For example, if `dnsNameservers` was provided and matched the existing container, the closure returned `false` without checking `dnsDomain`, `dnsSearchDomains`, or `dnsOptions`. Changed DNS values in those fields were silently ignored.
                let dnsChanged = (!dnsNameservers.isEmpty && existingDNS?.nameservers != dnsNameservers)
                    || (dnsDomain != nil && existingDNS?.domain != dnsDomain)
                    || (!dnsSearchDomains.isEmpty && existingDNS?.searchDomains != dnsSearchDomains)
                    || (!dnsOptions.isEmpty && existingDNS?.options != dnsOptions)

                switch existingContainer.status {
                case .running:
                    guard imageChanged || cpuChanged || memChanged || envChanged || dnsChanged else {
                        // If image, mem, cpu, env, and DNS are the same, continue using the existing builder
                        return
                    }
                    // If they changed, stop and delete the existing builder
                    try await client.stop(id: existingContainer.id)
                    try await client.delete(id: existingContainer.id)
                case .stopped:
                    // If the builder is stopped and matches our requirements, start it
                    // Otherwise, delete it and create a new one
                    guard imageChanged || cpuChanged || memChanged || envChanged || dnsChanged else {
                        // Flagged #3: LOW: `startBuildKit` called with `nil` task manager when restarting a stopped container
                        // In the `.stopped` case, when the existing container's configuration matches and it only needs to be restarted, `startBuildKit` was called with `nil` as the `taskManager` argument. The `startBuildKit` function calls `await taskManager?.finish()` after starting the process; passing `nil` meant this call was a no-op, so the `ProgressTaskCoordinator` task that was started at the top of `start()` (via `taskManager.startTask()`) was never finished.
                        try await startBuildKit(client: client, id: existingContainer.id, progressUpdate, taskManager)
                        return
                    }
                    try await client.delete(id: existingContainer.id)
                case .stopping:
                    throw ContainerizationError(
                        .invalidState,
                        message: "builder is stopping, please wait until it is fully stopped before proceeding"
                    )
                case .unknown:
                    // Flagged #1: HIGH: `.unknown` container status falls through to `client.create` without deleting the existing container
                    // In the `switch existingContainer.status` block, the `.unknown` case contained only `break`. After the switch, execution unconditionally falls through to `client.create(configuration:options:kernel:)` using `id: Builder.builderContainerId` ("buildkit"). Because the existing container with that ID was never deleted, the create call attempts to register a second container under an already-occupied ID.
                    try await client.delete(id: existingContainer.id)
                }
            }

            let useRosetta = DefaultsStore.getBool(key: .buildRosetta) ?? true
            let shimArguments = [
                "--debug",
                "--vsock",
                useRosetta ? nil : "--enable-qemu",
            ].compactMap { $0 }

            try ContainerAPIClient.Utility.validEntityName(Builder.builderContainerId)

            let image = try await ClientImage.fetch(
                reference: builderImage,
                platform: builderPlatform,
                progressUpdate: ProgressTaskCoordinator.handler(for: fetchTask, from: progressUpdate)
            )
            // Unpack fetched image before use
            await progressUpdate([
                .setDescription("Unpacking BuildKit image"),
                .setItemsName("entries"),
            ])

            let unpackTask = await taskManager.startTask()
            _ = try await image.getCreateSnapshot(
                platform: builderPlatform,
                progressUpdate: ProgressTaskCoordinator.handler(for: unpackTask, from: progressUpdate)
            )

            let imageDesc = ImageDescription(
                reference: builderImage,
                descriptor: image.descriptor
            )

            let imageConfig = try await image.config(for: builderPlatform).config
            var environment = imageConfig?.env ?? []
            environment.append(contentsOf: targetEnvVars)

            let processConfig = ProcessConfiguration(
                executable: "/usr/local/bin/container-builder-shim",
                arguments: shimArguments,
                environment: environment,
                workingDirectory: "/",
                terminal: false,
                user: .id(uid: 0, gid: 0)
            )

            let resources = try Parser.resources(
                cpus: cpus,
                memory: memory,
                cpuPropertyKey: .defaultBuildCPUs,
                memoryPropertyKey: .defaultBuildMemory,
                defaultCPUs: Self.defaultCPUs,
                defaultMemoryInBytes: Self.defaultMemoryInBytes
            )

            var config = ContainerConfiguration(id: Builder.builderContainerId, image: imageDesc, process: processConfig)
            config.resources = resources
            config.labels = [ResourceLabelKeys.role: ResourceRoleValues.builder]
            config.capAdd = ["ALL"]
            config.mounts = [
                .init(
                    type: .tmpfs,
                    source: "",
                    destination: "/run",
                    options: []
                ),
                .init(
                    type: .virtiofs,
                    source: exportsMount,
                    destination: "/var/lib/container-builder-shim/exports",
                    options: []
                ),
            ]
            // Enable Rosetta only if the user didn't ask to disable it
            config.rosetta = useRosetta

            let networkClient = NetworkClient()
            guard let defaultNetwork = try await networkClient.builtin else {
                throw ContainerizationError(.invalidState, message: "default network is not present")
            }
            guard case .running(_, _) = defaultNetwork else {
                throw ContainerizationError(.invalidState, message: "default network is not running")
            }
            config.networks = [
                AttachmentConfiguration(network: defaultNetwork.id, options: AttachmentOptions(hostname: Builder.builderContainerId))
            ]
            config.dns = ContainerConfiguration.DNSConfiguration(
                nameservers: dnsNameservers,
                domain: dnsDomain,
                searchDomains: dnsSearchDomains,
                options: dnsOptions
            )

            let kernel = try await {
                await progressUpdate([
                    .setDescription("Fetching kernel"),
                    .setItemsName("binary"),
                ])

                let kernel = try await ClientKernel.getDefaultKernel(for: .current)
                return kernel
            }()

            await progressUpdate([
                .setDescription("Starting BuildKit container")
            ])

            try await client.create(
                configuration: config,
                options: .default,
                kernel: kernel
            )

            try await startBuildKit(client: client, id: Builder.builderContainerId, progressUpdate, taskManager)
            log.debug("starting BuildKit and BuildKit-shim")
        }
    }
}

// MARK: - BuildKit Start Helper

/// Starts the BuildKit process within the container
/// This function handles bootstrapping the container and starting the BuildKit process
private func startBuildKit(
    client: ContainerClient,
    id: String,
    _ progress: @escaping ProgressUpdateHandler,
    _ taskManager: ProgressTaskCoordinator? = nil
) async throws {
    do {
        let io = try ProcessIO.create(
            tty: false,
            interactive: false,
            detach: true
        )
        defer { try? io.close() }

        var dynamicEnv: [String: String] = [:]
        if let sshAuthSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
            dynamicEnv["SSH_AUTH_SOCK"] = sshAuthSock
        }

        let process = try await client.bootstrap(id: id, stdio: io.stdio, dynamicEnv: dynamicEnv)
        try await process.start()
        await taskManager?.finish()
        try io.closeAfterStart()
    } catch {
        try? await client.stop(id: id)
        try? await client.delete(id: id)
        if error is ContainerizationError {
            throw error
        }
        throw ContainerizationError(.internalError, message: "failed to start BuildKit: \(error)")
    }
}
