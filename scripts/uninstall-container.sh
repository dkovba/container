#!/bin/bash 
# fix-bugs: 2026-05-09 19:52 — 0 critical, 1 high, 4 medium, 0 low (5 total)
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

set -uo pipefail

INSTALL_DIR="/usr/local"
DELETE_DATA=
OPTS=0

usage() { 
    echo "Usage: $0 {-d | -k}"
    echo "Uninstall container" 
    echo 
    echo "Options:"
    echo "d     Delete user data directory."
    echo "k     Don't delete user data directory."
    echo 
    exit 1
}

while getopts ":dk" arg; do
    case "$arg" in
        d)
            DELETE_DATA=true
            ((OPTS+=1))
            ;;
        k)
            DELETE_DATA=false
            ((OPTS+=1))
            ;;
        *)
            echo "Invalid option: -${OPTARG}"
            usage
            ;;
    esac
done

if [ $OPTS != 1 ]; then 
    echo "Invalid number of options. Must provide either -d OR -k"
    usage
    exit 1
fi

# check if container is still running 
# Flagged #1: HIGH: `grep` pattern never matches the primary container service name
# The regex `com\.apple\.container\W` requires a non-word character immediately after `container`. In `launchctl list` output the service label is the last tab-separated field on each line, so there is no character following it when the service is `com.apple.container` exactly. Because `\W` cannot match at end-of-line (grep strips the newline before matching), the pattern silently produces no output and `CONTAINER_RUNNING` is always empty for the primary service, causing the guard check to be skipped.
CONTAINER_RUNNING=$(launchctl list | grep -e 'com\.apple\.container\b')
if [ -n "$CONTAINER_RUNNING" ]; then
    echo '`container` is still running. Please ensure the service is stopped by running `container system stop`'
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "This script requires an administrator password to remove the application files from system directories."
fi

# Flagged #2 (1 of 3): MEDIUM: FILES removal loop: scalar declaration, unquoted array expansion, and unquoted `rm` path
# Three related defects in the same loop combine to make file removal unreliable. First, `FILES` is assigned via plain command substitution (`FILES=$(pkgutil ...)`), making it a scalar string; `${FILES[@]}` on a scalar expands to the single string `${FILES[0]}`, so correct iteration happens only incidentally because unquoted expansion triggers word-splitting on newlines — any filename containing an IFS character (space, tab, or newline) is split into multiple tokens. Second, the for loop uses unquoted `for i in ${FILES[@]}`: even after `FILES` is correctly declared as an array, the missing quotes subject every element to word-splitting and glob expansion, so filenames with spaces, tabs, or glob metacharacters (`*`, `?`, `[`) are split or silently expanded to matching paths on disk. Third, `sudo rm $INSTALL_DIR/$i` on line 71 is also unquoted: the constructed path undergoes word-splitting and globbing once more before being passed to `rm`. The parallel `DIRS` variable on line 75 is correctly declared as an array with `DIRS=($(pkgutil ...))`.
FILES=($(pkgutil --only-files --files com.apple.container-installer))
# Flagged #4 (1 of 4): MEDIUM: Empty array expansion under `set -u` aborts script on bash 3.2 when `pkgutil` returns no entries
# The script uses `set -uo pipefail` with shebang `#!/bin/bash`, which on macOS invokes the system bash (version 3.2). In bash prior to 4.4, expanding an empty array using `@` or `*` as a subscript — including both `"${arr[@]}"` and `${#arr[@]}` — under `nounset` triggers a fatal "unbound variable" error. Both loops construct their lists via `arr=($(pkgutil ...))`: if `pkgutil` returns no output (e.g., the package was already partially cleaned up or its database entry is inconsistent), the array is empty. After the FILES scalar-to-array fix is applied, the FILES loop crashes at `"${FILES[@]}"`. The DIRS loop crashes at `${#DIRS[@]}` inside the `for` arithmetic header regardless, since `DIRS` has always been an array.
set +u
# Flagged #2 (2 of 3)
for i in "${FILES[@]}"; do
    # this command can fail for some of the reported files from pkgutil such as 
    # `/usr/local/bin/._uninstall-container.sh``
    # Flagged #2 (3 of 3)
    sudo rm "$INSTALL_DIR/$i" &> /dev/null
done
# Flagged #4 (2 of 4)
set -u


DIRS=($(pkgutil --only-dirs --files com.apple.container-installer))
# Flagged #4 (3 of 4)
set +u
for ((i=${#DIRS[@]}-1; i>=0; i--)); do 
    # this command will fail when trying to remove `bin` and `libexec` since those directories
    # may not be empty
    # Flagged #3: MEDIUM: Unquoted path variable in DIRS removal loop
    # `sudo rmdir $INSTALL_DIR/${DIRS[$i]}` passes the constructed directory path without quoting. The DIRS loop uses an arithmetic index so iteration itself is safe, but the unquoted `$INSTALL_DIR/${DIRS[$i]}` in the rmdir call is subject to word-splitting and glob expansion. Any directory name containing spaces, tabs, or glob metacharacters causes `rmdir` to receive incorrect or multiple arguments.
    sudo rmdir "$INSTALL_DIR/${DIRS[$i]}" &> /dev/null
done
# Flagged #4 (4 of 4)
set -u

sudo pkgutil --forget com.apple.container-installer > /dev/null
echo 'Removed `container` tool and helpers'

if [ "$DELETE_DATA" = true ]; then
    echo 'Removing `container` user data'
    # Flagged #5: MEDIUM: Unquoted `~` in `sudo rm -rf` of user data directory
    # `sudo rm -rf ~/Library/Application\ Support/com.apple.container` uses an unquoted tilde. Bash expands `~` to `$HOME` before word-splitting, so if `$HOME` contains spaces (e.g. `/Users/John Doe`) the expanded path is split into two tokens and `rm -rf` receives incorrect arguments. The backslash before the space in `Application\ Support` only escapes that one space; it does not protect the `$HOME` expansion from being word-split. Glob metacharacters in `$HOME` would also be expanded against the filesystem before being passed to `rm`.
    sudo rm -rf "$HOME/Library/Application Support/com.apple.container"
    echo 'Removing `container` user defaults'
    defaults delete com.apple.container.defaults > /dev/null 2>&1 || true
fi
