#!/usr/bin/env bash
# build.sh — patrol build ios + install to simulator
# Usage: build.sh --sim <UDID> [--iter N] [--target <dart_file>]
# Stdout: single JSON object (only the final JSON — no other output)
# Stderr: human-readable progress from patrol + script progress messages
# Exit 0: build + install succeeded
# Exit 1: build failed or missing required arg/tool
# Exit 2: build succeeded but install failed
# Exit 3: (reserved) xcresult not found after build — currently treated as non-fatal
set -euo pipefail

# ── fvm auto-detection ────────────────────────────────────────────────────────
# If invoked from an fvm-managed project, prepend .fvm/flutter_sdk/bin to PATH
# so `flutter` / `dart` resolve to the project-pinned version instead of the
# system-wide one. Walks up at most 5 parent dirs to find .fvm/flutter_sdk.
_fvm_dir="$PWD"
for _i in 1 2 3 4 5; do
  if [ -d "$_fvm_dir/.fvm/flutter_sdk/bin" ]; then
    export PATH="$_fvm_dir/.fvm/flutter_sdk/bin:$PATH"
    echo "[fvm] using $_fvm_dir/.fvm/flutter_sdk" >&2
    break
  fi
  _parent="$(dirname "$_fvm_dir")"
  [ "$_parent" = "$_fvm_dir" ] && break
  _fvm_dir="$_parent"
done
unset _fvm_dir _parent _i || true

START_SECONDS=$SECONDS

# ── arg parsing ────────────────────────────────────────────────────────────────
UDID=""
ITER=1
TARGET_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sim)    UDID="$2";         shift 2 ;;
    --iter)   ITER="$2";         shift 2 ;;
    --target) TARGET_FILE="$2";  shift 2 ;;
    *) echo "[build.sh] Unknown argument: $1" >&2; shift ;;
  esac
done

if [ -z "$UDID" ]; then
  printf '{"success":false,"udid":null,"app_path":null,"bundle_id":null,"xcresult_path":null,"build_log_path":null,"elapsed_s":0,"error":{"stage":"build","summary":"--sim <UDID> is required","log_grep":[]}}\n'
  exit 1
fi

# ── tool checks ────────────────────────────────────────────────────────────────
for tool in xcrun python3; do
  if ! command -v "$tool" &>/dev/null; then
    printf '{"success":false,"udid":"%s","app_path":null,"bundle_id":null,"xcresult_path":null,"build_log_path":null,"elapsed_s":0,"error":{"stage":"build","summary":"Required tool not found: %s","log_grep":[]}}\n' "$UDID" "$tool"
    exit 1
  fi
done

if ! command -v patrol &>/dev/null; then
  echo '[build.sh] patrol not in PATH — run: export PATH="$PATH:$HOME/.pub-cache/bin"' >&2
  printf '{"success":false,"udid":"%s","app_path":null,"bundle_id":null,"xcresult_path":null,"build_log_path":null,"elapsed_s":0,"error":{"stage":"build","summary":"patrol not found — add ~/.pub-cache/bin to PATH","log_grep":[]}}\n' "$UDID"
  exit 1
fi

# ── directory setup ────────────────────────────────────────────────────────────
ITER_DIR=".test-results/iter-${ITER}"
mkdir -p "$ITER_DIR"
BUILD_LOG_PATH="$(pwd)/$ITER_DIR/build.log"

# ── marker for xcresult discovery (must be before patrol runs) ─────────────────
MARKER="/tmp/build_start_marker_$$"
touch "$MARKER"

# ── build ──────────────────────────────────────────────────────────────────────
# NOTE: `patrol build ios --simulator` builds a simulator-targeted .app bundle.
# It does NOT take a --device / --device-id flag (that is a `patrol test` flag).
# Device selection happens in the install step below via `xcrun simctl install <UDID>`.
echo "[build.sh] Running patrol build ios --simulator (target UDID for install: $UDID)..." >&2

