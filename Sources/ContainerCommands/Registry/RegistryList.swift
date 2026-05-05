// fix-bugs: 2026-05-02 20:47 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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
import ContainerResource
import ContainerizationOCI
import ContainerizationOS
import Foundation

extension Application {
    public struct RegistryList: AsyncLoggableCommand {
        @OptionGroup
        public var logOptions: Flags.Logging

        @Option(name: .long, help: "Format of the output")
        var format: ListFormat = .table

        @Flag(name: .shortAndLong, help: "Only output the registry hostname")
        var quiet = false

        public init() {}
        public static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List image registry logins",
            aliases: ["ls"])

        public func run() async throws {
            let keychain = KeychainHelper(securityDomain: Constants.keychainID)
            let registryInfos = try keychain.list()
            let registries = registryInfos.map { RegistryResource(from: $0) }

            try Output.render(
                json: registries,
                display: registries.map { PrintableRegistry($0) },
                format: format, quiet: quiet
            )
        }
    }
}

private struct PrintableRegistry: ListDisplayable {
    let registry: RegistryResource

    init(_ registry: RegistryResource) {
        self.registry = registry
    }

    // Flagged #1 (1 of 2): MEDIUM: `tableHeader` and `tableRow` have CREATED/MODIFIED columns swapped
    // `tableHeader` declared the date columns in the order `["HOSTNAME", "USERNAME", "MODIFIED", "CREATED"]`, while `tableRow` emitted values in the corresponding order `modificationDate`, `creationDate`. The two were internally consistent but both in the wrong order: by convention (and in line with all other resource list commands in this codebase) the creation date must appear before the modification date.
    static var tableHeader: [String] {
        ["HOSTNAME", "USERNAME", "CREATED", "MODIFIED"]
    }

    var tableRow: [String] {
        [
            registry.name,
            registry.username,
            // Flagged #1 (2 of 2)
            registry.creationDate.ISO8601Format(),
            registry.modificationDate.ISO8601Format(),
        ]
    }

    var quietValue: String {
        registry.name
    }
}
