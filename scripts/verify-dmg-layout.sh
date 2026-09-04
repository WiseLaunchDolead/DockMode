#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 /path/to/DockMode.dmg" >&2
  exit 64
fi

dmg_path=$1
if [[ ! -f "$dmg_path" || "${dmg_path:e}" != "dmg" ]]; then
  echo "The argument must be a .dmg file." >&2
  exit 66
fi

mount_point=$(mktemp -d /tmp/dockmode-dmg-verify.XXXXXX)
cleanup() {
  hdiutil detach "$mount_point" >/dev/null 2>&1 || true
  rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$dmg_path" >/dev/null

app_path="$mount_point/DockMode.app"
if [[ ! -d "$app_path" ]]; then
  echo "DockMode.app is missing from the DMG." >&2
  exit 1
fi
if [[ ! -L "$mount_point/Applications" ]]; then
  echo "The Applications shortcut is missing from the DMG." >&2
  exit 1
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")
if [[ "$bundle_id" != "fr.wiselaunch.DockMode" ]]; then
  echo "Unexpected bundle identifier: $bundle_id" >&2
  exit 1
fi

archs=$(lipo -archs "$app_path/Contents/MacOS/DockMode")
if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
  echo "The DMG app is not universal: $archs" >&2
  exit 1
fi

echo "DockMode DMG layout verification passed."
