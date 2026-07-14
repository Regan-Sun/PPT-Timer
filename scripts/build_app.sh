#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/dist/PPTTimer.app"
CONTENTS_DIR="$APP_DIR/Contents"
ICON_FILE="$CONTENTS_DIR/Resources/PPTTimer.icns"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"

ARM_TRIPLE="arm64-apple-macosx13.0"
INTEL_TRIPLE="x86_64-apple-macosx13.0"

swift build --disable-sandbox --package-path "$ROOT_DIR" -c release --triple "$ARM_TRIPLE"
swift build --disable-sandbox --package-path "$ROOT_DIR" -c release --triple "$INTEL_TRIPLE"
ARM_BIN_DIR="$(swift build --disable-sandbox --package-path "$ROOT_DIR" -c release --triple "$ARM_TRIPLE" --show-bin-path)"
INTEL_BIN_DIR="$(swift build --disable-sandbox --package-path "$ROOT_DIR" -c release --triple "$INTEL_TRIPLE" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

lipo -create "$ARM_BIN_DIR/PPTTimer" "$INTEL_BIN_DIR/PPTTimer" -output "$CONTENTS_DIR/MacOS/PPTTimer"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/beep.mp3" "$CONTENTS_DIR/Resources/beep.mp3"
cp "$ROOT_DIR/applause.mp3" "$CONTENTS_DIR/Resources/applause.mp3"

swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICON_FILE"

chmod +x "$CONTENTS_DIR/MacOS/PPTTimer"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
