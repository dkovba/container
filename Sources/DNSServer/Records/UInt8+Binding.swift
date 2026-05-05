// fix-bugs: 2026-05-04 14:01 — 0 critical, 2 high, 0 medium, 0 low (2 total)
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

import Foundation

// TODO: This copies some of the Bindable code from Containerization,
// but we can't use Bindable as it presumes a fixed length record.
// We can look at refining this later to see if we can use some common
// bit fiddling code everywhere.

extension [UInt8] {
    /// Copy a value into the buffer at the given offset.
    /// - Returns: The new offset after writing, or nil if the buffer is too small.
    package mutating func copyIn<T>(as type: T.Type, value: T, offset: Int = 0) -> Int? {
        let size = MemoryLayout<T>.size
        guard self.count >= size + offset else {
            return nil
        }
        return self.withUnsafeMutableBytes {
            // Flagged #1 (1 of 2): HIGH: `copyIn<T>` writes through incorrectly rebound pointer, causing undefined behavior
            // `$0.baseAddress?.advanced(by: offset).assumingMemoryBound(to: T.self).pointee = value` calls `assumingMemoryBound(to: T.self)` on memory that is bound to `UInt8`. Swift's memory model requires that a pointer used to access memory of type `T` must have been originally bound to `T`; using `assumingMemoryBound` to bypass this when the memory is bound to a different type is undefined behavior and can produce incorrect code under the optimizer's strict-aliasing rules. Additionally, the write is performed through an optional chain — if `baseAddress` were nil the assignment would silently become a no-op while the function still returns a non-nil success value.
            $0.storeBytes(of: value, toByteOffset: offset, as: T.self)
            return offset + size
        }
    }

    /// Copy a value out of the buffer at the given offset.
    /// - Returns: A tuple of (new offset, value), or nil if the buffer is too small.
    package func copyOut<T>(as type: T.Type, offset: Int = 0) -> (Int, T)? {
        let size = MemoryLayout<T>.size
        guard self.count >= size + offset else {
            return nil
        }
        return self.withUnsafeBytes {
            // Flagged #1 (2 of 2)
            // Flagged #2: HIGH: `copyOut<T>` reads through incorrectly rebound pointer and has incorrect nil-fallback, causing undefined behavior and data loss
            // `$0.baseAddress?.advanced(by: offset).assumingMemoryBound(to: T.self).pointee` has the same `assumingMemoryBound` undefined-behavior issue as `copyIn<T>`. Additionally, the `guard let value = ...? else { return nil }` pattern is semantically wrong: `pointee` on `UnsafePointer<T>` is not optional, so the optional produced by the chain is `.some(pointee)` — never `.none` — meaning the `guard` can never actually return `nil` and any apparent "safety" it provides is illusory. If `baseAddress` were nil (empty buffer past the guard), Swift would instead zero-initialize a `T` and return `.some` of that garbage value rather than propagating failure.
            let value = $0.load(fromByteOffset: offset, as: T.self)
            return (offset + size, value)
        }
    }

    /// Copy a byte array into the buffer at the given offset.
    /// - Returns: The new offset after writing, or nil if the buffer is too small.
    package mutating func copyIn(buffer: [UInt8], offset: Int = 0) -> Int? {
        guard offset + buffer.count <= self.count else {
            return nil
        }
        self[offset..<offset + buffer.count] = buffer[0..<buffer.count]
        return offset + buffer.count
    }

    /// Copy bytes out of the buffer into another buffer.
    /// - Returns: The new offset after reading, or nil if the buffer is too small.
    package func copyOut(buffer: inout [UInt8], offset: Int = 0) -> Int? {
        guard offset + buffer.count <= self.count else {
            return nil
        }
        buffer[0..<buffer.count] = self[offset..<offset + buffer.count]
        return offset + buffer.count
    }
}
