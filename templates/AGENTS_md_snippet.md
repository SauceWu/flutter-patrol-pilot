# AGENTS.md snippet — Flutter iOS Testing (Patrol)

> Copy the block below into your project's `AGENTS.md` (supported by Cursor, OpenAI Codex, and other AGENTS-aware agents).
> Replace `<PATH_TO_SKILL>` with the absolute or workspace-relative path to the cloned `flutter-patrol-pilot` skill directory.
> If your project already has `AGENTS.md`, append this as a new section; do not overwrite existing content.

---

```markdown
## Flutter iOS Testing (Patrol)

**Skill:** `<PATH_TO_SKILL>/SKILL.md` — follow literally when active.

### When this skill applies

Activate when the user says:

- "run my Flutter iOS test" / "test X on simulator" / "验证这个 Flutter 功能"
- "跑通这个流程" / "帮我跑一下 Patrol 测试"
- Mentions Patrol test failures, iOS simulator testing, or auto-fix Flutter tests
- Provides a `.dart` file in `patrol_test/` or describes a UI flow to test

Do NOT activate for Android-only testing, Flutter web, or non-Flutter iOS apps.

### Pre-flight (run once per session, cache result)

1. `flutter --version` — must be ≥ 3.22
2. `patrol --version` — install with `dart pub global activate patrol_cli` if missing
3. `pubspec.yaml` contains `patrol:` under `dev_dependencies`
4. `xcrun simctl list devices available` — at least one iOS simulator available

If any check fails, stop and tell the user what to install. Do NOT auto-install globally.

### Test directory

All Patrol tests live in `patrol_test/` (Patrol 4.x default). Do NOT use `integration_test/`.

### Iteration loop (follow `<PATH_TO_SKILL>/reference/iteration-protocol.md` literally)

```
[0] Generate test (if input is NL/Markdown) from templates/patrol_test_template.dart
[1] Prepare env  → scripts/boot_sim.sh <device>  → UDID
[2] Build        → scripts/build.sh --sim <UDID>
[3] Run test     → scripts/run_test.sh --sim <UDID> --target <file>
[4] All pass?    → DONE
[5] Triage       → classify failure via reference/failure-triage.md
[6] Fix          → apply action for that category ONLY
[7] Stop check   → iter ≥ 6 | same cat 3x | 2x non-shrinking | >10 files touched → STOP
                   else iter++, go to [2]
```

All scripts emit JSON to stdout; full logs stay at `.test-results/iter-N/` on disk.

### Failure categories (full table: `<PATH_TO_SKILL>/reference/failure-triage.md`)

| Cat | Key signal | First action | Forbidden |
|-----|------------|--------------|-----------|
| 5-A | `xcodebuild code 65/70`, Dart compile error, RunnerUITests scheme missing | Diagnose sub-cause from xcresult issues; fix build config or Podfile | Change test/app code before build is clean |
| 5-B | `WaitUntilVisibleTimeoutException`, `TimeoutException`, `pumpAndSettle timed out` | Take a11y tree; adjust timeouts or `SettlePolicy.trySettle` | Delete the test or add `Future.delayed` blindly |
| 5-C | `TestFailure: Expected: X Actual: Y` | Fix app code at the origin of the wrong value | **Change the `expect()` expected value** |
| 5-D | Simulator not booted, CocoaPods error, port conflict, `patrol: command not found` | Fix environment; `flutter clean` only here | Touch Dart code |
| 5-E | No matching signal / conflicting signals / empty parse output | Run `sim_snapshot.sh --tree` FIRST; STOP if tree is inconclusive | Speculative fixes before snapshot |

### Three hard rules (non-negotiable)

1. Never change an assertion to make a failing test pass — fix the app code.
2. Never delete a failing test to move on — use `skip: 'reason'` and report.
3. Never skip the triage step — classify the failure first, every time.

### Status line between iterations

```
iter N/6 · build ok · X/Y tests pass · fixing 5-C in file.dart
```

### Token discipline

- Scripts emit JSON summaries only; full logs stay on disk — read them with `rg`, not `cat`.
- Never dump raw `xcresult`, `xcodebuild`, or `simctl log` output into context.
- a11y tree is cheaper than screenshots — prefer `sim_snapshot.sh --tree`.
```

---

## How to use this snippet

### Cursor

1. Create or edit `AGENTS.md` in your project root.
2. Paste the markdown block above (between the ` ```markdown ``` ` fences).
3. Replace `<PATH_TO_SKILL>` with the actual path — e.g. `~/.claude/skills/flutter-patrol-pilot`.
4. Cursor reads `AGENTS.md` automatically on chat start.

### OpenAI Codex / other AGENTS-aware agents

Same procedure. Most AGENTS-aware agents look for `AGENTS.md` at the repo root and load it as high-priority context.

### Preferring `.cursor/rules/*.mdc` instead

If you want the rule to auto-attach only when Flutter/iOS files are open (rather than every chat),
use `templates/cursor_rule_snippet.mdc` instead — it uses Cursor's native `globs:` front-matter
to scope activation to `pubspec.yaml`, `patrol_test/**`, and `ios/Podfile`.
