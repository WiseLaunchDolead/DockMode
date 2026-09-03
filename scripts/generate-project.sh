#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

cd "$project_dir"
xcodegen generate
