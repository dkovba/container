// fix-bugs: 2026-05-04 00:52 — 0 critical, 1 high, 0 medium, 0 low (1 total)
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

// Flagged #1 (1 of 2): HIGH: `Version.h` missing include guard causes multiple-inclusion errors
// The header had no include guard (`#ifndef`/`#define`/`#endif` wrapper). Any translation unit that includes `Version.h` more than once — directly or transitively — would reprocess all macro definitions and function declarations on every inclusion, producing redefinition diagnostics and potentially violating the one-definition rule in C++.
#ifndef VERSION_H
#define VERSION_H
#ifndef CZ_VERSION
#define CZ_VERSION "latest"
#endif

#ifndef GIT_COMMIT
#define GIT_COMMIT "unspecified"
#endif

#ifndef RELEASE_VERSION
#define RELEASE_VERSION "0.0.0"
#endif

#ifndef BUILDER_SHIM_VERSION
#define BUILDER_SHIM_VERSION "0.0.0"
#endif

const char* get_git_commit();

const char* get_release_version();

const char* get_swift_containerization_version();

const char* get_container_builder_shim_version();
// Flagged #1 (2 of 2)
#endif
