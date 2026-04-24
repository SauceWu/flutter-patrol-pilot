---
phase: 02-scripts
plan: D
subsystem: scripts
tags: [parse_failure, xcresulttool, triage, python]
dependency_graph:
  requires:
    - reference/failure-triage.md
  provides:
    - scripts/parse_failure.py
  affects:
    - iteration loop step [5] Triage
tech_stack:
  added: []
  patterns:
    - xcresulttool get test-results summary --compact (Xcode 16+)
    - xcresulttool get test-results test-details --compact (Xcode 16+)
    - isinstance() normalization for dict-or-list ambiguity
    - Dart VM stack frame regex
    - SDK prefix stripping (display only, not file/line derivation)
key_files:
  created:
    - scripts/parse_failure.py
  modified: []
decisions:
  - "xcresulttool version gate uses integer comparison >= 23000 on --version regex output"
  - "testFailures normalized with isinstance() — handles both dict (current schema) and list (future-proof)"
  - "file/line derived from FIRST non-SDK frame before SDK stripping (Anti-Pattern 5 compliance)"
  - "raw_stack capped at 10 user-code frames (SDK stripped for display)"
  - "signal display: canonical string for known signals; first substantive non-noise line for unknown"
  - "detail_text from TestDetails tree takes priority over summary failureText when non-empty"
  - "finder_context: widget-not-found regex on failure_text first; FINDER_CALL_RE on raw_log fallback"
  - "exit 0 for empty failures (all tests passed is valid); exit 1 for missing path/tool; exit 2 for JSON parse error"
metrics:
  duration: "< 5 minutes"
  completed: "2026-04-24"
  tasks_completed: 1
  files_created: 1
  lines_written: 486
---

# Phase 02 Plan D: parse_failure.py Summary

**One-liner:** xcresult failure extractor using xcresulttool new API (>= 23000), isinstance() testFailures normalization, and Dart SDK-frame stripping aligned to failure-triage.md signal table.

## File Created

`scripts/parse_failure.py` — 486 lines, executable (`chmod +x`).

## Implementation Details

### xcresulttool Version Detection

```python
r = subprocess.run(["xcrun", "xcresulttool", "--version"], ...)
m = re.search(r'version\s+(\d+)', r.stdout)
ver = int(m.group(1)) if m else 0
USE_NEW_API = ver >= 23000
```

Reference machine version: 24757 (Xcode 26.4) — always takes new API path. Gate threshold 23000 sourced from `reference/failure-triage.md` Appendix and `02-RESEARCH.md`.

### Signal Patterns (aligned to failure-triage.md Section 2)

All 18 signals covered, checked in priority order:

| Signal (canonical) | failure-triage.md Category |
|--------------------|---------------------------|
| WaitUntilVisibleTimeoutException | 5-B |
| WaitUntilExistsTimeoutException | 5-B |
| pumpAndSettle timed out | 5-B |
| PatrolIntegrationTestBinding | 5-B |
| TimeoutException | 5-B |
| TestFailure | 5-C |
| xcodebuild exited with code 65 | 5-A |
| xcodebuild exited with code 70 | 5-A |
| Dart compilation failed | 5-A |
| Unable to find a destination matching | 5-D |
| patrol: command not found | 5-D |
| gRPC connection refused | 5-D |
| PatrolAppService connection refused | 5-D |
| no such module | 5-A / 5-D |
| CocoaPods could not find compatible versions | 5-D |
| _pendingExceptionDetails != null | 5-E |
| com.apple.provenance | 5-D |
| flutter pub get failed | 5-D |

Unknown signals fall through to first substantive non-noise line (max 200 chars).

### isinstance() Normalization

```python
def normalize_test_failures(summary: dict) -> list:
    failures = summary.get("testFailures", None)
    if failures is None:
        return []
    elif isinstance(failures, list):
        return failures
    elif isinstance(failures, dict):
        return [failures]
    else:
        return []
```

Handles current schema (single dict) and potential future list form safely.

### SDK Frame Filtering (Anti-Pattern 5 compliance)

**Two-pass algorithm:**
1. Collect ALL Dart frames in order (SDK + user mixed) using `DART_FRAME_RE`.
2. Walk in order — first non-SDK frame encountered sets `file`/`line` reference.
3. Non-SDK frames collected into `user_frames` (displayed in `raw_stack`), capped at 10.

SDK prefixes stripped from display: `package:flutter/`, `package:flutter_test/`, `package:patrol/`, `package:patrol_finders/`, `package:test/`, `package:test_api/`, `package:stack_trace/`, `dart:`, `package:async/`.

### Output Schema (per failure object — 10 fields)

```json
{
  "test_name": "RunnerUITests.ExampleTest/testLogin()",
  "test_identifier_string": "RunnerUITests/ExampleTest/testLogin()",
  "category": null,
  "signal": "WaitUntilVisibleTimeoutException",
  "file": "lib/auth/login_screen.dart",
  "line": 42,
  "message": "...",
  "raw_stack": ["lib/auth/login_screen.dart 42:18  _LoginScreenState._onSubmit"],
  "finder_context": "No widget with text 'Login' found in the widget tree",
  "xcode_failure_text": "<raw verbatim failureText from xcresulttool>"
}
```

7 required fields present: `test_name`, `signal`, `file`, `line`, `message`, `raw_stack`, `finder_context`. Plus `test_identifier_string`, `category` (null), `xcode_failure_text`.

### Exit Codes

| Code | Condition |
|------|-----------|
| 0 | Success — empty `failures[]` is valid (no failures found) |
| 1 | xcresult path not found OR xcresulttool unavailable |
| 2 | JSON parse error from xcresulttool output |

## Verification Results

```
python3 -m py_compile scripts/parse_failure.py && echo "syntax OK"
# → syntax OK

ls -la scripts/parse_failure.py
# → -rwxr-xr-x  ...  18565  scripts/parse_failure.py

python3 scripts/parse_failure.py /nonexistent/path.xcresult; echo "exit=$?"
# → { "source": "xcresult", ..., "failures": null, "error": "xcresult path not found: ..." }
# → exit=1
```

## Deviations from Plan

None — plan executed exactly as written. The implementation follows the spec in `02-D-PLAN.md` with all locked decisions honored:
- No third-party dependencies (stdlib only: argparse, json, os, re, subprocess, sys, time)
- `isinstance()` normalization present
- `get_xcresulttool_version()` uses `>= 23000` gate
- SDK frame stripping does not affect file/line derivation
- stdout = JSON only; stderr = progress messages

## Known Stubs

None — no stub data or placeholder values in output.

## Self-Check: PASSED

- [x] `scripts/parse_failure.py` exists at correct path
- [x] `python3 -m py_compile` passes (syntax OK)
- [x] File is executable (`-rwxr-xr-x`)
- [x] Line count 486 >= min_lines 150
- [x] Exit 1 on nonexistent xcresult path verified
- [x] `failures: null` on error verified
- [x] All 7 required failure object fields present in implementation
- [x] `isinstance()` normalization in `normalize_test_failures()`
- [x] Version gate `>= 23000` in `get_xcresulttool_version()` and `get_summary()`
- [x] SDK prefix list complete (9 prefixes)
- [x] Signal patterns aligned to failure-triage.md (18 patterns + "unknown" fallback)
