#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project OhMyBoop.xcodeproj -scheme OhMyBoop   -configuration Release -destination 'platform=macOS'   -derivedDataPath "$PWD/.build/xcode"   -clonedSourcePackagesDirPath "$PWD/.build/xcode-packages"   CODE_SIGN_IDENTITY=- build
app="$PWD/dist/HighlighterValidation/OhMyBoop.app"
mkdir -p "${app:h}"
ditto "$PWD/.build/xcode/Build/Products/Release/OhMyBoop.app" "$app"
codesign --verify --deep --strict "$app"
print "Built: $app"
