// fix-bugs: 2026-04-29 15:57 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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

import ContainerResource
import ContainerXPC
import ContainerizationError
import ContainerizationExtras
import Foundation
import Logging

public actor AllocationOnlyVmnetNetwork: Network {
    // The IPv4 subnet to be used if none explicitly passed in the `NetworkConfiguration`
    // Flagged #1: MEDIUM: Default subnet CIDR uses host address instead of network address
    // `CIDRv4("192.168.64.1/24")` specifies a host address (`.1`) rather than the network address (`.0`). `CIDRv4` stores the literal address in its `address` property and `description` returns `"\(address)/\(prefix)"`, so the non-canonical `192.168.64.1/24` appears in all log output and Codable serialization even though `lower` normalizes for gateway computation.
    private static let defaultIPv4Subnet = try! CIDRv4("192.168.64.0/24")

    private let log: Logger
    private var _state: NetworkState

    /// Configure a bridge network that allows external system access using
    /// network address translation.
    public init(
        configuration: NetworkConfiguration,
        log: Logger
    ) throws {
        guard configuration.mode == .nat else {
            throw ContainerizationError(.unsupported, message: "invalid network mode \(configuration.mode)")
        }

        guard configuration.ipv6Subnet == nil else {
            throw ContainerizationError(.unsupported, message: "IPv6 subnet assignment is not yet implemented")
        }

        self.log = log
        self._state = .created(configuration)
    }

    public var state: NetworkState {
        self._state
    }

    public nonisolated func withAdditionalData(_ handler: (XPCMessage?) throws -> Void) throws {
        try handler(nil)
    }

    public func start() async throws {
        guard case .created(let configuration) = _state else {
            throw ContainerizationError(.invalidState, message: "cannot start network \(_state.id) in \(_state.state) state")
        }

        log.info(
            "starting allocation-only network",
            metadata: [
                "id": "\(configuration.id)",
                "mode": "\(NetworkMode.nat.rawValue)",
            ]
        )

        let ipv4Subnet = configuration.ipv4Subnet ?? Self.defaultIPv4Subnet

        let gateway = IPv4Address(ipv4Subnet.lower.value + 1)
        let status = NetworkStatus(
            ipv4Subnet: ipv4Subnet,
            ipv4Gateway: gateway,
            ipv6Subnet: nil,
        )
        self._state = .running(configuration, status)
        log.info(
            "started allocation-only network",
            metadata: [
                "id": "\(configuration.id)",
                "mode": "\(configuration.mode)",
                "cidr": "\(ipv4Subnet)",
            ]
        )
    }
}