# tee writes patrol output to both the log file AND stderr.
# stdout stays clean so the final JSON is the only thing on stdout.
# Temporarily disable set -e during patrol — non-zero exit here is EXPECTED
# (build failures are the common case) and must be captured, not aborted on.
set +e
if [ -n "$TARGET_FILE" ]; then
  patrol build ios --simulator --target "$TARGET_FILE" 2>&1 | tee "$BUILD_LOG_PATH" >&2
  BUILD_EXIT=${PIPESTATUS[0]}
else
  patrol build ios --simulator 2>&1 | tee "$BUILD_LOG_PATH" >&2
  BUILD_EXIT=${PIPESTATUS[0]}
fi
set -e

echo "[build.sh] patrol build exited with code $BUILD_EXIT" >&2

# ── find xcresult (timestamped path — changes every build) ────────────────────
# NOTE: .xcresult is a directory (bundle). `ls <glob>` descends into each match
# and prefixes its contents with "<path>:" when multiple matches exist — the
# trailing colon would pollute xcresult_path. Use `find -type d` to list bundles.
XCRESULT_PATH=""
if [ -d build ]; then
  XCRESULT_PATH=$(find build -maxdepth 1 -type d -name "ios_results_*.xcresult" 2>/dev/null \
    | sort -r | head -1 || true)
fi
if [ -z "$XCRESULT_PATH" ]; then
  XCRESULT_PATH=$(find ~/Library/Developer/Xcode/DerivedData \
    -maxdepth 6 -type d -name "*.xcresult" -newer "$MARKER" 2>/dev/null \
    | sort | tail -1 || true)
fi
rm -f "$MARKER"

# Normalize to absolute path using python3
if [ -n "$XCRESULT_PATH" ]; then
  XCRESULT_PATH=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$XCRESULT_PATH" 2>/dev/null || echo "$XCRESULT_PATH")
fi

