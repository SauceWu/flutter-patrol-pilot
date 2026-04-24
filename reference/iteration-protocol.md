# Iteration Protocol

This is the core state machine. Follow it literally. Do not improvise the control flow.

## State to track across iterations

Maintain (in a scratchpad or TodoWrite) a minimal JSON-ish record:

```
{
  "iter": 0,
  "max_iter": 6,
  "last_known_good_commit": "<sha or stash ref>",
  "failures": [
    { "iter": 1, "test": "login_flow", "category": "5-C", "root_cause": "null check missing in AuthService.signIn", "fix": "added null guard", "shrunk_error": true }
  ],
  "consecutive_non_shrinking_fixes": 0,
  "per_test_same_category_streak": { "login_flow/5-B": 2 }
}
```

"Shrunk error" = fewer failing tests, OR same count but new failure is clearly further along in the flow (made progress).

## The loop

### [0] Intake

- If input is Patrol `.dart` → note path, skip to [1].
- If input is natural language / Markdown → generate test from `templates/patrol_test_template.dart`. **Show it to the user. Wait for ack if the scenario is non-trivial.**

### [1] Prepare environment (idempotent — skip steps that are already satisfied)

- `scripts/boot_sim.sh <device>` — default `iPhone 16`. Returns device UDID.
- Check `flutter pub get` ran since last pubspec change.
- Record `last_known_good_commit` (current HEAD, or `git stash create` if dirty).

### [2] Build & install

- `scripts/build.sh --sim <UDID>` → runs `patrol build ios --simulator` + installs.
- On failure → category **5-A (build)**. Go to [5]. Do NOT retry build without diagnosing.

### [3] Run test

- `scripts/run_test.sh --sim <UDID> --target <test_file>`
- Script writes `.test-results/latest.json` with `{ passed, failed, skipped, failures: [...] }`.

### [4] Decide

- All pass → ✅ DONE. Report iteration count and what was changed.
- Any failure → [5].

### [5] Triage (MANDATORY — do not skip)

For each failure:

1. Extract the failure signal (error type, first stack frame, finder output) — `scripts/parse_failure.py` returns this as JSON.
2. Match against `reference/failure-triage.md` to get a category (5-A through 5-E).
3. If category is **5-E (unknown)**: take a11y tree snapshot. If still unclear after snapshot, stop and ask user.

### [6] Fix

- Apply the action prescribed by the category. **Do not apply actions from other categories.**
- Record: `{ file, lines_changed, why, expected_effect }`.
- Commit the fix with a short message (or leave staged — user's call). This lets us revert cleanly.

### [7] Loop control — evaluate BEFORE going back to [2]

Check all stop conditions. First one that trips wins:

| Condition | Action |
|---|---|
| `iter >= max_iter` | STOP. Report all fixes tried. Ask user. |
| `per_test_same_category_streak[X] >= 3` | STOP. Same category 3x means our triage is wrong or the problem is deeper. Ask user. |
| `consecutive_non_shrinking_fixes >= 2` | ROLLBACK to `last_known_good_commit`, STOP. Report. |
| Fix touched >10 files or >200 lines in one iteration | STOP. Likely over-reaching. Ask user. |
| None of the above | `iter++`, go to [2]. |

## Reporting format

When loop exits (pass, fail, or stop), emit a report like:

```
Flutter iOS test run — <test name>
Result: ✅ passed / ❌ stopped after N iterations / 🛑 rolled back

Iterations:
  1. [5-C] Fixed null check in lib/auth/auth_service.dart:42 → tests reduced 3→1
  2. [5-B] Extended timeout for network stub in test → tests 1→0 ✅

Files changed:
  - lib/auth/auth_service.dart (+3 -1)
  - integration_test/login_test.dart (+1 -1)

Next step for user: <if stopped> <what to check>
```

## Things NOT to do inside the loop

- Don't grep through all source files speculatively. Let the failure signal point you to the file.
- Don't run `flutter clean` unless build errors suggest stale caches (category 5-D tells you when).
- Don't take screenshots on every iteration. A11y tree is cheaper and usually enough.
- Don't edit the test to "match reality" when reality is the bug. See Hard Rules in SKILL.md.
