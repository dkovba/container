// fix-bugs: 2026-05-09 02:11 — 0 critical, 0 high, 5 medium, 0 low (5 total)
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
import ContainerizationOCI
import Testing

@testable import ContainerAPIClient

struct DefaultPlatformTests {

    // MARK: - fromEnvironment

    @Test
    func testFromEnvironmentWithLinuxAmd64() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "linux/amd64"]
        let result = try DefaultPlatform.fromEnvironment(environment: env)
        #expect(result != nil)
        #expect(result?.os == "linux")
        #expect(result?.architecture == "amd64")
    }

    @Test
    func testFromEnvironmentWithLinuxArm64() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "linux/arm64"]
        let result = try DefaultPlatform.fromEnvironment(environment: env)
        #expect(result != nil)
        #expect(result?.os == "linux")
        #expect(result?.architecture == "arm64")
    }

    @Test
    func testFromEnvironmentNotSet() throws {
        let env: [String: String] = [:]
        let result = try DefaultPlatform.fromEnvironment(environment: env)
        #expect(result == nil)
    }

    @Test
    func testFromEnvironmentEmptyString() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": ""]
        let result = try DefaultPlatform.fromEnvironment(environment: env)
        #expect(result == nil)
    }

    @Test
    func testFromEnvironmentInvalidPlatformThrows() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "not-a-valid-platform"]
        #expect {
            _ = try DefaultPlatform.fromEnvironment(environment: env)
        } throws: { error in
            guard let error = error as? ContainerizationError else {
                return false
            }
            return error.description.contains("CONTAINER_DEFAULT_PLATFORM")
                && error.description.contains("not-a-valid-platform")
        }
    }

    @Test
    func testFromEnvironmentIgnoresOtherVariables() throws {
        let env = ["SOME_OTHER_VAR": "linux/amd64"]
        let result = try DefaultPlatform.fromEnvironment(environment: env)
        #expect(result == nil)
    }

    @Test
    func testFromEnvironmentWithVariant() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "linux/arm/v7"]
        let result = try DefaultPlatform.fromEnvironment(environment: env)
        #expect(result != nil)
        #expect(result?.os == "linux")
        #expect(result?.architecture == "arm")
        #expect(result?.variant == "v7")
    }

    // MARK: - resolve (optional os/arch, used by image pull/push/save)

    @Test
    func testResolveExplicitPlatformWins() throws {
        // Flagged #4: MEDIUM: `testResolveExplicitPlatformWins` uses same OS in env var as explicit platform, making the OS assertion vacuously true
        // The env var was set to `"linux/arm64"`, giving it the same OS (`linux`) as the explicit `platform: "linux/amd64"` under test. The assertion `result?.os == "linux"` therefore passes whether the explicit platform's OS is used or the env var's OS leaks through, so the test cannot detect a regression where `resolve()` incorrectly uses the env var's OS instead of the explicit platform's OS.
        let env = ["CONTAINER_DEFAULT_PLATFORM": "darwin/arm64"]
        let result = try DefaultPlatform.resolve(
            platform: "linux/amd64", os: nil, arch: nil, environment: env
        )
        #expect(result != nil)
        #expect(result?.architecture == "amd64")
        #expect(result?.os == "linux")
    }

    @Test
    func testResolveExplicitArchWinsOverEnvVar() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "linux/arm64"]
        let result = try DefaultPlatform.resolve(
            platform: nil, os: nil, arch: "amd64", environment: env
        )
        #expect(result != nil)
        #expect(result?.architecture == "amd64")
        #expect(result?.os == "linux")
    }

    @Test
    func testResolveExplicitOsAndArchWinOverEnvVar() throws {
        // Flagged #3 (1 of 2): MEDIUM: `testResolveExplicitOsAndArchWinOverEnvVar` uses same OS in env var as explicit parameter and omits the OS assertion, leaving the OS half of the claimed behaviour untested
        // The env var was set to `"linux/arm64"`, giving it the same OS (`linux`) as the explicit `os: "linux"` parameter under test. The only assertion was `result?.architecture == "amd64"`; there was no assertion on `result?.os`. Because the env-var OS and the explicit OS were identical, even adding an OS assertion would have been vacuously true — the assertion would pass whether `resolve()` honoured the explicit `os` parameter or fell through to the env var.
        let env = ["CONTAINER_DEFAULT_PLATFORM": "darwin/arm64"]
        let result = try DefaultPlatform.resolve(
            platform: nil, os: "linux", arch: "amd64", environment: env
        )
        #expect(result != nil)
        // Flagged #3 (2 of 2)
        #expect(result?.os == "linux")
        #expect(result?.architecture == "amd64")
    }

    @Test
    func testResolveExplicitOsWinsOverEnvVar() throws {
        // Flagged #1: MEDIUM: `testResolveExplicitOsWinsOverEnvVar` uses same OS in env var as explicit parameter, making the assertion vacuously true
        // The env var was set to `"linux/arm64"`, giving it the same OS (`linux`) as the explicit `os: "linux"` parameter under test. The assertion `result?.os == "linux"` therefore passes whether the explicit-OS code path fires or the env-var code path fires, so the test cannot detect a regression where `resolve()` incorrectly falls through to the env var when an explicit `os` is supplied.
        let env = ["CONTAINER_DEFAULT_PLATFORM": "darwin/arm64"]
        let result = try DefaultPlatform.resolve(
            platform: nil, os: "linux", arch: nil, environment: env
        )
        #expect(result != nil)
        #expect(result?.os == "linux")
    }

    @Test
    func testResolveFallsBackToEnvVar() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "linux/amd64"]
        let result = try DefaultPlatform.resolve(
            platform: nil, os: nil, arch: nil, environment: env
        )
        #expect(result != nil)
        #expect(result?.os == "linux")
        #expect(result?.architecture == "amd64")
    }

    @Test
    func testResolveReturnsNilWithNoFlagsOrEnvVar() throws {
        let env: [String: String] = [:]
        let result = try DefaultPlatform.resolve(
            platform: nil, os: nil, arch: nil, environment: env
        )
        #expect(result == nil)
    }

    @Test
    func testResolveExplicitPlatformOverridesEverything() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "linux/arm64"]
        let result = try DefaultPlatform.resolve(
            platform: "linux/amd64", os: "linux", arch: "arm64", environment: env
        )
        #expect(result?.architecture == "amd64")
    }

    @Test
    func testResolveExplicitPlatformIgnoresInvalidEnvVar() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "garbage"]
        let result = try DefaultPlatform.resolve(
            platform: "linux/amd64", os: nil, arch: nil, environment: env
        )
        #expect(result?.architecture == "amd64")
        #expect(result?.os == "linux")
    }

    // MARK: - resolveWithDefaults (required os/arch, used by run/create)

    @Test
    func testResolveWithDefaultsExplicitPlatformWins() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "linux/arm64"]
        let result = try DefaultPlatform.resolveWithDefaults(
            platform: "linux/amd64", os: "linux", arch: "arm64", environment: env
        )
        #expect(result.architecture == "amd64")
    }

    @Test
    func testResolveWithDefaultsEnvVarOverridesDefaults() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "linux/amd64"]
        // Flagged #5: MEDIUM: `testResolveWithDefaultsEnvVarOverridesDefaults` uses same OS in env var as default `os` parameter, making the OS assertion vacuously true
        // The default `os` parameter was set to `"linux"`, which is the same OS as the env var `"linux/amd64"`. The assertion `result.os == "linux"` therefore passes whether `resolveWithDefaults` correctly uses the env var's OS or falls back to the default `os` parameter, so the test cannot detect a regression where the env var's OS is silently ignored.
        let result = try DefaultPlatform.resolveWithDefaults(
            platform: nil, os: "darwin", arch: "arm64", environment: env
        )
        #expect(result.architecture == "amd64")
        #expect(result.os == "linux")
    }

    @Test
    func testResolveWithDefaultsFallsBackToOsArch() throws {
        let env: [String: String] = [:]
        let result = try DefaultPlatform.resolveWithDefaults(
            platform: nil, os: "linux", arch: "arm64", environment: env
        )
        #expect(result.os == "linux")
        #expect(result.architecture == "arm64")
    }

    @Test
    func testResolveWithDefaultsEnvVarWithDifferentOs() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "linux/amd64"]
        // Flagged #2: MEDIUM: `testResolveWithDefaultsEnvVarWithDifferentOs` uses `Arch.hostArchitecture().rawValue` as the default arch, making the assertion vacuously true on amd64 hosts
        // The default `arch` parameter was set to `Arch.hostArchitecture().rawValue`. On an Intel (amd64) machine this evaluates to `"amd64"`, which is the same architecture as the env var `"linux/amd64"`. The assertion `result.architecture == "amd64"` therefore passes whether `resolveWithDefaults` correctly takes the env-var code path or incorrectly falls through to the `os`/`arch` defaults, so the test cannot detect a regression where the env var is silently ignored on amd64 hosts.
        let result = try DefaultPlatform.resolveWithDefaults(
            platform: nil, os: "linux", arch: "arm64", environment: env
        )
        #expect(result.architecture == "amd64")
    }

    @Test
    func testResolveWithDefaultsInvalidEnvVarThrows() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "garbage"]
        #expect {
            _ = try DefaultPlatform.resolveWithDefaults(
                platform: nil, os: "linux", arch: "arm64", environment: env
            )
        } throws: { error in
            guard let error = error as? ContainerizationError else {
                return false
            }
            return error.description.contains("CONTAINER_DEFAULT_PLATFORM")
        }
    }

    @Test
    func testResolveWithDefaultsExplicitPlatformIgnoresInvalidEnvVar() throws {
        let env = ["CONTAINER_DEFAULT_PLATFORM": "garbage"]
        let result = try DefaultPlatform.resolveWithDefaults(
            platform: "linux/amd64", os: "linux", arch: "arm64", environment: env
        )
        #expect(result.architecture == "amd64")
    }

    // MARK: - Environment variable name

    @Test
    func testEnvironmentVariableName() {
        #expect(DefaultPlatform.environmentVariable == "CONTAINER_DEFAULT_PLATFORM")
    }
}
