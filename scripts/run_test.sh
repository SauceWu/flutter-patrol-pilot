#!/usr/bin/env bash
# run_test.sh — run a prebuilt Patrol test bundle on a specific simulator and
# emit a structured JSON result.
#
# Usage:
#   run_test.sh --sim <UDID> --target <dart_file> [--iter N]
#               [--isolate-sim] [--use-patrol]
#
# Prerequisite: `build.sh --sim <UDID>` must have produced
#   build/ios_integ/Build/Products/Runner_iphonesimulator<ver>-*.xctestrun
#
# Default execution path (recommended):
#   - Directly invokes `xcodebuild test-without-building` against the xctestrun
#     produced by `patrol build ios --simulator` (via build.sh).
#   - Disables Xcode parallel / concurrent-destination testing to prevent the
#     "Clone 1/2/3" simulator explosion (xcodebuild will otherwise clone the
#     target sim to parallelize test classes — patrol_cli 4.3.x does NOT pass
#     `-parallel-testing-enabled NO`).
#   - Uses `-destination id=<UDID>` instead of `name=<display-name>` to avoid
#     Xcode booting duplicate-named sims from other iOS runtimes.
#   - Injects `TEST_RUNNER_PATROL_TEST_PORT=8081` and
#     `TEST_RUNNER_PATROL_APP_PORT=8082` env vars so the Patrol native server
#     and Flutter app agree on ports. These match patrol_cli's defaults baked
#     into the test_bundle.dart at build time.
#
# Fallback (`--use-patrol`): invoke `patrol test --device <UDID>`. Use this
# only if the direct xcodebuild path is failing for reasons unrelated to the
# simulator-clone bug. Known caveats: patrol_cli 4.3.x may boot multiple sims
# (see reference/troubleshooting.md → Issue 15).
#
# --isolate-sim (optional, both paths): redundant safety net — shuts down any
# sim that was booted *by this run* on EXIT, and proactively shuts down
# pre-existing non-target booted sims before running. Not strictly needed for
# the direct path (parallel testing is already disabled) but harmless.
#
# Stdout: single JSON object (identical to .test-results/latest.json)
# Stderr: human-readable progress
# Exit 0: all tests passed
# Exit 1: one or more tests failed (EXPECTED — not a script error)
# Exit 2: test runner could not start (environment/config error)
# Exit 3: xcresult parsing failed
set -euo pipefail

# ── fvm auto-detection ────────────────────────────────────────────────────────
# Walk up the directory tree to locate `.fvm/flutter_sdk/bin`. Monorepos often
# put fvm config at the repo root but run tests from an `example/` subproject.
_fvm_dir="$PWD"
for _i in 1 2 3 4 5 6 7 8; do
  if [ -d "$_fvm_dir/.fvm/flutter_sdk/bin" ]; then
    export PATH="$_fvm_dir/.fvm/flutter_sdk/bin:$PATH"
    echo "[run_test] [fvm] using $_fvm_dir/.fvm/flutter_sdk" >&2
    break
  fi
  _parent="$(dirname "$_fvm_dir")"
  [ "$_parent" = "$_fvm_dir" ] && break
  _fvm_dir="$_parent"
done
unset _fvm_dir _parent _i || true

# ── pub-cache/bin auto-append (only needed for --use-patrol fallback) ────────
if [ -d "$HOME/.pub-cache/bin" ] && [[ ":$PATH:" != *":$HOME/.pub-cache/bin:"* ]]; then
  export PATH="$PATH:$HOME/.pub-cache/bin"
fi

START_SECONDS=$SECONDS

# ── arg parsing ───────────────────────────────────────────────────────────────
UDID=""
TARGET_FILE=""
ITER=1
ISOLATE_SIM=0
USE_PATROL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sim)           UDID="$2";        shift 2 ;;
    --target)        TARGET_FILE="$2"; shift 2 ;;
    --iter)          ITER="$2";        shift 2 ;;
    --isolate-sim)   ISOLATE_SIM=1;    shift ;;
    --use-patrol)    USE_PATROL=1;     shift ;;
    *) echo "[run_test] Unknown argument: $1" >&2; shift ;;
  esac
