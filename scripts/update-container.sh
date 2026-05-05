#!/bin/bash
# fix-bugs: 2026-05-09 20:54 — 0 critical, 3 high, 2 medium, 1 low (6 total)
# Copyright © 2026 Apple Inc. and the container project authors.
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

set -uo pipefail

INSTALL_DIR="/usr/local"
OPTS=0
LATEST=false
VERSION=
TMP_DIR=

# Release Info
RELEASE_URL=
RELEASE_JSON=
RELEASE_VERSION=

# Package Info
PKG_URL=
PKG_FILE=
PRIMARY_PKG=
FALLBACK_PKG=

check_installed_version() {
    local target_version="$1"
    if command -v container &>/dev/null; then
        local installed_version
        installed_version=$(container --version | awk '{print $4}')
        installed_version=${installed_version%\)}
        if [[ "$installed_version" == "$target_version" ]]; then
            return 0
        fi
    fi
    return 1
}

usage() {
    echo "Usage: $0 {-v <version>}"
    echo "Update container"
    echo
    echo "Options:"
    echo "v <version>     Install a specific release version"
    echo "No argument     Defaults to latest release version"
    exit 1
}

while getopts ":v:" arg; do
    case "$arg" in
        v)
            VERSION="$OPTARG"
            ((OPTS+=1))
            ;;
        *)
            echo "Invalid option: -${OPTARG}"
            usage
            ;;
    esac
done

# Default to install the latest release version
if [ "$OPTS" -eq 0 ]; then
    LATEST=true
fi

# Check if container is still running
# Flagged #4: MEDIUM: Running-service check silently misses exact-name launchd label
# The guard that prevents updating while the container service is running uses `grep -e 'com\.apple\.container\W'`. The `\W` anchor requires a non-word character immediately after `container`. In `launchctl list` output the service label is the last field on each line; if any container service is registered under the label `com.apple.container` exactly (no dot-separated suffix), the label is followed only by a newline, which `grep` does not treat as part of the matched text. The pattern therefore never matches that label, and `CONTAINER_RUNNING` remains empty, causing the script to proceed as if the service were stopped.
CONTAINER_RUNNING=$(launchctl list | grep -E 'com\.apple\.container(\W|$)')
if [ -n "$CONTAINER_RUNNING" ]; then
    echo '`container` is still running. Please ensure the service is stopped by running `container system stop`'
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "This script requires admin privileges to update files under $INSTALL_DIR"
    # Flagged #1: HIGH: Privilege check prints warning but never exits
    # The `if [ "$EUID" -ne 0 ]` block prints a message stating that admin privileges are required, but contains no `exit` statement. Execution continues unconditionally into the rest of the script regardless of whether the user is root.
    exit 1
fi

# Flagged #3 (1 of 2): HIGH: mktemp failure silently produces empty TMP_DIR, causing package to be written to root filesystem
# `TMP_DIR=$(mktemp -d)` has no failure guard. The script does not set `-e` (errexit), so a non-zero exit from `mktemp` is silently ignored and `TMP_DIR` is left empty. The `trap` on the following line uses single quotes, so `$TMP_DIR` is not expanded until the trap fires; the empty value propagates into every subsequent use of the variable. Most critically, `PKG_FILE` is constructed as `"$TMP_DIR/$(basename "$PKG_URL")"`, which expands to a bare filename rooted at `/` (e.g. `/container-installer-signed.pkg`). Because the script has already verified it is running as root, the subsequent `curl` download writes the package directly to the root filesystem and `sudo installer` installs from that path. Additionally, `error()` is defined two lines after `mktemp`, so even if a guard were added to the existing code it could not call `error` — `error` must first be moved above the `mktemp` call.
error() { echo "Error: $*" >&2; exit 1; }

# Temporary directory creation for install/download
# Flagged #3 (2 of 2)
TMP_DIR=$(mktemp -d) || error "Failed to create temporary directory"
trap 'rm -rf "$TMP_DIR"' EXIT

