---
phase: 02-scripts
plan: B
subsystem: scripts
tags: [build, patrol, ios, simulator, json]
dependency_graph:
  requires: []
  provides: [scripts/build.sh]
  affects: [scripts/run_test.sh, scripts/parse_failure.py]
tech_stack:
  added: []
  patterns: [patrol build ios --simulator, xcrun simctl install, tee redirect, PIPESTATUS, python3 json]
key_files:
  created: [scripts/build.sh]
  modified: []
decisions:
  - "tee ... >&2 pattern used so patrol output reaches stderr and build.log but never stdout"
  - "PlistBuddy primary + defaults read fallback for bundle ID extraction"
  - "Permissive error regex: grep -E '(error:|Error:|FAILED|xcodebuild: error)' with note:/warning: exclusion"
  - "Per-PID marker file /tmp/build_start_marker_$$ prevents xcresult collisions in parallel runs"
metrics:
  duration: "~2 minutes"
  completed: "2026-04-24"
  tasks_completed: 1
  files_created: 1
---

# Phase 02 Plan B: build.sh Summary

**One-liner:** patrol build ios --simulator with JSON-only stdout, full log to disk, uninstall-before-install, and python3-serialized error extraction.

## What Was Built

`scripts/build.sh` (206 lines, executable) — orchestrates `patrol build ios --simulator` for a given simulator UDID, captures the full build log to `.test-results/iter-N/build.log`, installs the resulting `.app` to the simulator via `xcrun simctl install`, and emits a single structured JSON object on stdout.

### File Created

- **`scripts/build.sh`** — patrol build + simctl install wrapper

## CLI Interface

```
scripts/build.sh --sim <UDID> [--iter N] [--target <dart_file>]
```

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--sim` | YES | — | Simulator UDID |
| `--iter` | no | `1` | Iteration number (sets iter-N subdir) |
| `--target` | no | all tests | Specific Dart test file |

## Key Implementation Decisions

### 1. stdout = JSON only (`tee ... >&2`)

patrol's build output (which goes to stdout+stderr combined via `2>&1`) is piped through `tee "$BUILD_LOG_PATH" >&2`. The `>&2` at the end of the pipeline redirects tee's stdout copy to stderr, so nothing from patrol leaks to the script's stdout. Only the final `printf '%s\n' "$SUCCESS_JSON"` line reaches stdout.

```bash
patrol build ios --simulator --device-id "$UDID" 2>&1 | tee "$BUILD_LOG_PATH" >&2
BUILD_EXIT=${PIPESTATUS[0]}
```

### 2. Error line extraction regex

The permissive form was chosen (per RESEARCH.md Claude's discretion):

```bash
grep -E '(error:|Error:|FAILED|xcodebuild: error)' "$BUILD_LOG_PATH" \
  | grep -v -E '(^[[:space:]]*(warning:|note:|ld: warning))' \
  | head -5
```

This catches Dart errors (`error: The getter '...'`), xcodebuild failures (`FAILED`), and compiler errors (`Error:`) while filtering warnings and notes. Maximum 5 lines enter the JSON.

### 3. Error stage detection

```bash
if echo "$ERROR_LINES" | grep -qE 'Dart compilation failed|error:.*\.dart'; then
  STAGE="dart_compile"
elif echo "$ERROR_LINES" | grep -q "xcodebuild exited with code 65"; then
  STAGE="xcodebuild_65"
elif echo "$ERROR_LINES" | grep -q "no such module"; then
  STAGE="cocoapods"
else
  STAGE="build"
fi
```

### 4. Bundle ID extraction

PlistBuddy is primary (more reliable for binary plists); `defaults read` is fallback:

```bash
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist" 2>/dev/null || true)
[ -z "$BUNDLE_ID" ] && BUNDLE_ID=$(defaults read "$APP_PATH/Info.plist" CFBundleIdentifier 2>/dev/null || true)
```

This is a Rule 2 (auto-add missing critical functionality) improvement over the plan's `defaults read` only — PlistBuddy handles binary plist format which `defaults read` can fail on.

### 5. Collision-safe xcresult marker

Uses per-PID temp file (`/tmp/build_start_marker_$$`) instead of a fixed path, preventing xcresult discovery collisions if multiple build.sh invocations run concurrently.

### 6. All JSON paths are absolute

All path values emitted in JSON are normalized via `python3 -c "import os,sys; print(os.path.abspath(...))"`. python3 was chosen over `realpath` for portability (realpath requires Homebrew coreutils on macOS).

## Success JSON Schema

```json
{
  "success": true,
  "udid": "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
  "app_path": "/abs/path/build/ios_integ/Build/Products/Debug-iphonesimulator/Runner.app",
  "bundle_id": "com.example.myApp",
  "xcresult_path": "/abs/path/build/ios_results_1706861394515.xcresult",
  "build_log_path": "/abs/path/.test-results/iter-1/build.log",
  "elapsed_s": 42,
  "error": null
}
```

## Failure JSON Schema

```json
{
  "success": false,
  "udid": "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX",
  "app_path": null,
  "bundle_id": null,
  "xcresult_path": null,
  "build_log_path": "/abs/path/.test-results/iter-1/build.log",
  "elapsed_s": 15,
  "error": {
    "stage": "dart_compile",
    "summary": "patrol build ios exited with code 1",
    "log_grep": [
      "error: The getter 'authService' isn't defined for the class 'LoginScreen'."
    ]
  }
}
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Build + install succeeded |
| 1 | Missing arg, missing tool, build failed, or .app not found |
| 2 | Build succeeded but `xcrun simctl install` failed |

## Deviations from Plan

### Auto-added: PlistBuddy as primary bundle ID extractor [Rule 2 - Missing Critical Functionality]

- **Found during:** Task 1 implementation
- **Issue:** `defaults read` can fail on binary plist format in some Flutter builds
- **Fix:** Added `/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier"` as the primary method, `defaults read` as fallback
- **Files modified:** scripts/build.sh (bundle ID extraction block)
- **Commit:** (included in task commit)

### Auto-added: Per-PID marker file [Rule 2 - Missing Critical Functionality]

- **Found during:** Task 1 implementation
- **Issue:** Plan used a fixed `/tmp/build_start_marker` path which would collide in parallel runs
- **Fix:** Used `/tmp/build_start_marker_$$` (PID-scoped) with cleanup on all exit paths
- **Files modified:** scripts/build.sh (MARKER variable + rm -f)
- **Commit:** (included in task commit)

## Verification Results

```
bash -n scripts/build.sh && echo "syntax OK"
# → syntax OK

ls -la scripts/build.sh
# → -rwxr-xr-x  206 lines  9525 bytes

# Missing --sim test:
bash scripts/build.sh 2>/dev/null
# → {"success":false,"udid":null,...,"error":{"stage":"build","summary":"--sim <UDID> is required","log_grep":[]}}
# exit 1

# stdout is exactly 1 JSON line:
# → STDOUT lines: 1, JSON valid, success: False
```

## Known Stubs

None — all code paths produce real output. The xcresult_path may be null on first build (no xcresult generated yet) which is expected and documented in the schema.

## Threat Flags

None beyond the plan's threat model. No new network endpoints, auth paths, or trust boundary changes introduced.

## Self-Check: PASSED

- `scripts/build.sh` exists: FOUND
- File executable: FOUND (-rwxr-xr-x)
- bash -n passes: PASSED (syntax OK)
- stdout only JSON: VERIFIED (1 line output in smoke test)
- All required JSON fields: VERIFIED (python3 validation passed)