done

_emit_error_json() {
  local msg="$1"
  python3 -c "
import sys, json
print(json.dumps({
  'success': False,
  'total': 0,
  'passed': 0,
  'failed': 0,
  'skipped': 0,
  'result': 'Failed',
  'xcresult_path': None,
  'test_log_path': None,
  'iter': int(sys.argv[1]),
  'target': sys.argv[2],
  'udid': sys.argv[3],
  'duration_s': 0,
  'failures': [{
    'test_name': '__env_error__',
    'target_name': '',
    'failure_text': sys.argv[4],
    'test_identifier_string': ''
  }],
  'error': sys.argv[4]
}))" "$ITER" "$TARGET_FILE" "$UDID" "$msg"
}

if [ -z "$UDID" ] || [ -z "$TARGET_FILE" ]; then
  _emit_error_json '--sim and --target are required'
  exit 2
fi

# ── tool checks ───────────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
  printf '{"success":false,"total":0,"passed":0,"failed":0,"skipped":0,"result":"Failed","xcresult_path":null,"test_log_path":null,"iter":%s,"target":"%s","udid":"%s","duration_s":0,"failures":[],"error":"Required tool not found: python3"}\n' \
    "$ITER" "$TARGET_FILE" "$UDID"
  exit 2
fi
for tool in xcrun xcodebuild; do
  if ! command -v "$tool" &>/dev/null; then
    _emit_error_json "Required tool not found: $tool"
    exit 2
  fi
done
if [ "$USE_PATROL" = "1" ] && ! command -v patrol &>/dev/null; then
  _emit_error_json 'patrol not found — add ~/.pub-cache/bin to PATH (only needed for --use-patrol)'
  exit 2
fi

# ── directory setup ───────────────────────────────────────────────────────────
ITER_DIR=".test-results/iter-${ITER}"
mkdir -p "$ITER_DIR"
mkdir -p ".test-results"
TEST_LOG_PATH="$(pwd)/$ITER_DIR/test.log"

# ── sim preflight + post-run cleanup ──────────────────────────────────────────
# Capture target sim name + pre-existing booted set so --isolate-sim can later
# shut down only sims that this run booted. These blocks are defensive: any
# JSON/python failure must not abort the test run.

_target_sim_name="$(xcrun simctl list devices --json 2>/dev/null | \
  python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    target = sys.argv[1]
    for _, devices in data.get('devices', {}).items():
        for d in devices:
            if d.get('udid') == target:
                print(d.get('name', ''))
                sys.exit(0)
except Exception:
    pass
print('')
" "$UDID" 2>/dev/null || echo "")"

if [ -n "$_target_sim_name" ]; then
  echo "[run_test] target sim: '$_target_sim_name' (UDID $UDID)" >&2
else
  echo "[run_test] WARNING: could not resolve name for UDID $UDID — preflight partial" >&2
fi

