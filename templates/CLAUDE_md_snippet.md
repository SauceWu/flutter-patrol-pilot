## Flutter iOS Testing Skill

> Copy this entire block into your project's CLAUDE.md to enable automatic Patrol test execution on iOS simulator.
> Replace `<PATH_TO_SKILL>` with the actual path to the flutter-patrol-pilot skill directory.

---

```markdown
## Flutter iOS Testing (Patrol)

**Skill location:** `<PATH_TO_SKILL>/SKILL.md`

### Activation triggers

Use the Flutter iOS testing skill when the user says:
- "run my Flutter iOS test" / "test X on simulator" / "验证这个 Flutter 功能"
- "跑通这个流程" / "帮我跑一下 Patrol 测试"
- Mentions Patrol test failures, iOS simulator testing, or asks to auto-fix Flutter tests
- Provides a `.dart` file in `patrol_test/` or describes a UI flow to test

Do NOT activate for Android-only testing, Flutter web, or non-Flutter iOS apps.

### Mandatory pre-flight checks (run once per session)

Before starting any build or test:
1. `flutter --version` — must be ≥ 3.22
2. `patrol --version` — install with `dart pub global activate patrol_cli` if missing
3. Check `pubspec.yaml` contains `patrol:` under `dev_dependencies`
4. `xcrun simctl list devices available` — at least one iOS simulator must be available

If any check fails, stop and tell the user what to install. Do NOT auto-install globally.

### Test directory convention

All Patrol tests live in `patrol_test/` (Patrol 4.x default).
- Pass `--target patrol_test/your_test.dart` to all script calls
- Do NOT use `integration_test/` (Patrol 3.x path — deprecated in 4.0)

### Iteration loop

Follow `<PATH_TO_SKILL>/reference/iteration-protocol.md` literally. The loop phases are:

| Phase | Action |
|-------|--------|
| [0] Generate | Create or load test from `templates/patrol_test_template.dart` |
| [1] Prepare | Run `scripts/boot_sim.sh <device>` — get UDID |
| [2] Build | Run `scripts/build.sh --sim <UDID>` |
| [3] Install | Included in build.sh |
| [4] Decide | Check build JSON: `success == false` → triage; `total == 0` → 5-A |
| [5] Triage | Run `scripts/run_test.sh --sim <UDID> --target <file>`, then classify via failure-triage.md |
| [6] Fix | Apply fix based on category — see hard rules below |
| [7] Repeat | Go to [2] — max 6 iterations |

**Status line between iterations:** `iter N/6 · build ok · X/Y tests pass · fixing 5-C in file.dart`

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/boot_sim.sh <device>` | Boot simulator idempotently, get UDID |
| `scripts/build.sh --sim <UDID>` | patrol build + install, JSON result |
| `scripts/run_test.sh --sim <UDID> --target <file>` | patrol test + xcresult parse, JSON |
| `scripts/parse_failure.py <xcresult>` | Extract structured failure signals |
| `scripts/sim_snapshot.sh --sim <UDID>` | a11y tree (default) or screenshot — only on 5-E |

All scripts: stdout = JSON only, stderr = progress. Full logs stay on disk.

### Failure category quick reference

| Category | Signal | First action |
|----------|--------|-------------|
| 5-A Build | `xcodebuild exited with code 65`, Dart compile error | Diagnose sub-cause before touching test code |
| 5-B Timeout | `WaitUntilVisibleTimeoutException`, `TimeoutException` | Get a11y tree; check `SettlePolicy.trySettle` |
| 5-C Assertion | `TestFailure: Expected: X Actual: Y` | Fix app code — NEVER change `expect()` expected value |
| 5-D Environment | Simulator not found, CocoaPods error, `patrol: command not found` | Fix environment, not code |
| 5-E Unknown | No matching signal or conflicting signals | Run `sim_snapshot.sh --tree` FIRST — then decide |

Full table: `<PATH_TO_SKILL>/reference/failure-triage.md`

### Three hard rules (non-negotiable)

1. **Never change an assertion to make a failing test pass.** Fix the app code, not the expected value.
2. **Never delete a failing test** to move on. Use `skip: 'reason'` and report it.
3. **Never skip the triage step.** Classify the failure first, every time — even if the fix seems obvious.

### Iteration limits

- **Default max = 6 iterations.**
- If the same failure category appears 3 times in a row with no progress: STOP and report.
- If 2 consecutive fixes produce the same or new failures: revert to last known-good state and report.
- When stopping: provide the failure JSON, iteration count, and a diagnosis summary.

### Token discipline

- Scripts emit JSON summaries; full logs stay on disk.
- Never dump raw `xcresult`, `xcodebuild` logs, or `simctl` output into context — grep for the error.
- Use `sim_snapshot.sh --tree` for a11y tree; use `--screenshot` only when tree is insufficient.
- One-line status between iterations: `iter N/6 · build ok · X/Y tests pass · fixing 5-C in file.dart`
```

---

> **How to use this snippet:**
> 1. Copy the markdown block above (between the ` ```markdown ``` ` fences) into your project's `CLAUDE.md`
> 2. Replace all occurrences of `<PATH_TO_SKILL>` with the absolute or relative path to the skill directory
> 3. Save `CLAUDE.md` — Claude Code will read it automatically on the next session start
