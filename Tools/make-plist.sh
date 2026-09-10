#!/bin/bash
# Emit Info.plist for the app bundle. Kept as a script rather than a checked-in
# file so version and identifier stay single-sourced in the Makefile.
set -euo pipefail
APP="$1"; BUNDLE_ID="$2"; VERSION="$3"
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP}</string>
    <key>CFBundleDisplayName</key><string>${APP}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP}</string>
    <key>CFBundleIconFile</key><string>${APP}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- The island is the entire interface: no Dock icon, no menu bar item. -->
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Chordware listens to an audio input you choose so it can detect chords in what you are playing or listening to. Audio is analysed on your Mac and never leaves it.</string>
</dict>
</plist>
PLIST
