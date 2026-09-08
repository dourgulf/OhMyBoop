#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app="$PWD/dist/OhMyBoop.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/OhMyBoop" "$app/Contents/MacOS/OhMyBoop"
# Use the standard signed-app resource directory; Catalog supports this and SwiftPM.
ditto "$binary_dir/OhMyBoop_OhMyBoop.bundle" "$app/Contents/Resources/OhMyBoop_OhMyBoop.bundle"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>OhMyBoop</string>
<key>CFBundleDisplayName</key><string>OhMyBoop</string>
<key>CFBundleIdentifier</key><string>dev.lidawen.OhMyBoop</string>
<key>CFBundleExecutable</key><string>OhMyBoop</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
print "Built: $app"
