#!/bin/zsh
# Builds Workspaces.app in build/. With --install, copies it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP=build/Workspaces.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Workspaces" "$APP/Contents/MacOS/Workspaces"
cp "$BIN/workspaces-hook" "$APP/Contents/MacOS/workspaces-hook"
# Only SwiftTerm's Metal renderer reads this bundle; it looks in Contents/Resources.
cp -R "$BIN/SwiftTerm_SwiftTerm.bundle" "$APP/Contents/Resources/"
# Regenerate with: swift scripts/make-icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.workspaces.app</string>
  <key>CFBundleName</key><string>Workspaces</string>
  <key>CFBundleDisplayName</key><string>Workspaces</string>
  <key>CFBundleExecutable</key><string>Workspaces</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP/Contents/MacOS/workspaces-hook"
codesign --force --sign - "$APP"
echo "Pronto: $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/Workspaces.app
  cp -R "$APP" ~/Applications/
  echo "Instalado em ~/Applications/Workspaces.app"
fi
