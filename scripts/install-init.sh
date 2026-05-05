#! /bin/bash -e
# fix-bugs: 2026-05-09 18:47 — 0 critical, 1 high, 1 medium, 0 low (2 total)
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

usage() {
    cat <<EOF
Usage: $(basename "$0") [-a APP_ROOT | --app-root APP_ROOT] [-l LOG_ROOT | --log-root LOG_ROOT] [-h | --help]

Install the init image for container system.

Options:
    -a, --app-root APP_ROOT    Install the init image under the APP_ROOT path
    -l, --log-root LOG_ROOT    Install the init image under the LOG_ROOT path
    -h, --help                 Show this help message

EOF
    # Flagged #2 (1 of 4): MEDIUM: `usage()` always exits 0, masking argument errors
    # `usage()` unconditionally calls `exit 0`. When `usage` is invoked after printing an error (invalid or missing argument), the script exits successfully, hiding the failure from callers and any wrapping automation that checks the exit code.
    exit "${1:-0}"
}

# Parse command line options
START_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--app-root)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Option $1 requires an argument." >&2
                # Flagged #2 (2 of 4)
                usage 1
            fi
            START_ARGS+=(--app-root "$2")
            shift 2
            ;;
        -l|--log-root)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Option $1 requires an argument." >&2
                # Flagged #2 (3 of 4)
                usage 1
            fi
            START_ARGS+=(--log-root "$2")
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Invalid option: $1" >&2
            # Flagged #2 (4 of 4)
            usage 1
            ;;
    esac
done

SWIFT="/usr/bin/swift"
IMAGE_NAME="vminit:latest"

CONTAINERIZATION_VERSION="$(${SWIFT} package show-dependencies --format json | jq -r '.dependencies[] | select(.identity == "containerization") | .version')"
if [ "${CONTAINERIZATION_VERSION}" == "unspecified" ] ; then
	CONTAINERIZATION_PATH="$(${SWIFT} package show-dependencies --format json | jq -r '.dependencies[] | select(.identity == "containerization") | .path')"
	if [ ! -d "${CONTAINERIZATION_PATH}" ] ; then
		echo "editable containerization directory at ${CONTAINERIZATION_PATH} does not exist"
		exit 1
	fi
	echo "Creating InitImage"
	# Flagged #1: HIGH: Unquoted variables cause word-splitting in `make` and `cctl images save`
	# Three variables are left unquoted across two lines. On line 72, `make -C ${CONTAINERIZATION_PATH} init` leaves `$CONTAINERIZATION_PATH` unquoted: bash word-splits the path so the portion before the first space is used as the `-C` argument and the remainder becomes spurious make targets. On line 73, `${CONTAINERIZATION_PATH}/bin/cctl images save -o /tmp/init.tar ${IMAGE_NAME}` is unquoted in two places: `$CONTAINERIZATION_PATH` again breaks the executable path so the command is not found, and `$IMAGE_NAME` is subject to word-splitting and pathname globbing so an image name with spaces or glob metacharacters (`*`, `?`, `[`) is passed to `cctl` as multiple garbled arguments.
	make -C "${CONTAINERIZATION_PATH}" init
	"${CONTAINERIZATION_PATH}/bin/cctl" images save -o /tmp/init.tar "${IMAGE_NAME}"

	# Sleep because commands after stop and start are racy.
	bin/container system stop
    sleep 3
	bin/container --debug system start "${START_ARGS[@]}"
	sleep 3
	bin/container i load -i /tmp/init.tar
	rm /tmp/init.tar
fi