# ── handle build failure ──────────────────────────────────────────────────────
if [ "$BUILD_EXIT" -ne 0 ]; then
  # Extract first 5 meaningful error lines (excluding note: and warning:)
  ERROR_LINES=$(grep -E '(error:|Error:|FAILED|xcodebuild: error)' "$BUILD_LOG_PATH" 2>/dev/null \
    | grep -v -E '(^[[:space:]]*(warning:|note:|ld: warning))' \
    | head -5 || true)

  # Determine error stage
  STAGE="build"
  if echo "$ERROR_LINES" | grep -qE 'Dart compilation failed|error:.*\.dart'; then
    STAGE="dart_compile"
  elif echo "$ERROR_LINES" | grep -q "xcodebuild exited with code 65"; then
    STAGE="xcodebuild_65"
  elif echo "$ERROR_LINES" | grep -q "no such module"; then
    STAGE="cocoapods"
  fi

  ELAPSED=$(( SECONDS - START_SECONDS ))

  # Build log_grep JSON array using python3 for correct escaping
  LOG_GREP=$(printf '%s' "$ERROR_LINES" | python3 -c "
import sys, json
lines = [l.rstrip() for l in sys.stdin.readlines() if l.strip()]
print(json.dumps(lines))
" 2>/dev/null || echo "[]")

  BUILD_LOG_ABS=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$BUILD_LOG_PATH" 2>/dev/null || echo "$BUILD_LOG_PATH")
  XCRESULT_JSON="null"
  [ -n "$XCRESULT_PATH" ] && XCRESULT_JSON="\"$XCRESULT_PATH\""

  python3 -c "
import sys, json
xcr = json.loads(sys.argv[6])
d = {
  'success': False,
  'udid': sys.argv[1],
  'app_path': None,
  'bundle_id': None,
  'xcresult_path': xcr,
  'build_log_path': sys.argv[2],
  'elapsed_s': int(sys.argv[3]),
  'error': {
    'stage': sys.argv[4],
    'summary': 'patrol build ios exited with code ' + sys.argv[5],
    'log_grep': json.loads(sys.argv[7])
  }
}
print(json.dumps(d))
" "$UDID" "$BUILD_LOG_ABS" "$ELAPSED" "$STAGE" "$BUILD_EXIT" "$XCRESULT_JSON" "$LOG_GREP"

  exit 1
fi

# ── find .app bundle ──────────────────────────────────────────────────────────
APP_PATH=$(find build/ios_integ/Build/Products/Debug-iphonesimulator -name "*.app" -maxdepth 1 -type d 2>/dev/null | head -1 || true)
if [ -z "$APP_PATH" ]; then
  ELAPSED=$(( SECONDS - START_SECONDS ))
  BUILD_LOG_ABS=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$BUILD_LOG_PATH" 2>/dev/null || echo "$BUILD_LOG_PATH")
  printf '{"success":false,"udid":"%s","app_path":null,"bundle_id":null,"xcresult_path":null,"build_log_path":"%s","elapsed_s":%d,"error":{"stage":"build","summary":".app bundle not found in Debug-iphonesimulator","log_grep":[]}}\n' \
    "$UDID" "$BUILD_LOG_ABS" "$ELAPSED"
  exit 1
fi
APP_PATH=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$APP_PATH" 2>/dev/null || echo "$APP_PATH")

# ── extract bundle ID from Info.plist ─────────────────────────────────────────
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist" 2>/dev/null || true)
if [ -z "$BUNDLE_ID" ]; then
  # Fallback: defaults read
  BUNDLE_ID=$(defaults read "$APP_PATH/Info.plist" CFBundleIdentifier 2>/dev/null || true)
fi
[ -z "$BUNDLE_ID" ] && BUNDLE_ID="unknown"

# ── install: uninstall first to avoid stale binary (Issue 8) ─────────────────
echo "[build.sh] Installing $APP_PATH → $UDID (bundle: $BUNDLE_ID)..." >&2
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_PATH"
INSTALL_EXIT=$?

if [ "$INSTALL_EXIT" -ne 0 ]; then
  ELAPSED=$(( SECONDS - START_SECONDS ))
  BUILD_LOG_ABS=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$BUILD_LOG_PATH" 2>/dev/null || echo "$BUILD_LOG_PATH")
  printf '{"success":false,"udid":"%s","app_path":"%s","bundle_id":"%s","xcresult_path":null,"build_log_path":"%s","elapsed_s":%d,"error":{"stage":"install","summary":"xcrun simctl install exited with code %d","log_grep":[]}}\n' \
    "$UDID" "$APP_PATH" "$BUNDLE_ID" "$BUILD_LOG_ABS" "$ELAPSED" "$INSTALL_EXIT"
  exit 2
fi

echo "[build.sh] Install succeeded" >&2

# ── write xcresult.path file for downstream scripts ───────────────────────────
[ -n "$XCRESULT_PATH" ] && printf '%s\n' "$XCRESULT_PATH" > "$ITER_DIR/xcresult.path"

ELAPSED=$(( SECONDS - START_SECONDS ))
BUILD_LOG_ABS=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$BUILD_LOG_PATH" 2>/dev/null || echo "$BUILD_LOG_PATH")

# ── emit success JSON to stdout (only output that reaches stdout) ─────────────
XCRESULT_JSON_VAL="null"
[ -n "$XCRESULT_PATH" ] && XCRESULT_JSON_VAL="\"$XCRESULT_PATH\""

SUCCESS_JSON=$(python3 -c "
import sys, json
xcr = json.loads(sys.argv[4])
d = {
  'success': True,
  'udid': sys.argv[1],
  'app_path': sys.argv[2],
  'bundle_id': sys.argv[3],
  'xcresult_path': xcr,
  'build_log_path': sys.argv[5],
  'elapsed_s': int(sys.argv[6]),
  'error': None
}
print(json.dumps(d))
" "$UDID" "$APP_PATH" "$BUNDLE_ID" "$XCRESULT_JSON_VAL" "$BUILD_LOG_ABS" "$ELAPSED")

# Write build.json audit trail (iter dir)
printf '%s\n' "$SUCCESS_JSON" > "$ITER_DIR/build.json"

# Emit to stdout — this is the ONLY stdout output
printf '%s\n' "$SUCCESS_JSON"

exit 0
