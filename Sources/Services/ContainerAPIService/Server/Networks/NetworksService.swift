// fix-bugs: 2026-04-28 16:22 — 1 critical, 4 high, 1 medium, 3 low (9 total)
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
import ContainerNetworkServiceClient
import ContainerPersistence
import ContainerPlugin
import ContainerResource
import ContainerXPC
import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOS
import Foundation
import Logging

public actor NetworksService {
    struct NetworkServiceState {
        var networkState: NetworkState
        var client: ContainerNetworkServiceClient.NetworkClient
    }

    private let pluginLoader: PluginLoader
    private let resourceRoot: URL
    private let containersService: ContainersService
    private let log: Logger
    private let debugHelpers: Bool

    private let store: FilesystemEntityStore<NetworkConfiguration>
    private let networkPlugins: [Plugin]
    private var busyNetworks = Set<String>()

    private let stateLock = AsyncLock()
    private var serviceStates = [String: NetworkServiceState]()

    public init(
        pluginLoader: PluginLoader,
        resourceRoot: URL,
        containersService: ContainersService,
        log: Logger,
        debugHelpers: Bool = false,
    ) async throws {
        self.pluginLoader = pluginLoader
        self.resourceRoot = resourceRoot
        self.containersService = containersService
        self.log = log
        self.debugHelpers = debugHelpers

        try FileManager.default.createDirectory(at: resourceRoot, withIntermediateDirectories: true)
        self.store = try FilesystemEntityStore<NetworkConfiguration>(
            path: resourceRoot,
            type: "network",
            log: log
        )

        let networkPlugins =
            pluginLoader
            .findPlugins()
            .filter { $0.hasType(.network) }
        guard !networkPlugins.isEmpty else {
            throw ContainerizationError(.internalError, message: "cannot find any plugins with type network")
        }
        self.networkPlugins = networkPlugins

        let configurations = try await store.list()
        for configuration in configurations {
            // Ensure the network with id "default" is marked as builtin.
            var updatedLabels: [String: String]?
            // Flagged #1 (1 of 4): CRITICAL: `init` passes stale configuration with nil `pluginInfo` to `registerService` and `getClient`
            // When `configuration.pluginInfo` is nil, the `if` block creates `updatedConfiguration` with a fallback `pluginInfo` and persists it, but the subsequent calls to `registerService(configuration:)` and `Self.getClient(configuration:)` still receive the original `configuration` whose `pluginInfo` remains nil. Both methods guard against nil `pluginInfo` and throw, so `registerService` fails (caught and logged) and then `getClient` throws an unrecoverable error that crashes the entire initializer.
            var activeConfiguration = configuration
            if configuration.id == NetworkClient.defaultNetworkName {
                let role = configuration.labels[ResourceLabelKeys.role]
                if role == nil || role != ResourceRoleValues.builtin {
                    var labels = configuration.labels.dictionary
                    labels[ResourceLabelKeys.role] = ResourceRoleValues.builtin
                    updatedLabels = labels
                }
            }

            // Ensure that the network always has plugin information.
            // Before this field was added, the code always assumed we were using the
            // container-network-vmnet network plugin, so it should be safe to fallback to that
            // if no info was found in an on disk configuration.
            if updatedLabels != nil || configuration.pluginInfo == nil {
                // Flagged #5 (1 of 2): HIGH: `init` loop has no error handling around configuration update, so one corrupt network aborts the entire initializer
                // In the `for configuration in configurations` loop, the `NetworkConfiguration(...)` construction and `store.update(updatedConfiguration)` calls inside the `if updatedLabels != nil || configuration.pluginInfo == nil` block are bare `try`/`try await` expressions with no surrounding `do/catch`. If either throws — for example `try .init($0)` fails on corrupted persisted labels, or `store.update` fails due to a disk I/O error — the error propagates out of the `for` loop and out of `init`, aborting the entire `NetworksService` initialization.
                do {
                    let updatedConfiguration = try NetworkConfiguration(
                        id: configuration.id,
                        mode: configuration.mode,
                        ipv4Subnet: configuration.ipv4Subnet,
                        ipv6Subnet: configuration.ipv6Subnet,
                        labels: updatedLabels.map { try .init($0) } ?? configuration.labels,
                        pluginInfo: configuration.pluginInfo ?? NetworkPluginInfo(plugin: "container-network-vmnet")
                    )
                    try await store.update(updatedConfiguration)
                    // Flagged #1 (2 of 4)
                    activeConfiguration = updatedConfiguration
                // Flagged #5 (2 of 2)
                } catch {
                    log.error(
                        "failed to update network configuration",
                        metadata: [
                            "id": "\(configuration.id)",
                            "error": "\(error)",
                        ])
                    continue
                }
            }

            // Start up the network.
            do {
                // Flagged #1 (3 of 4)
                try await registerService(configuration: activeConfiguration)
            } catch {
                log.error(
                    "failed to start network",
                    metadata: [
                        "id": "\(configuration.id)",
                        "error": "\(error)",
                    ])
                // Flagged #3: HIGH: `init` loop falls through to `getClient`/`client.state()` after `registerService` failure
                // In the `for configuration in configurations` loop, the `do/catch` around `registerService` logs the error but does not `continue` to the next iteration. Execution falls through to `Self.getClient(configuration:)` and `client.state()`, which operate on a service that was never registered. The `client.state()` call throws an uncaught error that propagates out of `init`, aborting the initializer.
                continue
            }

            // This call will normally take ~20-100ms to complete after service
            // registration, but on a fresh system (e.g. CI runner), it may take
            // 5 seconds or considerably more from the registration of this first
            // network service to its execution.
            // Flagged #4 (1 of 2): HIGH: `init` loop has no error handling around `getClient`/`client.state()`, so one failing network aborts the entire initializer
            // After the `registerService` do/catch block, the calls to `Self.getClient(configuration:)` and `client.state()` (as well as the `try NetworkConfiguration(...)` calls in the switch body) are bare `try`/`try await` expressions at the top level of the `for configuration in configurations` loop with no surrounding do/catch. If any of these throw — for example `client.state()` times out due to an unresponsive XPC service — the error propagates out of the loop and out of `init`, aborting the entire `NetworksService` initialization.
            do {
                // Flagged #1 (4 of 4)
                let client = try Self.getClient(configuration: activeConfiguration)
                var networkState = try await client.state()

                // FIXME: Temporary workaround for persisted configuration being overwritten
                // by what comes back from the network helper, which messes up creationDate.
                // FIXME: Temporarily need to override the plugin information with the info from
                // the helper, so we can ensure that older networks get a variant value.
                let finalConfiguration: NetworkConfiguration
                switch networkState {
                case .created(let helperConfig):
                    finalConfiguration = try NetworkConfiguration(
                        id: configuration.id,
                        mode: configuration.mode,
                        ipv4Subnet: configuration.ipv4Subnet,
                        ipv6Subnet: configuration.ipv6Subnet,
                        labels: updatedLabels.map { try .init($0) } ?? configuration.labels,
                        pluginInfo: helperConfig.pluginInfo
                    )
                    networkState = NetworkState.created(finalConfiguration)
                case .running(let helperConfig, let status):
                    finalConfiguration = try NetworkConfiguration(
                        id: configuration.id,
                        mode: configuration.mode,
                        ipv4Subnet: configuration.ipv4Subnet,
                        ipv6Subnet: configuration.ipv6Subnet,
                        labels: updatedLabels.map { try .init($0) } ?? configuration.labels,
                        pluginInfo: helperConfig.pluginInfo
                    )
                    networkState = NetworkState.running(finalConfiguration, status)
                }

                guard case .running = networkState else {
                    log.error(
                        "network failed to start",
                        metadata: [
                            "id": "\(finalConfiguration.id)",
                            "state": "\(networkState.state)",
                        ])
                    // Flagged #2: HIGH: `return` in `init` loop exits initializer instead of advancing to next network
                    // Inside the `for configuration in configurations` loop, a `guard case .running` check uses `return` when a network is not in the running state. Because this is an `init`, `return` exits the initializer entirely, skipping all remaining networks in the list.
                    continue
                }

                // Flagged #6: MEDIUM: `init` adds non-running networks to `serviceStates` before the `guard case .running` check
                // In the `for configuration in configurations` loop, the `NetworkServiceState` is created and inserted into `serviceStates` before the `guard case .running = networkState` check. When a network's helper reports `.created` (not running), the entry is stored in `serviceStates`, the guard logs an error and `continue`s to the next network, but the entry remains. Because `delete(id:)` requires `guard case .running` on the service state, these entries can never be deleted through the API. They also appear in `list()` results and can be passed to `allocate()`, which will attempt to use a non-running client.
                let state = NetworkServiceState(
                    networkState: networkState,
                    client: client
                )

                serviceStates[finalConfiguration.id] = state
            // Flagged #4 (2 of 2)
            } catch {
                log.error(
                    "failed to initialize network",
                    metadata: [
                        "id": "\(activeConfiguration.id)",
                        "error": "\(error)",
                    ])
                continue
            }
        }
    }

    /// List all networks registered with the service.
    public func list() async throws -> [NetworkState] {
        log.debug("NetworksService: enter", metadata: ["func": "\(#function)"])
        defer { log.debug("NetworksService: exit", metadata: ["func": "\(#function)"]) }

        return serviceStates.reduce(into: [NetworkState]()) {
            $0.append($1.value.networkState)
        }
    }

    /// Create a new network from the provided configuration.
    public func create(configuration: NetworkConfiguration) async throws -> NetworkState {
        log.debug(
            "NetworksService: enter",
            metadata: [
                "func": "\(#function)",
                "id": "\(configuration.id)",
            ]
        )
        defer {
            log.debug(
                "NetworksService: exit",
                metadata: [
                    "func": "\(#function)",
                    "id": "\(configuration.id)",
                ]
            )
        }

        //Ensure that the network is not named "none"
        if configuration.id == NetworkClient.noNetworkName {
            throw ContainerizationError(.unsupported, message: "network \(configuration.id) is not a valid name")
        }

        // Ensure nobody is manipulating the network already.
        guard !busyNetworks.contains(configuration.id) else {
            throw ContainerizationError(.exists, message: "network \(configuration.id) has a pending operation")
        }

        busyNetworks.insert(configuration.id)
        defer { busyNetworks.remove(configuration.id) }

        // Ensure the network doesn't already exist.
        return try await self.stateLock.withLock { _ in
            guard await self.serviceStates[configuration.id] == nil else {
                throw ContainerizationError(.exists, message: "network \(configuration.id) already exists")
            }

            // Create and start the network.
            try await self.registerService(configuration: configuration)
            let client = try Self.getClient(configuration: configuration)

            // Ensure the network is running, and set up the persistent network state
            // using our configuration data
            guard case .running(let helperConfig, let status) = try await client.state() else {
                throw ContainerizationError(.invalidState, message: "network \(configuration.id) failed to start")
            }

            let finalConfiguration = try NetworkConfiguration(
                id: configuration.id,
                mode: configuration.mode,
                ipv4Subnet: configuration.ipv4Subnet,
                ipv6Subnet: configuration.ipv6Subnet,
                labels: configuration.labels,
                pluginInfo: helperConfig.pluginInfo
            )

            let networkState: NetworkState = .running(finalConfiguration, status)
            let serviceState = NetworkServiceState(networkState: networkState, client: client)
            await self.setServiceState(key: finalConfiguration.id, value: serviceState)

            // Persist the configuration data.
            do {
                try await self.store.create(finalConfiguration)
                return networkState
            } catch {
                await self.removeServiceState(key: finalConfiguration.id)
                do {
                    try await self.deregisterService(configuration: finalConfiguration)
                } catch {
                    self.log.error(
                        "failed to deregister network service after failed creation",
                        metadata: [
                            "id": "\(finalConfiguration.id)",
                            "error": "\(error.localizedDescription)",
                        ])
                }
                throw error
            }
        }
    }

    /// Delete a network.
    public func delete(id: String) async throws {
        log.debug(
            "NetworksService: enter",
            metadata: [
                "func": "\(#function)",
                "id": "\(id)",
            ]
        )
        defer {
            log.debug(
                // Flagged #7: LOW: `delete` defer log message says "enter" instead of "exit"
                // The `defer` block in `delete(id:)` logs `"NetworksService: enter"` instead of `"NetworksService: exit"`, making it identical to the log line at function entry.
                "NetworksService: exit",
                metadata: [
                    "func": "\(#function)",
                    "id": "\(id)",
                ]
            )
        }

        // check actor busy state
        guard !busyNetworks.contains(id) else {
            throw ContainerizationError(.exists, message: "network \(id) has a pending operation")
        }

        // make actor state busy for this network
        busyNetworks.insert(id)
        defer { busyNetworks.remove(id) }

        log.info(
            "deleting network",
            metadata: [
                "id": "\(id)"
            ]
        )

        try await stateLock.withLock { _ in
            guard let serviceState = await self.serviceStates[id] else {
                throw ContainerizationError(.notFound, message: "no network for id \(id)")
            }

            guard case .running(let netConfig, _) = serviceState.networkState else {
                throw ContainerizationError(.invalidState, message: "cannot delete network \(id) in state \(serviceState.networkState.state)")
            }

            // basic sanity checks on network itself
            if serviceState.networkState.isBuiltin {
                throw ContainerizationError(.invalidArgument, message: "cannot delete builtin network: \(id)")
            }

            // prevent container operations while we atomically check and delete
            try await self.containersService.withContainerList(logMetadata: ["acquirer": "\(#function)", "id": "\(id)"]) { containers in
                // find all containers that refer to the network
                var referringContainers = Set<String>()
                for container in containers {
                    for attachmentConfiguration in container.configuration.networks {
                        if attachmentConfiguration.network == id {
                            referringContainers.insert(container.configuration.id)
                            break
                        }
                    }
                }

                // bail if any referring containers
                guard referringContainers.isEmpty else {
                    throw ContainerizationError(
                        .invalidState,
                        // Flagged #9: LOW: `delete` error message says "subnet" instead of "network"
                        // In `delete(id:)`, when referring containers prevent deletion, the error message reads `"cannot delete subnet \(id) with referring containers: …"`. The method deletes networks, not subnets, and every other error message in the method correctly uses the term "network".
                        message: "cannot delete network \(id) with referring containers: \(referringContainers.joined(separator: ", "))"
                    )
                }

                // start network deletion, this is the last place we'll want to throw
                do {
                    try await self.deregisterService(configuration: netConfig)
                } catch {
                    self.log.error(
                        "failed to deregister network service",
                        metadata: [
                            "id": "\(id)",
                            "error": "\(error.localizedDescription)",
                        ])
                }

                // deletion is underway, do not throw anything now
                do {
                    try await self.store.delete(id)
                } catch {
                    self.log.error(
                        "failed to delete network from configuration store",
                        metadata: [
                            "id": "\(id)",
                            "error": "\(error.localizedDescription)",
                        ])
                }
            }

            // having deleted successfully, remove the runtime state
            await self.removeServiceState(key: id)
        }
    }

    /// Perform a hostname lookup on all networks.
    ///
    /// - Parameter hostname: A canonical DNS hostname with a trailing dot (e.g. `"example.com."`).
    public func lookup(hostname: String) async throws -> Attachment? {
        try await self.stateLock.withLock { _ in
            for state in await self.serviceStates.values {
                guard let allocation = try await state.client.lookup(hostname: hostname) else {
                    continue
                }
                return allocation
            }
            return nil
        }
    }

    public func allocate(id: String, hostname: String, macAddress: MACAddress?) async throws -> AllocatedAttachment {
        guard let serviceState = serviceStates[id] else {
            throw ContainerizationError(.notFound, message: "no network for id \(id)")
        }
        guard let pluginInfo = serviceState.networkState.pluginInfo else {
            throw ContainerizationError(.internalError, message: "network \(id) missing plugin information")
        }
        let (attach, additionalData) = try await serviceState.client.allocate(hostname: hostname, macAddress: macAddress)
        return AllocatedAttachment(
            attachment: attach,
            additionalData: additionalData,
            pluginInfo: pluginInfo
        )
    }

    public func deallocate(attachment: Attachment) async throws {
        guard let serviceState = serviceStates[attachment.network] else {
            throw ContainerizationError(.notFound, message: "no network for id \(attachment.network)")
        }
        return try await serviceState.client.deallocate(hostname: attachment.hostname)
    }

    private static func getClient(configuration: NetworkConfiguration) throws -> ContainerNetworkServiceClient.NetworkClient {
        guard let pluginInfo = configuration.pluginInfo else {
            throw ContainerizationError(.internalError, message: "network \(configuration.id) missing plugin information")
        }
        return NetworkClient(id: configuration.id, plugin: pluginInfo.plugin)
    }

    private func registerService(configuration: NetworkConfiguration) async throws {
        guard configuration.mode == .nat || configuration.mode == .hostOnly else {
            throw ContainerizationError(.invalidArgument, message: "unsupported network mode \(configuration.mode.rawValue)")
        }

        guard let pluginInfo = configuration.pluginInfo else {
            throw ContainerizationError(.internalError, message: "network \(configuration.id) missing plugin information")
        }

        guard let networkPlugin = self.networkPlugins.first(where: { $0.name == pluginInfo.plugin }) else {
            throw ContainerizationError(
                .notFound,
                message: "unable to locate network plugin \(pluginInfo.plugin)"
            )
        }

        guard let serviceIdentifier = networkPlugin.getMachService(instanceId: configuration.id, type: .network) else {
            // Flagged #8: LOW: `registerService` reports wrong error code and misleading message when `getMachService` returns nil
            // When `networkPlugin.getMachService(instanceId:type:)` returns nil, the guard throws `ContainerizationError(.invalidArgument, message: "unsupported network mode \(configuration.mode.rawValue)")`. The network mode was already validated as `.nat` or `.hostOnly` by an earlier guard on line 423, so reporting "unsupported network mode" is factually incorrect at this point. The actual failure is that the plugin cannot provide a mach service for this network instance. The error code `.invalidArgument` is also wrong — the argument (mode) is valid; the issue is an internal plugin configuration problem.
            throw ContainerizationError(.internalError, message: "network plugin \(pluginInfo.plugin) has no mach service for network \(configuration.id)")
        }
        var args = [
            "start",
            "--id",
            configuration.id,
            "--service-identifier",
            serviceIdentifier,
            "--mode",
            configuration.mode.rawValue,
        ]
        if debugHelpers {
            args.append("--debug")
        }

        if let ipv4Subnet = configuration.ipv4Subnet {
            var existingCidrs: [CIDRv4] = []
            for serviceState in serviceStates.values {
                if case .running(_, let status) = serviceState.networkState {
                    existingCidrs.append(status.ipv4Subnet)
                }
            }
            let overlap = existingCidrs.first {
                $0.contains(ipv4Subnet.lower)
                    || $0.contains(ipv4Subnet.upper)
                    || ipv4Subnet.contains($0.lower)
                    || ipv4Subnet.contains($0.upper)
            }
            if let overlap {
                throw ContainerizationError(.exists, message: "IPv4 subnet \(ipv4Subnet) overlaps an existing network with subnet \(overlap)")
            }

            args += ["--subnet", ipv4Subnet.description]
        }

        if let ipv6Subnet = configuration.ipv6Subnet {
            var existingCidrs: [CIDRv6] = []
            for serviceState in serviceStates.values {
                if case .running(_, let status) = serviceState.networkState, let otherIPv6Subnet = status.ipv6Subnet {
                    existingCidrs.append(otherIPv6Subnet)
                }
            }
            let overlap = existingCidrs.first {
                $0.contains(ipv6Subnet.lower)
                    || $0.contains(ipv6Subnet.upper)
                    || ipv6Subnet.contains($0.lower)
                    || ipv6Subnet.contains($0.upper)
            }
            if let overlap {
                throw ContainerizationError(.exists, message: "IPv6 subnet \(ipv6Subnet) overlaps an existing network with subnet \(overlap)")
            }

            args += ["--subnet-v6", ipv6Subnet.description]
        }

        if let variant = configuration.pluginInfo?.variant {
            args += ["--variant", variant]
        }

        try await pluginLoader.registerWithLaunchd(
            plugin: networkPlugin,
            pluginStateRoot: store.entityUrl(configuration.id),
            args: args,
            instanceId: configuration.id
        )
    }

    private func deregisterService(configuration: NetworkConfiguration) async throws {
        guard let pluginInfo = configuration.pluginInfo else {
            throw ContainerizationError(.internalError, message: "network \(configuration.id) missing plugin information")
        }
        guard let networkPlugin = self.networkPlugins.first(where: { $0.name == pluginInfo.plugin }) else {
            throw ContainerizationError(
                .notFound,
                message: "unable to locate network plugin \(pluginInfo.plugin)"
            )
        }
        try self.pluginLoader.deregisterWithLaunchd(plugin: networkPlugin, instanceId: configuration.id)
    }
}

extension NetworksService {
    private func removeServiceState(key: String) {
        self.serviceStates.removeValue(forKey: key)
    }

    private func setServiceState(key: String, value: NetworkServiceState) {
        self.serviceStates[key] = value
    }
}
