// fix-bugs: 2026-05-06 16:27 — 0 critical, 0 high, 1 medium, 0 low (1 total)
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

struct KeyExistsError: Error {}

class LRUCache<K: Hashable, V> {
    private class Node {
        // Flagged #1: MEDIUM: Retain cycle memory leak in `LRUCache` doubly-linked list
        // `prev` was a strong reference (`var prev: Node?`), creating retain cycles between every pair of adjacent nodes in the doubly-linked list. When the `LRUCache` instance is deallocated, internal nodes hold mutual strong references (A.next → B and B.prev → A) and never reach a reference count of zero.
        fileprivate weak var prev: Node?
        fileprivate var next: Node?
        fileprivate let key: K
        fileprivate let value: V

        init(key: K, value: V) {
            self.prev = nil
            self.next = nil
            self.key = key
            self.value = value
        }
    }

    private let size: UInt
    private var head: Node?
    private var tail: Node?
    private var members: [K: Node]

    init(size: UInt) {
        self.size = size
        self.head = nil
        self.tail = nil
        self.members = [:]
    }

    var count: Int { members.count }

    func get(_ key: K) -> V? {
        guard let node = members[key] else {
            return nil
        }
        listRemove(node: node)
        listInsert(node: node, after: tail)
        return node.value
    }

    func put(key: K, value: V) -> (K, V)? {
        let node = Node(key: key, value: value)
        var evicted: (K, V)? = nil

        if let existingNode = members[key] {
            // evict the replaced node
            listRemove(node: existingNode)
            evicted = (existingNode.key, existingNode.value)
        } else if self.count >= self.size {
            // evict the least recently used node
            evicted = evict()
        }

        // insert the new node and return any evicted node
        members[key] = node
        listInsert(node: node, after: tail)
        return evicted
    }

    private func evict() -> (K, V)? {
        guard let head else {
            return nil
        }
        let ret = (head.key, head.value)
        listRemove(node: head)
        members.removeValue(forKey: head.key)
        return ret
    }

    private func listRemove(node: Node) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            head = node.next
        }
        if let next = node.next {
            next.prev = node.prev
        } else {
            tail = node.prev
        }
    }

    private func listInsert(node: Node, after: Node?) {
        let before: Node?
        if let after {
            before = after.next
            after.next = node
        } else {
            before = head
            head = node
        }

        if let before {
            before.prev = node
        } else {
            tail = node
        }

        node.prev = after
        node.next = before
    }
}
