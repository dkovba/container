// fix-bugs: 2026-04-29 16:12 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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

import ContainerizationError
import ContainerizationExtras

actor AttachmentAllocator {
    private let allocator: any AddressAllocator<UInt32>
    private var hostnames: [String: UInt32] = [:]

    init(lower: UInt32, size: Int) throws {
        allocator = try UInt32.rotatingAllocator(
            lower: lower,
            size: UInt32(size)
        )
    }

    /// Allocate a network address for a host.
    func allocate(hostname: String) async throws -> UInt32 {
        // Client is responsible for ensuring two containers don't use same hostname, so provide existing IP if hostname exists
        if let index = hostnames[hostname] {
            return index
        }

        let index = try allocator.allocate()
        hostnames[hostname] = index

        return index
    }

    /// Free an allocated network address by hostname.
    @discardableResult
    func deallocate(hostname: String) async throws -> UInt32? {
        // Flagged #1 (1 of 2): MEDIUM: `deallocate()` leaks address when `release` throws
        // `hostnames.removeValue(forKey: hostname)` was called in the `guard` statement before `allocator.release(index)`, so it both looked up and removed the hostname mapping in a single step. If `allocator.release(index)` then threw an error, the hostname-to-address mapping was already deleted from `hostnames` while the address remained allocated in the underlying allocator. The leaked address could never be freed because no hostname pointed to it, and it could never be reallocated because the allocator still considered it in use.
        guard let index = hostnames[hostname] else {
            return nil
        }

        try allocator.release(index)
        // Flagged #1 (2 of 2)
        hostnames.removeValue(forKey: hostname)
        return index
    }

    /// If no addresses are allocated, prevent future allocations and return true.
    func disableAllocator() async -> Bool {
        allocator.disableAllocator()
    }

    /// Retrieve the allocator index for a hostname.
    func lookup(hostname: String) async throws -> UInt32? {
        hostnames[hostname]
    }
}
