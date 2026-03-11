#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ICON="$ROOT_DIR/assets/branding/MuniRename_icon_source.png"
APPICON_DIR="$ROOT_DIR/MuniRename/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Source icon not found: $SOURCE_ICON" >&2
  exit 1
fi

mkdir -p "$APPICON_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SQUARE_ICON="$TMP_DIR/source-square.png"

# Convert to 1024x1024 without distortion by padding the shortest side.
sips --padToHeightWidth 1024 1024 "$SOURCE_ICON" --out "$SQUARE_ICON" >/dev/null

make_icon() {
  local size="$1"
  local filename="$2"
  sips --resampleHeightWidth "$size" "$size" "$SQUARE_ICON" --out "$APPICON_DIR/$filename" >/dev/null
}

make_icon 16   "appicon_16.png"
make_icon 32   "appicon_16@2x.png"
make_icon 32   "appicon_32.png"
make_icon 64   "appicon_32@2x.png"
make_icon 128  "appicon_128.png"
make_icon 256  "appicon_128@2x.png"
make_icon 256  "appicon_256.png"
make_icon 512  "appicon_256@2x.png"
make_icon 512  "appicon_512.png"
make_icon 1024 "appicon_512@2x.png"

cat > "$APPICON_DIR/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "appicon_16.png",     "idiom" : "mac", "size" : "16x16",   "scale" : "1x" },
    { "filename" : "appicon_16@2x.png",  "idiom" : "mac", "size" : "16x16",   "scale" : "2x" },
    { "filename" : "appicon_32.png",     "idiom" : "mac", "size" : "32x32",   "scale" : "1x" },
    { "filename" : "appicon_32@2x.png",  "idiom" : "mac", "size" : "32x32",   "scale" : "2x" },
    { "filename" : "appicon_128.png",    "idiom" : "mac", "size" : "128x128", "scale" : "1x" },
    { "filename" : "appicon_128@2x.png", "idiom" : "mac", "size" : "128x128", "scale" : "2x" },
    { "filename" : "appicon_256.png",    "idiom" : "mac", "size" : "256x256", "scale" : "1x" },
    { "filename" : "appicon_256@2x.png", "idiom" : "mac", "size" : "256x256", "scale" : "2x" },
    { "filename" : "appicon_512.png",    "idiom" : "mac", "size" : "512x512", "scale" : "1x" },
    { "filename" : "appicon_512@2x.png", "idiom" : "mac", "size" : "512x512", "scale" : "2x" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "AppIcon generated in: $APPICON_DIR"
