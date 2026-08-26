#!/bin/bash
# Builds ClaudeUsage.app — a menu bar app showing Claude Code plan usage.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClaudeUsage"
BUNDLE="build/${APP_NAME}.app"
MACOS_DIR="${BUNDLE}/Contents/MacOS"

rm -rf build
mkdir -p "${MACOS_DIR}" "${BUNDLE}/Contents/Resources"

echo "→ Compiling…"
# main.swift must come last: top-level code has to be in the final file.
swiftc \
  -O \
  -swift-version 5 \
  -target arm64-apple-macosx13.0 \
  -framework AppKit -framework SwiftUI -framework ServiceManagement \
  -o "${MACOS_DIR}/${APP_NAME}" \
  Sources/UsageModels.swift \
  Sources/UsageService.swift \
  Sources/ClaudeGlyph.swift \
  Sources/ClaudeApp.swift \
  Sources/UsageModel.swift \
  Sources/UsageView.swift \
  Sources/main.swift

cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"

# Ad-hoc sign so the app keeps a stable identity — without this macOS treats
# each rebuild as a new app and re-prompts for Keychain access.
echo "→ Signing…"
codesign --force --sign - "${BUNDLE}" 2>/dev/null

echo "✓ Built ${BUNDLE}"
echo
echo "Run it:       open ${BUNDLE}"
echo "Install it:   cp -R ${BUNDLE} /Applications/"
