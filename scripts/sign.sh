#!/usr/bin/env bash
# Sign + notarize Arduino Classic.app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP="${APP:-$REPO_ROOT/dist/Arduino Classic.app}"
ENTITLEMENTS="${ENTITLEMENTS:-$REPO_ROOT/entitlements.plist}"
ZIP="${ZIP:-$REPO_ROOT/dist/Arduino Classic.zip}"

if [[ -f "$REPO_ROOT/.sign.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.sign.env"
  set +a
fi

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
APP_PASSWORD="${APP_PASSWORD:-}"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./scripts/sign.sh [sign|notarize|log SUBMISSION_ID]

  ./scripts/sign.sh              sign + notarize (default)
  ./scripts/sign.sh sign         sign only (no upload)
  ./scripts/sign.sh notarize     sign + notarize (same as default)
  ./scripts/sign.sh log ID       fetch notarization log

Env vars (set in shell or in repo-root .sign.env — see .sign.env.example):
  SIGN_IDENTITY   Developer ID Application cert name (required for sign)
  APPLE_ID        Apple ID email (required for notarize)
  TEAM_ID         10-char Team ID (required for notarize)
  APP_PASSWORD    App-specific password (required for notarize)
  APP             Path to .app (default: dist/Arduino Classic.app)

Examples:
  cp .sign.env.example .sign.env   # edit once, gitignored
  ./scripts/sign.sh
  security find-identity -v -p codesigning
  ./scripts/sign.sh log e37cdd14-4b57-42b4-b479-98c5777d771f
EOF
}

is_macho() {
  local f="$1"
  local ft
  ft="$(file -b "$f" 2>/dev/null || true)"
  [[ "$ft" == Mach-O* ]]
}

needs_entitlements() {
  local f="$1"
  case "$f" in
    */Contents/Java/jdk/bin/java|\
    */Contents/Java/jdk/lib/jspawnhelper|\
    */Contents/Java/jdk/lib/libjli.dylib)
      return 0
      ;;
  esac
  return 1
}

sign_binary() {
  local f="$1"
  local args=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
  if needs_entitlements "$f"; then
    args+=(--entitlements "$ENTITLEMENTS")
  fi
  codesign "${args[@]}" "$f"
}

check_sign_vars() {
  [[ -n "$SIGN_IDENTITY" ]] || die "set SIGN_IDENTITY (run: security find-identity -v -p codesigning)"
  [[ -d "$APP" ]] || die "app not found: $APP (run ./scripts/build.sh first)"
  [[ -f "$ENTITLEMENTS" ]] || die "entitlements missing: $ENTITLEMENTS"
}

check_notarize_vars() {
  [[ -n "$APPLE_ID" ]] || die "set APPLE_ID"
  [[ -n "$TEAM_ID" ]] || die "set TEAM_ID"
  [[ -n "$APP_PASSWORD" ]] || die "set APP_PASSWORD (create at https://appleid.apple.com)"
  [[ -d "$APP" ]] || die "app not found: $APP"
}

prepare_app_layout() {
  local legacy_jdk="$APP/Contents/PlugIns/jdk"
  local jdk_home="$APP/Contents/Java/jdk"
  if [[ -d "$legacy_jdk/Contents/Home" && ! -d "$jdk_home" ]]; then
    log "migrate JDK PlugIns/jdk → Java/jdk"
    mkdir -p "$APP/Contents/Java"
    mv "$legacy_jdk/Contents/Home" "$jdk_home"
    rm -rf "$legacy_jdk"
    sed -i '' 's|PlugIns/jdk/Contents/Home|Java/jdk|g' "$APP/Contents/MacOS/Arduino"
  elif [[ -d "$legacy_jdk/Home" && ! -d "$jdk_home" ]]; then
    log "migrate JDK PlugIns/jdk/Home → Java/jdk"
    mkdir -p "$APP/Contents/Java"
    mv "$legacy_jdk/Home" "$jdk_home"
    rm -rf "$legacy_jdk"
    sed -i '' 's|PlugIns/jdk/Home|Java/jdk|g' "$APP/Contents/MacOS/Arduino"
  fi
  rm -rf "$legacy_jdk"
  rmdir "$APP/Contents/PlugIns" 2>/dev/null || true

  find "$APP/Contents/MacOS" -name '*.orig' -delete 2>/dev/null || true
  xattr -cr "$APP" 2>/dev/null || true
}