_booted_others=$(xcrun simctl list devices --json 2>/dev/null | \
  python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    target = sys.argv[1]
    for _, devices in data.get('devices', {}).items():
        for d in devices:
            if d.get('state') == 'Booted' and d.get('udid') != target:
                print(d.get('udid', ''))
except Exception:
    pass
" "$UDID" 2>/dev/null || true)

if [ -n "$_booted_others" ]; then
  echo "[run_test] NOTE: other sims currently booted:" >&2
  echo "$_booted_others" | sed 's/^/          /' >&2
fi

_preexisting_booted="$(xcrun simctl list devices --json 2>/dev/null | \
  python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    out = []
    for _, devices in data.get('devices', {}).items():
        for d in devices:
            if d.get('state') == 'Booted':
                out.append(d.get('udid', ''))
    print(' '.join(out))
except Exception:
    pass
" 2>/dev/null || true)"

_cleanup_on_exit() {
  local ec=$?
  if [ "$ISOLATE_SIM" = "1" ]; then
    local now_booted
    now_booted=$(xcrun simctl list devices --json 2>/dev/null | \
      python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    out = []
    for _, devices in data.get('devices', {}).items():
        for d in devices:
            if d.get('state') == 'Booted':
                out.append(d.get('udid', ''))
    print(' '.join(out))
except Exception:
    pass
" 2>/dev/null || true)
    local pre=" $_preexisting_booted "
    for udid in $now_booted; do
      if [ "$udid" != "$UDID" ] && [[ "$pre" != *" $udid "* ]]; then
        echo "[run_test] --isolate-sim: shutting down $udid (spawned by this run)" >&2
        xcrun simctl shutdown "$udid" 2>/dev/null || true
      fi
    done
  fi
  exit $ec
}
trap _cleanup_on_exit EXIT

if [ "$ISOLATE_SIM" = "1" ] && [ -n "$_booted_others" ]; then
  echo "[run_test] --isolate-sim: shutting down $(echo "$_booted_others" | wc -l | tr -d ' ') non-target booted sims..." >&2
  for udid in $_booted_others; do
    xcrun simctl shutdown "$udid" 2>/dev/null || true
  done
fi

# Ensure target sim is booted (xcodebuild test-without-building will launch app
# on an already-booted sim much faster than on a cold one).
echo "[run_test] Ensuring target sim is booted..." >&2
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true

# ── run tests ────────────────────────────────────────────────────────────────
# Pre-compute xcresult path. We always write our own, in-tree, so discovery is
# deterministic (no reliance on `find build -name '*.xcresult'`).
XCRESULT_PATH="$(pwd)/$ITER_DIR/result.xcresult"
rm -rf "$XCRESULT_PATH" 2>/dev/null || true

TEST_EXIT=0
if [ "$USE_PATROL" = "1" ]; then
  # ── legacy path: patrol test ─────────────────────────────────────────────
  echo "[run_test] [legacy] patrol test --target $TARGET_FILE --device $UDID" >&2
  set +e
  patrol test --target "$TARGET_FILE" --device "$UDID" 2>&1 | tee "$TEST_LOG_PATH" >&2
  TEST_EXIT=${PIPESTATUS[0]}
  set -e
  echo "[run_test] patrol test exited $TEST_EXIT" >&2

  # For legacy path, xcresult lives in build/ios_results_*.xcresult
  if [ -d build ]; then
    _found=$(find build -maxdepth 1 -type d -name "ios_results_*.xcresult" 2>/dev/null | sort -r | head -1 || true)
    if [ -n "$_found" ]; then
      XCRESULT_PATH="$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$_found")"
    fi
  fi
else
  # ── direct path: find prebuilt xctestrun + xcodebuild test-without-building
  XCTESTRUN=""
  if [ -d build/ios_integ/Build/Products ]; then
    XCTESTRUN=$(find build/ios_integ/Build/Products -maxdepth 1 -type f \
      -name "Runner_iphonesimulator*.xctestrun" 2>/dev/null | sort -r | head -1 || true)
  fi

  if [ -z "$XCTESTRUN" ] || [ ! -f "$XCTESTRUN" ]; then
    _emit_error_json "No xctestrun found under build/ios_integ/Build/Products. Run build.sh --sim $UDID first."
    exit 2
  fi

  XCTESTRUN_ABS="$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$XCTESTRUN")"
  echo "[run_test] xctestrun: $XCTESTRUN_ABS" >&2

  # Defense-in-depth: patch ParallelizationEnabled=false in the xctestrun, even
  # though `-parallel-testing-enabled NO` on the xcodebuild invocation should
  # already prevent cloning. Harmless if already false.
  python3 - "$XCTESTRUN_ABS" <<'PY' >&2 || true
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
        print(f'[run_test] patched ParallelizationEnabled=false in {changed} xctestrun entries')
except Exception as e:
    print(f'[run_test] WARN: could not patch xctestrun: {e}')
