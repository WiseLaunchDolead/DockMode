#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  echo "Usage: $0 /path/to/DockMode.app /path/to/DockMode.dmg" >&2
  exit 64
fi

app_path=$1
dmg_path=$2

codesign --verify --deep --strict --verbose=2 "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
xcrun stapler validate "$dmg_path"
lipo -archs "$app_path/Contents/MacOS/DockMode" | grep -q arm64
lipo -archs "$app_path/Contents/MacOS/DockMode" | grep -q x86_64

echo "DockMode release verification passed."
