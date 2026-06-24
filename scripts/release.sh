#!/usr/bin/env bash
# Build, sign, notarize, and pack Arduino Classic for distribution
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST="$REPO_ROOT/dist"
APP="$DIST/Arduino Classic.app"
DMG="$DIST/Arduino Classic.dmg"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh [sign-only]

  ./scripts/release.sh            build + sign + notarize + dmg (default)
  ./scripts/release.sh sign-only  build + sign + dmg (no notarization)

Requires repo-root .sign.env for signing (see .sign.env.example).
Outputs: dist/Arduino Classic.app, dist/Arduino Classic.dmg
EOF
}

finish() {
  [[ -d "$APP" ]] || die "missing app: $APP"
  log "done"
  log "  $APP"
  [[ -f "$DMG" ]] && log "  $DMG"
}

cmd="${1:-}"
case "$cmd" in
  ""|release|all)
    log "release: build → sign → notarize → dmg"
    "$SCRIPT_DIR/build.sh"
    "$SCRIPT_DIR/sign.sh"
    finish
    ;;
  sign-only)
    log "release: build → sign → dmg (skip notarization)"
    "$SCRIPT_DIR/build.sh"
    "$SCRIPT_DIR/sign.sh" sign
    "$SCRIPT_DIR/mkdmg.sh"
    finish
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    die "unknown command: $cmd — try: ./scripts/release.sh, sign-only"
    ;;
esac
