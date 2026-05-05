// fix-bugs: 2026-05-04 18:32 — 0 critical, 1 high, 1 medium, 0 low (2 total)
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

import Containerization
import ContainerizationOCI

public typealias IO = Com_Apple_Container_Build_V1_IO
public typealias InfoRequest = Com_Apple_Container_Build_V1_InfoRequest
public typealias InfoResponse = Com_Apple_Container_Build_V1_InfoResponse
public typealias ClientStream = Com_Apple_Container_Build_V1_ClientStream
public typealias ServerStream = Com_Apple_Container_Build_V1_ServerStream
public typealias ImageTransfer = Com_Apple_Container_Build_V1_ImageTransfer
public typealias BuildTransfer = Com_Apple_Container_Build_V1_BuildTransfer

extension BuildTransfer {
    func stage() -> String? {
        let stage = self.metadata["stage"]
        return stage == "" ? nil : stage
    }

    func method() -> String? {
        let method = self.metadata["method"]
        return method == "" ? nil : method
    }

    func includePatterns() -> [String]? {
        guard let includePatternsString = self.metadata["include-patterns"] else {
            return nil
        }
        return includePatternsString == "" ? nil : includePatternsString.components(separatedBy: ",")
    }

    func followPaths() -> [String]? {
        // Flagged #1: HIGH: `followPaths()` always returns empty due to wrong metadata key
        // `BuildTransfer.followPaths()` looks up `self.metadata["followpaths"]`, but the key written by senders follows the hyphenated convention used throughout this file (`"include-patterns"`, `"stage"`, `"mode"`, etc.). The correct key is `"follow-paths"`. Because the key never matches, the `guard let` always falls through and the function always returns `nil`.
        guard let followPathString = self.metadata["follow-paths"] else {
            return nil
        }
        return followPathString == "" ? nil : followPathString.components(separatedBy: ",")
    }

    func mode() -> String? {
        // Flagged #2: MEDIUM: `BuildTransfer.mode()` returns empty string instead of `nil`
        // `BuildTransfer.mode()` returns `self.metadata["mode"]` directly. Every other string-returning method in the same `BuildTransfer` extension (`stage()`, `method()`) maps an empty-string value to `nil`. `mode()` is missing this guard, so it can return `""` when the key exists but has no value.
        let mode = self.metadata["mode"]
        return mode == "" ? nil : mode
    }

    func size() -> Int? {
        guard let sizeStr = self.metadata["size"] else {
            return nil
        }
        return sizeStr == "" ? nil : Int(sizeStr)
    }

    func offset() -> UInt64? {
        guard let offsetStr = self.metadata["offset"] else {
            return nil
        }
        return offsetStr == "" ? nil : UInt64(offsetStr)
    }

    func len() -> Int? {
        guard let lenStr = self.metadata["length"] else {
            return nil
        }
        return lenStr == "" ? nil : Int(lenStr)
    }
}

extension ImageTransfer {
    func stage() -> String? {
        self.metadata["stage"]
    }

    func method() -> String? {
        self.metadata["method"]
    }

    func ref() -> String? {
        self.metadata["ref"]
    }

    func platform() throws -> Platform? {
        let metadata = self.metadata
        guard let platform = metadata["platform"] else {
            return nil
        }
        return try Platform(from: platform)
    }

    func mode() -> String? {
        self.metadata["mode"]
    }

    func size() -> Int? {
        let metadata = self.metadata
        guard let sizeStr = metadata["size"] else {
            return nil
        }
        return Int(sizeStr)
    }

    func len() -> Int? {
        let metadata = self.metadata
        guard let lenStr = metadata["length"] else {
            return nil
        }
        return Int(lenStr)
    }

    func offset() -> UInt64? {
        let metadata = self.metadata
        guard let offsetStr = metadata["offset"] else {
            return nil
        }
        return UInt64(offsetStr)
    }
}

extension ServerStream {
    func getImageTransfer() -> ImageTransfer? {
        if case .imageTransfer(let v) = self.packetType {
            return v
        }
        return nil
    }

    func getBuildTransfer() -> BuildTransfer? {
        if case .buildTransfer(let v) = self.packetType {
            return v
        }
        return nil
    }

    func getIO() -> IO? {
        if case .io(let v) = self.packetType {
            return v
        }
        return nil
    }
}
