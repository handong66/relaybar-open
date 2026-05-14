#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
PACKAGE_DIR="$BUILD_DIR/package"
APP_DIR="$BUILD_DIR/RelayBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$PACKAGE_DIR/AppIcon.iconset"
EXECUTABLE_PATH="$MACOS_DIR/RelayBar"
SDK_PATH="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
DEFAULT_SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
if [[ -x "$DEFAULT_SWIFTC" ]]; then
  SWIFTC_BIN="${SWIFTC:-$DEFAULT_SWIFTC}"
else
  SWIFTC_BIN="${SWIFTC:-swiftc}"
fi
ICON_SOURCE="$ROOT_DIR/RelayBar/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
MENU_BAR_ICON_SOURCE="$ROOT_DIR/RelayBar/Assets/menuBarIconFallback.png"

typeset -a SWIFT_SOURCES
SWIFT_SOURCES=("${(@f)$(cd "$ROOT_DIR" && rg --files RelayBar -g '*.swift' | sort)}")
for i in {1..${#SWIFT_SOURCES[@]}}; do
  SWIFT_SOURCES[$i]="$ROOT_DIR/${SWIFT_SOURCES[$i]}"
done

rm -rf "$APP_DIR" "$PACKAGE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

"$SWIFTC_BIN" \
  -sdk "$SDK_PATH" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework CryptoKit \
  -lsqlite3 \
  "${SWIFT_SOURCES[@]}" \
  -o "$EXECUTABLE_PATH"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>RelayBar</string>
	<key>CFBundleExecutable</key>
	<string>RelayBar</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.handong66.relaybar</string>
	<key>CFBundleName</key>
	<string>RelayBar</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>com.relaybar.oauth</string>
			</array>
		</dict>
	</array>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.developer-tools</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

cp "$MENU_BAR_ICON_SOURCE" "$RESOURCES_DIR/menuBarIconFallback.png"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

if ! codesign --force --deep --sign - --timestamp=none --entitlements "$ROOT_DIR/RelayBar/RelayBar.entitlements" "$APP_DIR"; then
  codesign --force --deep --sign - --timestamp=none "$APP_DIR"
fi

echo "$APP_DIR"
