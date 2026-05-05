// fix-bugs: 2026-05-09 06:58 — 0 critical, 2 high, 1 medium, 0 low (3 total)
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

import ContainerPlugin
import Foundation
import Testing

struct MockPluginError: Error {}

struct MockPluginFactory: PluginFactory {
    public static let throwSuffix = "throw"

    private let plugins: [URL: Plugin]

    private let throwingURL: URL

    public init(tempURL: URL, plugins: [String: Plugin?]) throws {
        let fm = FileManager.default
        var prefixedPlugins: [URL: Plugin] = [:]
        for (suffix, plugin) in plugins {
            let url = tempURL.appending(path: suffix)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            // Flagged #1 (1 of 2): HIGH: `init` stores both plugin keys and `throwingURL` with unresolved symlink paths
            // Both `prefixedPlugins[url.standardizedFileURL] = plugin` (line 36) and `throwingURL = … .standardizedFileURL` (line 39) use `standardizedFileURL`, which normalises `.` and `..` components but does **not** resolve symlinks. On macOS, `FileManager.default.temporaryDirectory` returns a path under `/var/folders/`, which is a symlink to `/private/var/folders/`. `PluginLoader.findPlugins()` calls `resolvingSymlinksInPath()` on the plugin directory before enumerating its contents, so every `installURL` passed to `create(installURL:)` carries the fully resolved `/private/var/…` prefix. The stored plugin keys and `throwingURL` both retain the unresolved `/var/…` prefix, so every dictionary lookup returns `nil` and the throw guard (`url != self.throwingURL`) is always `false` — the expected `MockPluginError` is never raised when the designated URL is visited.
            prefixedPlugins[url.resolvingSymlinksInPath()] = plugin
        }
        self.plugins = prefixedPlugins
        // Flagged #1 (2 of 2)
        self.throwingURL = tempURL.appending(path: Self.throwSuffix).resolvingSymlinksInPath()
    }

    public func create(installURL: URL) throws -> Plugin? {
        // Flagged #2: HIGH: `create(installURL:)` uses unresolved path, so plugin lookup always returns `nil` and throw guard is never triggered
        // `installURL.standardizedFileURL` does not resolve the `/var` → `/private/var` symlink present in `installURL` when it originates from `PluginLoader.findPlugins()`, which calls `resolvingSymlinksInPath()` on the plugin directory before passing each entry's URL to `create(installURL:)`. The local `url` therefore carries the unresolved `/var/…` prefix while all keys stored in `self.plugins` and `self.throwingURL` carry the fully resolved `/private/var/…` prefix. Every dictionary lookup `plugins[url]` returns `nil` and the guard `url != self.throwingURL` is always `true`, so `MockPluginError` is never thrown for the designated throwing URL.
        let url = installURL.resolvingSymlinksInPath()
        guard url != self.throwingURL else {
            throw MockPluginError()
        }
        return plugins[url]
    }

    public func create(parentURL: URL, name: String) throws -> Plugin? {
        // Flagged #3: MEDIUM: `create(parentURL:name:)` uses unresolved path, so plugin lookup always returns `nil`
        // `parentURL.appendingPathComponent(name).standardizedFileURL` does not resolve the `/var` → `/private/var` symlink present in `parentURL` when it originates from `FileManager.default.temporaryDirectory`. `PluginLoader.findPlugin(name:)` passes the original (unresolved) plugin directory URL as `parentURL`, so the constructed lookup key has the `/var/…` prefix while all stored keys (after the `init` fix) have the `/private/var/…` prefix. Every call therefore returns `nil` regardless of which name is requested.
        let url = parentURL.appendingPathComponent(name).resolvingSymlinksInPath()
        guard url != self.throwingURL else {
            throw MockPluginError()
        }
        return plugins[url]
    }

}