sign_jar_natives() {
  local jar="$1"
  local tmpdir signed=0 rel

  tmpdir="$(mktemp -d)"
  unzip -q -o "$jar" -d "$tmpdir" 2>/dev/null || { rm -rf "$tmpdir"; return 0; }

  while IFS= read -r -d '' f; do
    if is_macho "$f"; then
      sign_binary "$f"
      rel="${f#"$tmpdir"/}"
      (cd "$tmpdir" && zip -q -u "$jar" "$rel")
      signed=$((signed + 1))
    fi
  done < <(find "$tmpdir" -type f -print0)

  rm -rf "$tmpdir"

  if (( signed > 0 )); then
    log "signed $signed native(s) in $(basename "$jar")"
  fi
}

sign_jars() {
  log "sign Mach-O natives inside JARs"
  while IFS= read -r -d '' jar; do
    sign_jar_natives "$jar"
  done < <(find "$APP/Contents/Java" -name '*.jar' -print0 2>/dev/null)
}

sign_macho_tree() {
  log "sign on-disk Mach-O binaries (deepest first)"
  local -a files=()
  local f

  while IFS= read -r -d '' f; do
    is_macho "$f" || continue
    case "$f" in
      *.orig) continue ;;
    esac
    files+=("$f")
  done < <(find "$APP" -type f -print0)

  if ((${#files[@]} == 0)); then
    die "no Mach-O binaries found in $APP"
  fi

  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    sign_binary "$f"
  done < <(printf '%s\n' "${files[@]}" | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)

  log "signed ${#files[@]} Mach-O file(s)"
}

sign_nested_apps() {
  local nested
  while IFS= read -r -d '' nested; do
    [[ "$nested" == "$APP" ]] && continue
    rm -rf "$nested/Contents/_CodeSignature"
    log "sign nested app $(basename "$nested")"
    codesign --force --options runtime --timestamp \
      --sign "$SIGN_IDENTITY" "$nested"
  done < <(find "$APP" -name '*.app' -type d -print0)
}

sign_app() {
  check_sign_vars
  prepare_app_layout
  sign_jars
  sign_macho_tree
  sign_nested_apps

  log "sign app bundle"
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP"

  log "verify signature"
  codesign --verify --deep --strict --verbose=2 "$APP"
  spctl -a -t exec -vv "$APP" || log "WARN: spctl assess failed (normal before notarization)"
}

notary_log() {
  local submission_id="${1:-}"
  check_notarize_vars
  [[ -n "$submission_id" ]] || die "usage: ./scripts/sign.sh log SUBMISSION_ID"
  xcrun notarytool log "$submission_id" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD"
}

notarize_app() {
  check_notarize_vars
  log "zip for notarization → $ZIP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"

  log "submit to Apple notary service"
  local output submission_id status
  if ! output="$(xcrun notarytool submit "$ZIP" \
    --wait \
    --output-format json \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" 2>&1)"; then
    echo "$output" >&2
    die "notarytool submit failed"
  fi
  echo "$output"

  submission_id="$(echo "$output" | plutil -extract id raw -o - - 2>/dev/null || true)"
  status="$(echo "$output" | plutil -extract status raw -o - - 2>/dev/null || true)"

  if [[ "$status" != "Accepted" ]]; then
    log "notarization status: ${status:-unknown}"
    if [[ -n "$submission_id" ]]; then
      log "fetching rejection log for $submission_id"
      notary_log "$submission_id" || true
    fi
    die "notarization failed — run: ./scripts/sign.sh log $submission_id"
  fi

  log "staple ticket"
  xcrun stapler staple "$APP"

  log "verify notarization"
  spctl -a -t exec -vv "$APP"
  xcrun stapler validate "$APP"
  log "done — $APP is signed + notarized"
}

run_all() {
  sign_app
  notarize_app
}

cmd="${1:-}"
case "$cmd" in
  ""|notarize|all)
    run_all
    ;;
  sign)
    sign_app
    ;;
  log)
    notary_log "${2:-}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    die "unknown command: $cmd — try: ./scripts/sign.sh, sign, notarize, log"
    ;;
esac
