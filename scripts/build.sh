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
# system-wide one. Walks up the directory tree (up to 8 levels) because
# monorepos commonly put `.fvm/` at the repo root and run builds from an
# `example/` or `packages/<x>/` subdirectory.
_fvm_dir="$PWD"
for _i in 1 2 3 4 5 6 7 8; do
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

# ── pub-cache/bin auto-detection ──────────────────────────────────────────────
# `patrol_cli` is installed via `dart pub global activate`, which puts its
# executable in ~/.pub-cache/bin. That directory is NOT on PATH by default;
# pub prints a warning telling the user to add it themselves. Rather than
# fail with "command not found: patrol" when the user skipped that step,
# append ~/.pub-cache/bin to PATH if it exists.
if [ -d "$HOME/.pub-cache/bin" ] && [[ ":$PATH:" != *":$HOME/.pub-cache/bin:"* ]]; then
  export PATH="$PATH:$HOME/.pub-cache/bin"
fi

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

# ── find both .app bundles: the app-under-test (Runner.app) and the UITest
# runner app (RunnerUITests-Runner.app). The XCUITest driver launches the
# runner app, which in turn spawns XCUIApplication for the app-under-test, so
# BOTH need to be installed on the sim and BOTH need the Xcode-26 Swift Testing
# deps injected (the dyld-crash can originate from either side).
PRODUCTS_DIR="build/ios_integ/Build/Products/Debug-iphonesimulator"
APP_PATH=""          # the app-under-test (Runner.app)
RUNNER_APP_PATH=""   # the UITest runner (RunnerUITests-Runner.app)

if [ -d "$PRODUCTS_DIR/Runner.app" ]; then
  APP_PATH=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$PRODUCTS_DIR/Runner.app")
fi
if [ -d "$PRODUCTS_DIR/RunnerUITests-Runner.app" ]; then
  RUNNER_APP_PATH=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$PRODUCTS_DIR/RunnerUITests-Runner.app")
fi

if [ -z "$APP_PATH" ]; then
  # Fallback: pick the first non-"RunnerUITests" .app
  APP_PATH=$(find "$PRODUCTS_DIR" -maxdepth 1 -type d -name "*.app" 2>/dev/null \
    | grep -v "RunnerUITests" | head -1 || true)
  [ -n "$APP_PATH" ] && APP_PATH=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$APP_PATH")
fi

if [ -z "$APP_PATH" ]; then
  ELAPSED=$(( SECONDS - START_SECONDS ))
  BUILD_LOG_ABS=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$BUILD_LOG_PATH" 2>/dev/null || echo "$BUILD_LOG_PATH")
  printf '{"success":false,"udid":"%s","app_path":null,"bundle_id":null,"xcresult_path":null,"build_log_path":"%s","elapsed_s":%d,"error":{"stage":"build","summary":"Runner.app bundle not found in Debug-iphonesimulator","log_grep":[]}}\n' \
    "$UDID" "$BUILD_LOG_ABS" "$ELAPSED"
  exit 1
fi

# ── extract bundle ID from Info.plist ─────────────────────────────────────────
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist" 2>/dev/null || true)
if [ -z "$BUNDLE_ID" ]; then
  BUNDLE_ID=$(defaults read "$APP_PATH/Info.plist" CFBundleIdentifier 2>/dev/null || true)
fi
[ -z "$BUNDLE_ID" ] && BUNDLE_ID="unknown"

RUNNER_BUNDLE_ID=""
if [ -n "$RUNNER_APP_PATH" ]; then
  RUNNER_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$RUNNER_APP_PATH/Info.plist" 2>/dev/null || true)
fi

