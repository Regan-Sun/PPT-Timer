#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
DEVELOPER_PATH="$(xcode-select -p)"

if [[ "$DEVELOPER_PATH" == "/Library/Developer/CommandLineTools" ]]; then
    FRAMEWORKS_DIR="$DEVELOPER_PATH/Library/Developer/Frameworks"
    TESTING_LIB_DIR="$DEVELOPER_PATH/Library/Developer/usr/lib"
    DYLD_FRAMEWORK_PATH="$FRAMEWORKS_DIR" \
    DYLD_LIBRARY_PATH="$TESTING_LIB_DIR" \
        swift test \
            --package-path "$ROOT_DIR" \
            --disable-xctest \
            --enable-swift-testing \
            -Xswiftc -F \
            -Xswiftc "$FRAMEWORKS_DIR"
else
    swift test \
        --package-path "$ROOT_DIR" \
        --disable-xctest \
        --enable-swift-testing
fi
