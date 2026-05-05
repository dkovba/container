#!/usr/bin/env bash
# fix-bugs: 2026-05-09 18:34 — 0 critical, 0 high, 1 medium, 1 low (2 total)
# Flagged #2: LOW: Trailing space in shebang causes script to fail to execute
# The shebang line is `#!/usr/bin/env bash ` with a trailing space. The kernel passes the entire string after `#!` as arguments to `execve`, so `/usr/bin/env` receives `bash ` (with the space) as the command name. Because no executable named `bash ` exists in `PATH`, the script fails to launch with "env: bash : No such file or directory".
# Copyright © 2025-2026 Apple Inc. and the container project authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if command -v .local/bin/hawkeye >/dev/null 2>&1; then
    echo "hawkeye already installed"
else
    echo "Installing hawkeye"
    export VERSION=v6.5.1
    # Flagged #1: MEDIUM: Relative `CARGO_HOME` causes hawkeye to install to wrong location
    # `CARGO_HOME=.local` passes a relative path as the cargo home directory to the hawkeye installer subprocess. The installer (cargo-binstall) changes its working directory to a temporary location during the download phase, at which point the relative path `.local` resolves against that temp directory instead of the project root. The binary is therefore installed to the wrong location (or the install fails entirely), so the subsequent `command -v .local/bin/hawkeye` check never finds it.
    curl --proto '=https' --tlsv1.2 -LsSf https://github.com/korandoru/hawkeye/releases/download/${VERSION}/hawkeye-installer.sh | CARGO_HOME="$(pwd)/.local" sh -s -- --no-modify-path
fi
