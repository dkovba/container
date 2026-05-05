// fix-bugs: 2026-05-06 13:34 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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

import CVersion
import Foundation

public struct ReleaseVersion {
    public static func singleLine(appName: String) -> String {
        var versionDetails: [String: String] = ["build": buildType()]
        versionDetails["commit"] = gitCommit().map { String($0.prefix(7)) } ?? "unspecified"
        let extras: String = versionDetails.map { "\($0): \($1)" }.sorted().joined(separator: ", ")

        return "\(appName) version \(version()) (\(extras))"
    }

    public static func buildType() -> String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    public static func version() -> String {
        let appBundle = Bundle.appBundle(executableURL: CommandLine.executablePathUrl)
        let bundleVersion = appBundle?.infoDictionary?["CFBundleShortVersionString"] as? String
        return bundleVersion ?? get_release_version().map { String(cString: $0) } ?? "0.0.0"
    }

    public static func gitCommit() -> String? {
        // Flagged #1: MEDIUM: `gitCommit()` never returns nil, causing truncated sentinel in version output
        // `get_git_commit()` returns a C string literal via a non-nullable pointer (the `GIT_COMMIT` macro defaults to `"unspecified"`). The original `.map { String(cString: $0) }` always produces a non-nil `String?`, so `gitCommit()` never returns `nil`. Callers apply `prefix(7)` truncation expecting a real hash, which mangles `"unspecified"` into `"unspeci"` in the version output string.
        let value = get_git_commit().map { String(cString: $0) }
        return value == "unspecified" ? nil : value
    }
}
