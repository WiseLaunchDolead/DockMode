#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  echo "Usage: $0 /path/to/DockMode.app /path/to/DockMode.dmg" >&2
  exit 64
fi

app_path=$1
output_path=$2

if [[ ! -d "$app_path" || "${app_path:t}" != "DockMode.app" ]]; then
  echo "The first argument must be a built DockMode.app bundle." >&2
  exit 66
fi

staging_dir=$(mktemp -d /tmp/dockmode-dmg.XXXXXX)
trap 'rm -rf "$staging_dir"' EXIT

cp -R "$app_path" "$staging_dir/DockMode.app"
ln -s /Applications "$staging_dir/Applications"
mkdir -p "${output_path:h}"
rm -f "$output_path"

hdiutil create \
  -volname DockMode \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$output_path"
