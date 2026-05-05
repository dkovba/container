#!/usr/bin/env bash
# fix-bugs: 2026-05-09 18:21 — 0 critical, 0 high, 0 medium, 1 low (1 total)
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

echo "Checking existence of hawkeye..."

if command -v .local/bin/hawkeye >/dev/null 2>&1; then
    echo "hawkeye found!"
else
    # Flagged #1: LOW: Error message incorrectly claims hawkeye was not found in PATH
    # The error message `"hawkeye not found in PATH"` is wrong. The check on line 18 uses `command -v .local/bin/hawkeye`, which — because the argument contains a `/` — bypasses PATH lookup entirely and checks for the file at that specific relative path. The message therefore misdiagnoses the failure for any user who has hawkeye in their system PATH but not at `.local/bin/hawkeye`.
    echo "hawkeye not found at .local/bin/hawkeye"
    echo "please install hawkeye. For convenience, you can run scripts/install-hawkeye.sh"
    exit 1
fi