PY

  echo "[run_test] Running: xcodebuild test-without-building (parallel disabled, only RunnerUITests)" >&2

  set +e
  TEST_RUNNER_PATROL_TEST_PORT=8081 \
  TEST_RUNNER_PATROL_APP_PORT=8082 \
  xcodebuild test-without-building \
    -xctestrun "$XCTESTRUN_ABS" \
    -only-testing RunnerUITests/RunnerUITests \
    -destination "id=$UDID" \
    -parallel-testing-enabled NO \
    -disable-concurrent-destination-testing \
    -resultBundlePath "$XCRESULT_PATH" \
    2>&1 | tee "$TEST_LOG_PATH" >&2
  TEST_EXIT=${PIPESTATUS[0]}
  set -e
  echo "[run_test] xcodebuild exited $TEST_EXIT" >&2
fi

# ── xcresult path resolution ─────────────────────────────────────────────────
if [ ! -d "$XCRESULT_PATH" ]; then
  echo "[run_test] WARNING: no xcresult at $XCRESULT_PATH (xcodebuild may have failed before writing it)" >&2
  XCRESULT_PATH=""
else
  echo "$XCRESULT_PATH" > "$ITER_DIR/xcresult.path"
  echo "$XCRESULT_PATH" > ".test-results/last_xcresult_path.txt"
  echo "[run_test] xcresult: $XCRESULT_PATH" >&2
fi

# ── xcresulttool version detection ────────────────────────────────────────────
# Gate: >= 23000 → new API (Xcode 16+ / 26.x); else → legacy
XCRESULT_VERSION=$(xcrun xcresulttool --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "0")
if [ -z "$XCRESULT_VERSION" ]; then
  XCRESULT_VERSION=0
fi

SUMMARY_JSON=""
if [ -n "$XCRESULT_PATH" ] && [ -d "$XCRESULT_PATH" ]; then
  if [ "${XCRESULT_VERSION:-0}" -ge 23000 ]; then
    echo "[run_test] xcresulttool new API (v$XCRESULT_VERSION)" >&2
    SUMMARY_JSON=$(xcrun xcresulttool get test-results summary \
      --path "$XCRESULT_PATH" \
      --compact 2>/dev/null || true)
  else
    echo "[run_test] xcresulttool legacy API (v$XCRESULT_VERSION)" >&2
    SUMMARY_JSON=$(xcrun xcresulttool get \
      --format json \
      --path "$XCRESULT_PATH" 2>/dev/null || true)
  fi
fi

# ── extract fields + build output JSON via python3 ────────────────────────────
SUMMARY_TMP="/tmp/run_test_summary_$$.json"
printf '%s' "$SUMMARY_JSON" > "$SUMMARY_TMP"

TEST_LOG_ABS="$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$TEST_LOG_PATH")"
XCRESULT_ABS="${XCRESULT_PATH:-}"

