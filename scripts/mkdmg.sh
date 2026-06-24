#!/usr/bin/env bash
# Wrap dist/*.app in a compressed .dmg (app + Applications symlink)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="${APP:-$REPO_ROOT/dist/Arduino Classic.app}"
DMG="${DMG:-${APP%.app}.dmg}"
VOLNAME="${DMG_VOLNAME:-$(basename "$APP" .app)}"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "$APP" ]] || die "app not found: $APP (run ./scripts/build.sh first)"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

log "stage $VOLNAME"
ditto "$APP" "$stage/$(basename "$APP")"
ln -s /Applications "$stage/Applications"

rm -f "$DMG"
log "create $DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$stage" -ov -format UDZO -imagekey zlib-level=9 "$DMG"

log "done — $DMG"
