#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/MuniRename.xcodeproj"
SCHEME="MuniRename"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-platform=macOS}"

if [[ ! -d "$PROJECT" ]]; then
  echo "Project not found: $PROJECT" >&2
  exit 1
fi

# Respect any Xcode already selected by CI (xcode-select or DEVELOPER_DIR).
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  ACTIVE_DEV_DIR="$(xcode-select -p)"
  if [[ "$ACTIVE_DEV_DIR" == "/Library/Developer/CommandLineTools" ]] && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  else
    export DEVELOPER_DIR="$ACTIVE_DEV_DIR"
  fi
fi

echo "Using DEVELOPER_DIR=${DEVELOPER_DIR:-$(xcode-select -p)}"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  build
