// fix-bugs: 2026-04-28 16:40 — 0 critical, 2 high, 1 medium, 0 low (3 total)
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

import ContainerPlugin
import Foundation
import Logging

public actor PluginsService {
    private let log: Logger
    private var loaded: [String: Plugin]
    private let pluginLoader: PluginLoader

    public init(pluginLoader: PluginLoader, log: Logger) {
        self.log = log
        self.loaded = [:]
        self.pluginLoader = pluginLoader
    }

    /// Load the specified plugins, or all plugins with services defined
    /// if none are explicitly specified.
    public func loadAll(
        _ plugins: [Plugin]? = nil,
        debug: Bool = false
    ) throws {
        let registerPlugins = plugins ?? pluginLoader.findPlugins()
        for plugin in registerPlugins {
            // Flagged #3: MEDIUM: `loadAll` double-registers already-loaded plugins with launchd
            // `loadAll` unconditionally called `pluginLoader.registerWithLaunchd` for every plugin in the list without checking whether the plugin was already present in `self.loaded`. Unlike the single-plugin `load(name:)` method which guards with `self.loaded[name] == nil`, `loadAll` would re-register plugins that were already loaded — either from a previous `loadAll` call or from individual `load(name:)` calls — resulting in duplicate launchd service registrations.
            guard self.loaded[plugin.name] == nil else {
                continue
            }
            try pluginLoader.registerWithLaunchd(plugin: plugin, debug: debug)
            loaded[plugin.name] = plugin
        }
    }

    /// Stop the specified plugins, or all plugins with services defined
    /// if none are explicitly specified.
    public func stopAll(_ plugins: [Plugin]? = nil) throws {
        // Flagged #1: HIGH: `stopAll` attempts to deregister plugins that were never registered
        // When called without arguments, `stopAll` defaulted to `pluginLoader.findPlugins()` which returns all discoverable plugins on disk, not just the ones currently loaded and registered with launchd. Calling `deregisterWithLaunchd` on a plugin that was never registered throws an error, and because the loop has no error handling, the first such failure causes the method to throw immediately — leaving all remaining actually-loaded plugins still running and registered.
        let deregisterPlugins = plugins ?? Array(self.loaded.values)
        for plugin in deregisterPlugins {
            try pluginLoader.deregisterWithLaunchd(plugin: plugin)
            self.loaded.removeValue(forKey: plugin.name)
        }
    }

    // MARK: XPC API surface.

    /// Load a single plugin, doing nothing if the plugin is already loaded.
    public func load(name: String, debug: Bool = false) throws {
        guard self.loaded[name] == nil else {
            return
        }
        guard let plugin = pluginLoader.findPlugin(name: name) else {
            throw Error.pluginNotFound(name)
        }
        try pluginLoader.registerWithLaunchd(plugin: plugin, debug: debug)
        self.loaded[plugin.name] = plugin
    }

    /// Get information for a loaded plugin.
    public func get(name: String) throws -> Plugin {
        guard let plugin = loaded[name] else {
            throw Error.pluginNotLoaded(name)
        }
        return plugin
    }

    /// Restart a loaded plugin.
    public func restart(name: String) throws {
        guard let plugin = self.loaded[name] else {
            throw Error.pluginNotLoaded(name)
        }
        // Flagged #2: HIGH: `restart` passes incomplete service label to `launchctl kickstart`
        // `restart` called `ServiceManager.kickstart(fullServiceLabel: plugin.getLaunchdLabel())`, but `getLaunchdLabel()` returns only the bare label (e.g. `com.apple.container.pluginname`) without the required domain prefix. `launchctl kickstart -k` expects a fully-qualified service target in `domain/service-label` format (e.g. `gui/501/com.apple.container.pluginname`). The sibling operation `deregisterWithLaunchd` in `PluginLoader` correctly constructs the full label by prepending `ServiceManager.getDomainString()` + `/`, but `restart` skipped this step.
        let domain = try ServiceManager.getDomainString()
        let fullLabel = "\(domain)/\(plugin.getLaunchdLabel())"
        try ServiceManager.kickstart(fullServiceLabel: fullLabel)
    }

    /// Unload a loaded plugin.
    public func unload(name: String) throws {
        guard let plugin = self.loaded[name] else {
            throw Error.pluginNotLoaded(name)
        }
        try pluginLoader.deregisterWithLaunchd(plugin: plugin)
        self.loaded.removeValue(forKey: plugin.name)
    }

    /// List all loaded plugins.
    public func list() throws -> [Plugin] {
        self.loaded.map { $0.value }
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case pluginNotFound(String)
        case pluginNotLoaded(String)

        public var description: String {
            switch self {
            case .pluginNotFound(let name):
                return "plugin not found: \(name)"
            case .pluginNotLoaded(let name):
                return "plugin not loaded: \(name)"
            }
        }
    }
}