# ── Xcode 26+ Swift Testing dylib/framework injection (Issue 16) ──────────────
# Xcode 26 / Swift 6.1 added a new "Swift Testing" runtime to the XCTest stack.
# Runner.app ships with libXCTestSwiftSupport.dylib (embedded by Flutter), which
# hard-depends on:
#   - _Testing_Foundation.framework  (+ _Testing_CoreGraphics / _Testing_CoreImage
#     / _Testing_UIKit, transitively pulled by the Swift stdlib glue)
#   - lib_TestingInterop.dylib
# Neither Flutter's build pipeline (`patrol build ios` → `flutter build ios
# --debug --simulator`) nor the iOS 26.x simruntime ships these, so launching
# Runner.app under iOS 26 dyld-crashes with:
#
#     Library not loaded: @rpath/_Testing_Foundation.framework/_Testing_Foundation
#     (also: @rpath/lib_TestingInterop.dylib)
#
# XCUITest then hangs on "Wait for <bundle> to idle" for its full 6-minute
# timeout and reports "The test runner timed out while preparing to run tests."
#
# Fix: copy the Simulator platform's copies into Runner.app/Frameworks before
# `xcrun simctl install`, so the sim gets an app bundle with a self-contained
# rpath. Idempotent (checks for existing files) and a no-op on Xcode <26.
#
# See: reference/troubleshooting.md Issue 16
XCODE_PLATFORM_ROOT=$(xcrun --sdk iphonesimulator --show-sdk-platform-path 2>/dev/null || echo "")
if [ -n "$XCODE_PLATFORM_ROOT" ]; then
  XCODE_PLATFORM_FRAMEWORKS="$XCODE_PLATFORM_ROOT/Developer/Library/Frameworks"
  XCODE_PLATFORM_USRLIB="$XCODE_PLATFORM_ROOT/Developer/usr/lib"
  INJECTED=0
  for target_app in "$APP_PATH" "$RUNNER_APP_PATH"; do
    [ -z "$target_app" ] && continue
    [ ! -d "$target_app" ] && continue
    target_frameworks="$target_app/Frameworks"
    mkdir -p "$target_frameworks"
    for fw in _Testing_Foundation _Testing_CoreGraphics _Testing_CoreImage _Testing_UIKit; do
      src="$XCODE_PLATFORM_FRAMEWORKS/$fw.framework"
      dst="$target_frameworks/$fw.framework"
      if [ -d "$src" ] && [ ! -d "$dst" ]; then
        cp -R "$src" "$dst"
        echo "[build.sh] injected $fw.framework → $(basename "$target_app")" >&2
        INJECTED=$((INJECTED + 1))
      fi
    done
    for dylib in lib_TestingInterop.dylib; do
      src="$XCODE_PLATFORM_USRLIB/$dylib"
      dst="$target_frameworks/$dylib"
      if [ -f "$src" ] && [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        echo "[build.sh] injected $dylib → $(basename "$target_app")" >&2
        INJECTED=$((INJECTED + 1))
      fi
    done
  done
  [ "$INJECTED" -gt 0 ] && echo "[build.sh] Xcode-26 Swift Testing deps: injected $INJECTED file(s) across app bundles" >&2
fi

# ── install: uninstall first to avoid stale binary (Issue 8) ─────────────────
# Install BOTH the app-under-test and (if present) the UITest runner app.
# xcodebuild test-without-building needs the runner app pre-installed on the
# sim — without it, XCUI spends minutes trying to install it on its own and
# can time out before the Patrol handshake completes.
echo "[build.sh] Installing $APP_PATH → $UDID (bundle: $BUNDLE_ID)..." >&2
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP_PATH"
INSTALL_EXIT=$?

if [ "$INSTALL_EXIT" -eq 0 ] && [ -n "$RUNNER_APP_PATH" ] && [ -n "$RUNNER_BUNDLE_ID" ]; then
  echo "[build.sh] Installing $RUNNER_APP_PATH → $UDID (bundle: $RUNNER_BUNDLE_ID)..." >&2
  xcrun simctl uninstall "$UDID" "$RUNNER_BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$RUNNER_APP_PATH" || {
    echo "[build.sh] WARN: UITest runner app install returned non-zero; xcodebuild will retry" >&2
  }
fi

if [ "$INSTALL_EXIT" -ne 0 ]; then
  ELAPSED=$(( SECONDS - START_SECONDS ))
  BUILD_LOG_ABS=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$BUILD_LOG_PATH" 2>/dev/null || echo "$BUILD_LOG_PATH")
  printf '{"success":false,"udid":"%s","app_path":"%s","bundle_id":"%s","xcresult_path":null,"build_log_path":"%s","elapsed_s":%d,"error":{"stage":"install","summary":"xcrun simctl install exited with code %d","log_grep":[]}}\n' \
    "$UDID" "$APP_PATH" "$BUNDLE_ID" "$BUILD_LOG_ABS" "$ELAPSED" "$INSTALL_EXIT"
  exit 2
fi

echo "[build.sh] Install succeeded" >&2

# ── patch xctestrun to disable Xcode test parallelization ─────────────────────
# patrol_cli 4.3.x builds the xctestrun with `ParallelizationEnabled=<true/>`,
# and its own xcodebuild invocation does NOT pass `-parallel-testing-enabled NO`.
# With the default, Xcode CLONES the target simulator (producing "Clone 1/2/3"
# sims) to parallelize test methods — noisy, slow, and often causes Patrol
# native↔app port collisions. We flip the flag in the xctestrun so that
# `xcodebuild test-without-building` (in run_test.sh) starts with a safe
# default, even when parallel-testing is also disabled on the command line.
XCTESTRUN=$(find build/ios_integ/Build/Products -maxdepth 1 -type f \
  -name "Runner_iphonesimulator*.xctestrun" 2>/dev/null | sort -r | head -1 || true)
if [ -n "$XCTESTRUN" ] && [ -f "$XCTESTRUN" ]; then
  python3 - "$XCTESTRUN" <<'PY' >&2 || true
import sys, plistlib, pathlib
p = pathlib.Path(sys.argv[1])
try:
    d = plistlib.loads(p.read_bytes())
    changed = 0
    for k, v in d.items():
        if isinstance(v, dict) and v.get('ParallelizationEnabled') is not False:
            v['ParallelizationEnabled'] = False
            changed += 1
    if changed:
        p.write_bytes(plistlib.dumps(d))
        print(f'[build.sh] patched ParallelizationEnabled=false in {changed} xctestrun entries')
except Exception as e:
    print(f'[build.sh] WARN: could not patch xctestrun: {e}')
PY
fi

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
