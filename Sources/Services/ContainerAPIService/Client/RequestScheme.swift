// fix-bugs: 2026-04-28 21:48 — 0 critical, 3 high, 0 medium, 0 low (3 total)
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

import ContainerPersistence
import ContainerizationError

/// The URL scheme to be used for a HTTP request.
public enum RequestScheme: String, Sendable {
    case http = "http"
    case https = "https"

    case auto = "auto"

    public init(_ rawValue: String) throws {
        switch rawValue {
        case RequestScheme.http.rawValue:
            self = .http
        case RequestScheme.https.rawValue:
            self = .https
        case RequestScheme.auto.rawValue:
            self = .auto
        default:
            throw ContainerizationError(.invalidArgument, message: "unsupported scheme \(rawValue)")
        }
    }

    /// Returns the prescribed protocol to use while making a HTTP request to a webserver
    /// - Parameter host: The domain or IP address of the webserver
    /// - Returns: RequestScheme
    public func schemeFor(host: String) throws -> Self {
        guard host.count > 0 else {
            throw ContainerizationError(.invalidArgument, message: "host cannot be empty")
        }
        switch self {
        case .http, .https:
            return self
        case .auto:
            return Self.isInternalHost(host: host) ? .http : .https
        }
    }

    /// Checks if the given `host` string is a private IP address
    /// or a domain typically reachable only on the local system.
    private static func isInternalHost(host: String) -> Bool {
        // Flagged #1: HIGH: `isInternalHost` misclassifies external hosts starting with "localhost" as internal
        // `host.hasPrefix("localhost")` matches any hostname that begins with the string "localhost", such as `localhostevil.com` or `localhost.attacker.org`, incorrectly treating them as internal hosts.
        // Flagged #3 (1 of 3): HIGH: `isInternalHost` private-IP prefix checks match non-IP hostnames
        // The `hasPrefix("127.")`, `hasPrefix("192.168.")`, `hasPrefix("10.")`, and `172.16-31` regex checks operate on raw string prefixes without verifying the host is an IPv4 address. Hostnames such as `10.evil.com`, `127.attacker.org`, `192.168.phishing.net`, or `172.16.malicious.com` match these prefix checks and are incorrectly classified as internal.
        if host == "localhost" || (host.allSatisfy({ $0 == "." || ($0.isASCII && $0.isNumber) }) && host.hasPrefix("127.")) {
            return true
        }
        // Flagged #3 (2 of 3)
        if host.allSatisfy({ $0 == "." || ($0.isASCII && $0.isNumber) }) && (host.hasPrefix("192.168.") || host.hasPrefix("10.")) {
            return true
        }
        let regex = "(^172\\.1[6-9]\\.)|(^172\\.2[0-9]\\.)|(^172\\.3[0-1]\\.)"
        // Flagged #3 (3 of 3)
        if host.allSatisfy({ $0 == "." || ($0.isASCII && $0.isNumber) }) && host.range(of: regex, options: .regularExpression) != nil {
            return true
        }
        let dnsDomain = DefaultsStore.get(key: .defaultDNSDomain)
        // Flagged #2: HIGH: `isInternalHost` misclassifies external hosts as internal when DNS domain is empty
        // When `DefaultsStore.get(key: .defaultDNSDomain)` returns an empty string, the expression `".\(dnsDomain)"` evaluates to `"."`, causing `host.hasSuffix(".")` to match any host written in FQDN form (e.g., `evil.com.`), incorrectly treating it as internal.
        if !dnsDomain.isEmpty && host.hasSuffix(".\(dnsDomain)") {
            return true
        }
        return false
    }
}