# Determine the release URL and version
if [[ "$LATEST" == true ]]; then
    RELEASE_URL="https://api.github.com/repos/apple/container/releases/latest"
    # Flagged #2: HIGH: LATEST branch fetches release URL twice with no error handling on first fetch
    # In the `LATEST` branch, the release URL is fetched twice. The first fetch (line 96) pipes directly into `jq` to extract `tag_name`, discarding the response body and performing no error check: `RELEASE_VERSION=$(curl -fsSL "$RELEASE_URL" | jq -r '.tag_name')`. A network or API failure here causes the pipeline to exit non-zero silently (no `|| error` guard); `jq` receives empty input and outputs the string `"null"`, leaving `RELEASE_VERSION="null"`. Execution then falls through to a second unconditional fetch of the same URL at line 115 that does have an error check, but by then the script has already printed misleading output. Additionally, the two fetches introduce a TOCTOU window: if a new release is published between them, `RELEASE_VERSION` reflects the old release while `RELEASE_JSON` reflects the new one, causing the version-specific fallback package name (`container-$RELEASE_VERSION-installer-signed.pkg`) to be absent from the new release's asset list.
    RELEASE_VERSION=$(curl -fsSL "$RELEASE_URL" | jq -r '.tag_name') || error "Failed fetching latest release"
    if check_installed_version "$RELEASE_VERSION"; then
        echo "Container is already on latest version $RELEASE_VERSION"
        exit 0
    else
        echo "Updating to latest version $RELEASE_VERSION"
    fi
elif [[ -n "$VERSION" ]]; then
    RELEASE_URL="https://api.github.com/repos/apple/container/releases/tags/$VERSION"
    RELEASE_VERSION="$VERSION"
    if check_installed_version "$RELEASE_VERSION"; then
        echo "Container is already on version $RELEASE_VERSION"
        exit 0
    else
        echo "Updating to release version $RELEASE_VERSION"
    fi
fi

# Fetch the release json
RELEASE_JSON=$(curl -fsSL "$RELEASE_URL") || {
    # Flagged #6: LOW: Unquoted command substitution in error call subjects message to word-splitting and glob expansion
    # The error handler for the standalone `RELEASE_JSON` fetch passes the error message via an unquoted command substitution: `error $([[ "$LATEST" == true ]] && echo "Failed fetching latest release" || echo "Release '$VERSION' not found")`. Without quotes around `$()`, the shell performs word-splitting on the substituted string and then applies glob expansion to each resulting word before passing them to `error`. The `$VERSION` expansion inside the inner `echo` is already protected by the surrounding double-quoted string, but once `echo` emits its output and the subshell exits, the outer unquoted `$()` causes the full message — including any glob-special characters that `$VERSION` may have contributed — to be re-split and glob-expanded in the calling shell's context.
    error "$([[ "$LATEST" == true ]] && echo "Failed fetching latest release" || echo "Release '$VERSION' not found")"
}

# Possible package names
PRIMARY_PKG="container-installer-signed.pkg"
FALLBACK_PKG="container-$RELEASE_VERSION-installer-signed.pkg"

# Find the package URL
PKG_URL=$(echo "$RELEASE_JSON" | jq -r \
    --arg primary "$PRIMARY_PKG" \
    --arg fallback "$FALLBACK_PKG" \
    '.assets[] | select(.name == $primary or .name == $fallback) | .browser_download_url' | head -n1)
[[ -n "$PKG_URL" ]] || error "Neither $PRIMARY_PKG nor $FALLBACK_PKG found"

PKG_FILE="$TMP_DIR/$(basename "$PKG_URL")"

echo "Downloading package from: $PKG_URL..."
# Flagged #5: MEDIUM: Package download curl failure not explicitly checked
# The `curl` invocation that downloads the installer package has no error guard: `curl -fSL "$PKG_URL" -o "$PKG_FILE"`. The script does not set `-e` (errexit), so a non-zero curl exit status is silently ignored. The only downstream check is `[[ -s "$PKG_FILE" ]] || error "Downloaded package is empty"`, which detects an absent or zero-byte file but passes if any bytes were written. A network interruption mid-transfer can leave a non-empty, truncated file that satisfies `[[ -s ]]`, whereupon the corrupt package is handed to `sudo installer`, which fails with the opaque message "Installer failed" — the real cause (download error) is lost.
curl -fSL "$PKG_URL" -o "$PKG_FILE" || error "Download failed"
[[ -s "$PKG_FILE" ]] || error "Downloaded package is empty"

echo "Installing package to $INSTALL_DIR..."
sudo installer -pkg "$PKG_FILE" -target / >/dev/null 2>&1 || error "Installer failed"

echo "Installed successfully"
container --version || error "'container' command not found"
