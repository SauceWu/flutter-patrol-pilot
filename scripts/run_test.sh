#!/usr/bin/env bash
# run_test.sh — patrol test runner with xcresult parsing
# Usage: run_test.sh --sim <UDID> --target <dart_file> [--iter N]
# Stdout: single JSON object (identical to .test-results/latest.json)
# Stderr: human-readable progress
# Exit 0: all tests passed
# Exit 1: one or more tests failed (EXPECTED — not a script error)
# Exit 2: patrol test could not run (environment/config error)
# Exit 3: xcresult parsing failed
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

# ── arg parsing ───────────────────────────────────────────────────────────────
UDID=""
TARGET_FILE=""
ITER=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sim)    UDID="$2";        shift 2 ;;
    --target) TARGET_FILE="$2"; shift 2 ;;
    --iter)   ITER="$2";        shift 2 ;;
    *) echo "[run_test] Unknown argument: $1" >&2; shift ;;
  esac
done

if [ -z "$UDID" ] || [ -z "$TARGET_FILE" ]; then
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
  'failures': [],
  'error': '--sim and --target are required'
}))" "$ITER" "$TARGET_FILE" "$UDID"
  exit 2
fi

# ── tool checks ───────────────────────────────────────────────────────────────
# Check python3 first using printf (no python3 available yet to emit JSON)
if ! command -v python3 &>/dev/null; then
  printf '{"success":false,"total":0,"passed":0,"failed":0,"skipped":0,"result":"Failed","xcresult_path":null,"test_log_path":null,"iter":%s,"target":"%s","udid":"%s","duration_s":0,"failures":[],"error":"Required tool not found: python3"}\n' \
    "$ITER" "$TARGET_FILE" "$UDID"
  exit 2
fi
# Check remaining required tools
for tool in xcrun; do
  if ! command -v "$tool" &>/dev/null; then
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
  'failures': [],
  'error': 'Required tool not found: ' + sys.argv[4]
}))" "$ITER" "$TARGET_FILE" "$UDID" "$tool"
    exit 2
  fi
done

if ! command -v patrol &>/dev/null; then
  echo '[run_test] patrol not in PATH — run: export PATH="$PATH:$HOME/.pub-cache/bin"' >&2
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
  'failures': [],
  'error': 'patrol not found — add ~/.pub-cache/bin to PATH'
}))" "$ITER" "$TARGET_FILE" "$UDID"
  exit 2
fi

# ── directory setup ───────────────────────────────────────────────────────────
ITER_DIR=".test-results/iter-${ITER}"
mkdir -p "$ITER_DIR"
mkdir -p ".test-results"
TEST_LOG_PATH="$(pwd)/$ITER_DIR/test.log"

# ── time marker for xcresult discovery ────────────────────────────────────────
touch /tmp/test_start_marker_$$

# ── run patrol test ───────────────────────────────────────────────────────────
# Temporarily disable set -e — non-zero exit from patrol test is EXPECTED when
# tests fail and must be captured into JSON, not aborted on.
echo "[run_test] Running: patrol test --target $TARGET_FILE --device $UDID" >&2
set +e
patrol test --target "$TARGET_FILE" --device "$UDID" 2>&1 | tee "$TEST_LOG_PATH" >&2
TEST_EXIT=${PIPESTATUS[0]}
set -e

echo "[run_test] patrol test exited with code $TEST_EXIT" >&2

# ── discover xcresult ─────────────────────────────────────────────────────────
# NOTE: .xcresult is a directory (bundle). `ls <glob>` descends into each match
# and prefixes its contents with "<path>:" when multiple matches exist.
# Use `find -type d -maxdepth 1` to list the bundles themselves, not contents.
XCRESULT_PATH=""
if [ -d build ]; then
  XCRESULT_PATH=$(find build -maxdepth 1 -type d -name "ios_results_*.xcresult" 2>/dev/null \
    | sort -r | head -1 || true)
fi
if [ -z "$XCRESULT_PATH" ]; then
  XCRESULT_PATH=$(find ~/Library/Developer/Xcode/DerivedData \
    -maxdepth 8 -type d -name "*.xcresult" -newer /tmp/test_start_marker_$$ 2>/dev/null \
    | sort | tail -1 || true)
fi
rm -f /tmp/test_start_marker_$$

if [ -n "$XCRESULT_PATH" ]; then
  XCRESULT_PATH=$(python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$XCRESULT_PATH")
  echo "$XCRESULT_PATH" > "$ITER_DIR/xcresult.path"
  echo "$XCRESULT_PATH" > ".test-results/last_xcresult_path.txt"
  echo "[run_test] xcresult found: $XCRESULT_PATH" >&2
else
  echo "[run_test] WARNING: no xcresult found" >&2
fi

# ── xcresulttool version detection ────────────────────────────────────────────
# Gate: >= 23000 → new API (Xcode 16+ / 26.x); else → legacy
XCRESULT_VERSION=$(xcrun xcresulttool --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "0")

if [ -z "$XCRESULT_VERSION" ]; then
  echo "[run_test] WARNING: xcresulttool not found — xcresult parsing unavailable" >&2
  XCRESULT_VERSION=0
fi

# ── parse xcresult summary (if available) ────────────────────────────────────
SUMMARY_JSON=""
if [ -n "$XCRESULT_PATH" ] && [ -d "$XCRESULT_PATH" ]; then
  if [ "${XCRESULT_VERSION:-0}" -ge 23000 ]; then
    echo "[run_test] Using xcresulttool new API (version $XCRESULT_VERSION)" >&2
    SUMMARY_JSON=$(xcrun xcresulttool get test-results summary \
      --path "$XCRESULT_PATH" \
      --compact 2>/dev/null || true)
  else
    echo "[run_test] Using xcresulttool legacy API (version $XCRESULT_VERSION)" >&2
    SUMMARY_JSON=$(xcrun xcresulttool get \
      --format json \
      --path "$XCRESULT_PATH" 2>/dev/null || true)
  fi
fi

# ── extract fields + build output JSON via python3 ────────────────────────────
# Pass SUMMARY_JSON via a temp file to avoid argv length limits and quoting issues
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

# Read summary JSON from temp file
summary_raw = ''
try:
    with open(summary_file, 'r') as f:
        summary_raw = f.read().strip()
except Exception:
    pass

# Parse summary JSON
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

        # Normalize testFailures — may be dict (single) or list
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
#   - test_exit == 0 → patrol exited clean but discovered nothing (target/patrolTest usage)
#   - test_exit != 0 → test infrastructure crashed before tests ran (xcodebuild 70, signing,
#     RunnerUITests target missing, UI test runner failed to launch)
# Both are 5-A per failure-triage.md (testing_infra sub-category for the second case).
if total == 0 and test_exit == 0:
    result_str = 'Failed'
    failures = [{
        'test_name': '__silent_failure__',
        'target_name': '',
        'failure_text': 'patrol test exited 0 but 0 tests ran — check --target path and patrolTest() usage',
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
        'patrol test exited ' + str(test_exit) + ' and 0 tests ran — '
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
