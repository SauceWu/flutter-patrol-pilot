---
phase: 02-scripts
plan: A
subsystem: scripts/boot_sim.sh
tags: [simulator, boot, json-output, idempotent]
dependency_graph:
  requires: [xcrun simctl, python3]
  provides: [UDID, booted simulator state]
  affects: [build.sh, run_test.sh]
tech_stack:
  added: []
  patterns: [stdout-json-only, stderr-progress, jq-with-python3-fallback, bash-SECONDS-timing]
key_files:
  created:
    - scripts/boot_sim.sh
  modified: []
decisions:
  - "jq used when available; python3 one-liner as universal fallback — avoids hard jq dependency"
  - "UDID detection uses UUID regex (8-4-4-4-12 hex), not length check — more precise"
  - "get_state() helper always re-queries simctl JSON — never parses text grep output"
  - "Poll deadline is SECONDS+30 (integer bash arithmetic), not wall-clock float"
  - "boot || true pattern makes boot idempotent — simctl exits non-zero on already-booted device"
  - "runtime field strips com.apple.CoreSimulator.SimRuntime. prefix via sed"
metrics:
  duration: "< 5 minutes"
  completed: "2026-04-24"
  tasks_completed: 1
  files_created: 1
---

# Phase 2 Plan A: boot_sim.sh Summary

**One-liner:** Idempotent iOS simulator boot via `xcrun simctl list devices --json` with jq/python3 dual-path lookup and structured JSON output on stdout.

## What Was Built

`scripts/boot_sim.sh` — 164 lines, executable. Accepts a device name (substring match, case-insensitive) or exact UDID (UUID regex detection). Emits a single JSON object to stdout on all code paths; all progress goes to stderr.

### File Path

```
scripts/boot_sim.sh
```

### Line Count

164 lines (plan minimum: 60).

## Key Implementation Decisions

### 1. jq/python3 Dual-Path

jq is detected at startup with `command -v jq`. If present, it handles JSON parsing for the lookup and state-check phases. If absent, an inline `python3 -c "..."` one-liner provides equivalent behavior. The python3 path is the fallback used when jq is not installed (Homebrew-optional environment).

**Rationale:** jq is faster and more readable; python3 is guaranteed on macOS. Never grep text output of simctl — the text format is unstable across Xcode versions.

### 2. UDID Detection via Regex

Input is tested against `^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$` before lookup. If it matches, the script does an exact UDID comparison across all runtime keys. If not, it does a case-insensitive name substring search.

**Rationale:** Regex is more precise than a length check; avoids misidentifying a device named "ABCDEF12-..." as a name query.

### 3. All Runtime Keys Iterated

Both the jq path (`to_entries[] | select(.key | contains("iOS"))`) and the python3 path (`for rkey, devs in data['devices'].items(): if 'iOS' not in rkey: continue`) traverse all runtime keys. No iOS version is hardcoded.

**Rationale:** Reference machine has both iOS-18-2 and iOS-26-4 runtime keys. Hardcoding any version would silently miss devices.

### 4. get_state() Helper Always Uses JSON

The polling loop calls `get_state()` which pipes `xcrun simctl list devices --json` through python3 to extract the state field. This is slower than grep but unambiguous and format-stable.

### 5. Timeout: 30s, Not 60s

Per CONTEXT.md locked decisions and the plan spec, the boot poll timeout is 30 seconds. The reference machine boots in < 5s (already-booted case), making this ample margin.

### 6. Security: DEVICE_INPUT Passed via sys.argv[1]

The device name/UDID is passed to python3 as a positional argument (`sys.argv[1]`), never interpolated into a shell command string unquoted. This prevents shell injection (T-02A-01 from threat model).

## Deviations from Plan

None. Script implements the exact specification from 02-A-PLAN.md Task 1. The only discretionary choices are internal (jq vs python3 path selection logic), which match the plan's stated dual-path approach.

## Verification Results

### Syntax Check
```
bash -n scripts/boot_sim.sh && echo "syntax OK"
# Output: syntax OK
```

### File Permissions
```
ls -la scripts/boot_sim.sh
# -rwxr-xr-x@ 1 stevensteven  staff  7002  Apr 24 17:10 scripts/boot_sim.sh
```

### Functional Tests (live simulator)

| Test | Input | stdout | exit |
|------|-------|--------|------|
| No args | (none) | `{"udid":null,...,"error":"Usage: boot_sim.sh <device-name-or-udid>"}` | 1 |
| Unknown device | `"NONEXISTENT-DEVICE-XXXX"` | `{"udid":null,"state":"not_found",...}` | 1 |
| Already-booted name | `"iPhone 16 Pro Max"` | `{"action":"already_running","state":"Booted",...}` | 0 |
| Already-booted UDID | `239BE50D-01D0-4083-8B4A-71154AD9451D` | `{"action":"already_running","state":"Booted",...}` | 0 |

All acceptance criteria met.

## Known Stubs

None.

## Threat Flags

No new threat surface beyond what is documented in the plan's threat model.

## Self-Check: PASSED

- [x] `scripts/boot_sim.sh` exists and is executable
- [x] `bash -n scripts/boot_sim.sh` passes
- [x] stdout contains only JSON under all tested code paths
- [x] Already-booted simulator returns `action: "already_running"`, exit 0
- [x] Unknown device returns exit 1 with `state: "not_found"` JSON
- [x] No args returns exit 1 with usage JSON
- [x] UDID passthrough resolves correctly
- [x] 164 lines (exceeds min_lines: 60)
