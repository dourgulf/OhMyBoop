#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodebuild -project OhMyBoop.xcodeproj -scheme OhMyBoop   -configuration Release -destination 'platform=macOS'   -derivedDataPath "$PWD/.build/xcode"   -clonedSourcePackagesDirPath "$PWD/.build/xcode-packages"   CODE_SIGN_IDENTITY=- build
app="$PWD/dist/OhMyBoop.app"
mkdir -p "${app:h}"
stage=$(mktemp -d "$PWD/dist/.app-build.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
# ditto merges directories. Stage a fresh bundle so obsolete resources cannot survive an upgrade.
ditto "$PWD/.build/xcode/Build/Products/Release/OhMyBoop.app" "$stage/OhMyBoop.app"
codesign --verify --deep --strict "$stage/OhMyBoop.app"
if [[ -e "$app" ]]; then mv "$app" "$stage/previous.app"; fi
if ! mv "$stage/OhMyBoop.app" "$app"; then
  if [[ -e "$stage/previous.app" ]]; then mv "$stage/previous.app" "$app"; fi
  exit 1
fi
print "Built: $app"
