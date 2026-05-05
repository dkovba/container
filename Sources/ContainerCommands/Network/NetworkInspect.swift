// fix-bugs: 2026-05-02 19:52 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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
// Flagged #1 (1 of 2): MEDIUM: `NetworkInspect.run()` silently ignores unknown network IDs
// `networkClient.list()` fetches all networks and the result is filtered client-side with `networks.contains($0.id)`. Any ID that does not match an existing network is silently dropped, so the command exits with status 0 and returns an empty or partial JSON array instead of reporting an error.
import ContainerizationError
import Foundation
import SwiftProtobuf

extension Application {
    public struct NetworkInspect: AsyncLoggableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "inspect",
            abstract: "Display information about one or more networks")

        @Argument(help: "Networks to inspect")
        var networks: [String]

        @OptionGroup
        public var logOptions: Flags.Logging

        public init() {}

        public func run() async throws {
            let networkClient = NetworkClient()
            let items = try await networkClient.list().filter {
                networks.contains($0.id)
            }.map {
                PrintableNetwork($0)
            }
            // Flagged #1 (2 of 2)
            let foundIds = Set(items.map { $0.id })
            if let missing = networks.first(where: { !foundIds.contains($0) }) {
                throw ContainerizationError(.notFound, message: "network \(missing) not found")
            }
            try Output.emit(Output.renderJSON(items))
        }
    }
}