OUTPUT_JSON=$(python3 -c "
import sys, json, os

iter_n    = int(sys.argv[1])
target    = sys.argv[2]
udid      = sys.argv[3]
test_exit = int(sys.argv[4])
xcresult  = sys.argv[5] if sys.argv[5] else None
test_log  = sys.argv[6]
summary_file = sys.argv[7]

summary_raw = ''
try:
    with open(summary_file, 'r') as f:
        summary_raw = f.read().strip()
except Exception:
    pass

total = 0; passed_c = 0; failed_c = 0; skipped_c = 0
result_str = 'unknown'; duration = 0.0; failures = []

if summary_raw:
    try:
        data = json.loads(summary_raw)
        total     = data.get('totalTestCount', 0)
        passed_c  = data.get('passedTests', 0)
        failed_c  = data.get('failedTests', 0)
        skipped_c = data.get('skippedTests', 0)
        result_str = data.get('result', 'unknown')
        start_t   = data.get('startTime', 0)
        finish_t  = data.get('finishTime', 0)
        if finish_t and start_t:
            duration = round(finish_t - start_t, 1)

        raw_tf = data.get('testFailures', None)
        if isinstance(raw_tf, list):
            tf_list = raw_tf
        elif isinstance(raw_tf, dict):
            tf_list = [raw_tf]
        else:
            tf_list = []

        for tf in tf_list:
            failures.append({
                'test_name': tf.get('testName', ''),
                'target_name': tf.get('targetName', ''),
                'failure_text': tf.get('failureText', ''),
                'test_identifier_string': tf.get('testIdentifierString', '')
            })
    except (json.JSONDecodeError, KeyError, TypeError):
        pass

# total==0 guard: 0 tests ran — split into two sub-cases so agent can triage:
#   - test_exit == 0 → runner exited clean but discovered nothing (target/patrolTest usage)
#   - test_exit != 0 → test infrastructure crashed before tests ran (xcodebuild 70, signing,
#     RunnerUITests target missing, UI test runner failed to launch)
# Both are 5-A per failure-triage.md.
if total == 0 and test_exit == 0:
    result_str = 'Failed'
    failures = [{
        'test_name': '__silent_failure__',
        'target_name': '',
        'failure_text': 'xcodebuild/patrol exited 0 but 0 tests ran — check --target path and patrolTest() usage',
        'test_identifier_string': ''
    }]
elif total == 0 and test_exit != 0:
    result_str = 'Failed'
    # When 0 tests run, the real error is in xcresult ResultIssueSummaries,
    # not in testFailures (which is empty). Extract it so the agent sees
    # the actual cause (e.g. 'RunnerUITests isn't a member of the specified
    # test plan or scheme', 'RunnerUITests target missing from scheme').
    issue_msg = ''
    if xcresult and os.path.isdir(xcresult):
        try:
            import subprocess
            obj = subprocess.run(
                ['xcrun', 'xcresulttool', 'get', 'object',
                 '--legacy', '--format', 'json', '--path', xcresult],
                capture_output=True, text=True, timeout=15
            )
            if obj.returncode == 0 and obj.stdout:
                od = json.loads(obj.stdout)
                errs = (od.get('issues', {})
                          .get('errorSummaries', {})
                          .get('_values', []))
                if errs:
                    issue_msg = (errs[0].get('message', {})
                                        .get('_value', '') or '')
        except (subprocess.TimeoutExpired, json.JSONDecodeError,
                FileNotFoundError, KeyError, TypeError):
            pass
    base_text = (
        'xcodebuild/patrol exited ' + str(test_exit) + ' and 0 tests ran — '
        'test infrastructure failed before any test executed.'
    )
    if issue_msg:
        failure_text = (base_text + ' xcresult issue: ' + issue_msg +
                        ' See failure-triage.md 5-A testing_infra sub-category.')
    else:
        failure_text = (
            base_text + ' Common causes: xcodebuild exit 70 (signing / '
            'RunnerUITests scheme missing target), port conflict on 8081/8082, '
            'UI test runner never launched. '
            'See failure-triage.md 5-A testing_infra sub-category.'
        )
    failures = [{
        'test_name': '__testing_infra_failure__',
        'target_name': '',
        'failure_text': failure_text,
        'test_identifier_string': ''
    }]

success = (test_exit == 0 and total > 0 and failed_c == 0)

out = {
    'iter': iter_n,
    'target': target,
    'udid': udid,
    'passed': passed_c,
    'failed': failed_c,
    'skipped': skipped_c,
    'total': total,
    'duration_s': duration,
    'xcresult_path': xcresult,
    'test_log_path': test_log,
    'result': result_str,
    'success': success,
    'failures': failures
}
print(json.dumps(out))
" "$ITER" "$TARGET_FILE" "$UDID" "$TEST_EXIT" "$XCRESULT_ABS" "$TEST_LOG_ABS" "$SUMMARY_TMP")

rm -f "$SUMMARY_TMP"

# ── write output files ────────────────────────────────────────────────────────
echo "$OUTPUT_JSON" > "$ITER_DIR/test.json"
echo "$OUTPUT_JSON" > ".test-results/latest.json"

# ── stdout ────────────────────────────────────────────────────────────────────
echo "$OUTPUT_JSON"

# ── exit code ─────────────────────────────────────────────────────────────────
# Exit 1 when tests failed (EXPECTED — agent reads latest.json, not exit code)
# Exit 0 only when all tests truly passed
SUCCESS=$(echo "$OUTPUT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print('true' if d.get('success') else 'false')")
if [ "$SUCCESS" = "true" ]; then
  exit 0
else
  exit 1
fi
