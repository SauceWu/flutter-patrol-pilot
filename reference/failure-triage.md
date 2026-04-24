# Failure Triage Reference

This document is read at iteration loop step **[5] Triage**. When `parse_failure.py` returns failure JSON, use this document to classify the failure and determine the correct fix action.

**How to use:**

1. Run the **Pre-Triage Checks** (Section 1) before touching the signal table — structural parse errors masquerade as test failures.
2. Match the error signal against the **Quick-Reference Signal Table** (Section 2) to get a category (5-A through 5-E).
3. Read the **Per-Category Detail Block** (Section 4) for that category to get permitted actions, forbidden actions, and diagnostic commands.
4. Apply only the actions prescribed by that category. Do not cross-apply actions from other categories.

---

## Section 1 — Pre-Triage Checks

Run these three checks before consulting the signal table. Failures here indicate a tooling or environment problem, not a test logic problem.

**Check 1 — Validate xcresulttool output**

If `parse_failure.py` returned `null` or the `failures` array is empty, this is a **5-D or 5-E** condition, NOT a test failure. The xcresult file may not exist, the path may be stale, or the xcresulttool command syntax is wrong for the current Xcode version. Do not proceed to the signal table — fix the parsing step first.

**Check 2 — Check total test count**

If `latest.json` contains `total == 0`, treat this as a **5-A (silent failure)**, not a success. Zero tests ran. `patrol test` exits 0 (success code) when it finds no tests — this is indistinguishable from "all tests passed" unless `total` is explicitly checked. See the 5-A detail block for diagnosis steps.

**Check 3 — Verify xcresulttool command version**

Run `xcrun xcresulttool --version`. If the version number is >= 23000 (Xcode 16+ / Xcode 26.x), use the `get test-results summary` subcommand syntax. Do NOT use `xcrun xcresulttool get --format json --path <path>` without the `--legacy` flag — that form is deprecated in Xcode 16 and errors silently or returns empty output.

---

## Section 2 — Quick-Reference Signal Table

Match the first meaningful signal from `parse_failure.py` output against this table. If multiple signals appear, match the topmost one.

| Signal | Category | First Action | Forbidden |
|--------|----------|--------------|-----------|
| `xcodebuild exited with code 65` | 5-A | Sub-diagnose: check log for port conflict / missing pod / signing / sim-not-booted — see 5-A detail block | Change Dart/test code before diagnosing sub-cause |
| `xcodebuild exited with code 70` | 5-A | Query xcresult for `issues.errorSummaries` — most common root cause is `RunnerUITests isn't a member of the specified test plan or scheme`. Fix: open ios/Runner.xcworkspace in Xcode → Product → Scheme → Edit Scheme → Test → `+` add `RunnerUITests` target. For non-scheme causes (signing / provisioning): use `--allow-provisioning-updates` | Change app code before reading xcresult issues |
| `RunnerUITests isn't a member of the specified test plan or scheme` (in xcresult issues) | 5-A (testing_infra / Patrol setup) | Patrol 4.x setup step missing — RunnerUITests target exists but is not added to Runner scheme's Test action. Fix in Xcode: Product → Scheme → Edit Scheme → Test → `+` → select `RunnerUITests`. Commit `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` so the setup persists | Change Dart code |
| `Dart compilation failed` / `error:` in a `.dart` file | 5-A | Fix Dart syntax/type error at indicated file:line | Touch test file first |
| `no such module 'X'` | 5-A | `pod install` / `flutter pub get`; check Podfile.lock | Change Dart code |
| `Failed to build app with entrypoint test_bundle.dart` | 5-A | Find which test file is imported; fix Dart error there | Treat as Xcode issue |
| `SWIFT_VERSION` or deployment target mismatch | 5-A | Align `IPHONEOS_DEPLOYMENT_TARGET` in Podfile | Change Flutter code |
| `Total: 0 tests` in summary JSON | 5-A (silent failure) | Check `--target` path; verify test uses `patrolTest()` not `testWidgets()`; check test discovery | Treat as success |
| `WaitUntilVisibleTimeoutException` | 5-B | Take a11y tree; check: widget offscreen, overlay covering, animation not done; use `SettlePolicy.trySettle` or `scrollTo()` | Immediately add delay without checking tree |
| `WaitUntilExistsTimeoutException` | 5-B | Check navigation/routing; widget never appeared in tree at all | Assume widget exists |
| `pumpAndSettle timed out` | 5-B | Infinite animation running; switch action to `settlePolicy: SettlePolicy.trySettle` | Delete the pump call |
| `TimeoutException after 0:0X:XX` (runner-level) | 5-B | Whole test exceeded runner timeout; increase `PatrolTesterConfig.visibleTimeout` or split test | Ignore timeout |
| `PatrolIntegrationTestBinding` / `Binding is already initialized` | 5-B | Remove `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` from test file; never call vanilla binding init in Patrol tests | Change app code |
| `TestFailure: Expected: ... Actual: ...` | 5-C | Identify app-side code producing wrong value; fix app code | **Change the `expect()` expected value** |
| `expect($(finder), findsOneWidget)` found 0 widgets | 5-C | Check which widget should render this; fix app code that controls rendering | Delete the assertion |
| `Unable to find a destination matching` (sim Shutdown) | 5-D | Simulator not booted or UDID stale; re-run `boot_sim.sh` | Change code |
| `Unable to find a destination matching ... OS:latest, name:<X>` AFTER `build.sh` succeeded and sim IS Booted | 5-A (testing_infra / runtime mismatch) | Patrol CLI passes `-destination "OS=latest,name=<X>"` to xcodebuild. If Xcode's latest SDK > booted sim's iOS runtime, this fails. Fix: `xcrun simctl list runtimes` → boot a sim with runtime matching Xcode's installed SDK (or install the older runtime via Xcode → Settings → Platforms). | Retry without changing sim runtime |
| `flutter pub get` failed | 5-D | Network issue or bad pubspec; fix pubspec, retry pub get | Touch test/app code |
| `com.apple.provenance` xattr signing error | 5-D | `xattr -cr /path/to/Flutter.framework` | Regenerate signing certificates |
| `patrol: command not found` | 5-D | Add `~/.pub-cache/bin` to PATH; re-run `dart pub global activate patrol_cli` | Change code |
| `gRPC connection refused` / `PatrolAppService connection refused` | 5-D | Simulator not fully booted before test; wait for "Booted" state, not just "Booting" | Change code |
| `CocoaPods could not find compatible versions` | 5-D | Run `flutter pub get && cd ios && pod install` in order; if fails: `--repo-update` | Change app code |
| Port conflict `8081`/`8082` — `Test runner never began executing` | 5-D | `patrol test --test-server-port 8096 --app-server-port 8095`; check ports with `lsof` | Rebuild without diagnosing |
| `_pendingExceptionDetails != null` | 5-E | Take a11y tree; if still unclear → STOP and report | Speculative code changes |
| False positive (test marked passed, behavior wrong) | 5-E | Take screenshot; escalate to user | Any fix without human confirmation |
| No signal / empty parse output (null failures array) | 5-E | Check xcresult path validity; check Xcode version → xcresulttool command mismatch | Treat as pass |
| Native crash / Dart stack absent / XCUITest crash | 5-E | Take a11y tree; STOP if tree inconclusive | Speculative code changes |

---

## Section 3 — Critical Distinction Rules

> **5-B vs 5-C — Definitive Distinction:**
>
> - **5-B** throws `TimeoutException`, `WaitUntilVisibleTimeoutException`, or `WaitUntilExistsTimeoutException`
> - **5-C** throws `TestFailure` with an `Expected:` / `Actual:` pair in the failure message
>
> **Rule:** Check the exception class name in the first stack frame. The class name is the definitive signal — not the symptom description.
>
> **Common misclassification:** `expect($('Submit'), findsOneWidget)` → found 0 widgets looks like a 5-C assertion failure, but if the failure message contains `WaitUntilVisibleTimeoutException` or `TimeoutException`, it is actually 5-B (the widget exists but is not hit-testable or not visible). Always read the exception class before deciding.

> **5-D vs 5-E — Parse Output is Empty:**
>
> If `parse_failure.py` returns `null` or empty `failures` array, start with **5-D** (environment failure), not 5-E. Check the xcresult path and xcresulttool command version first. Only escalate to 5-E if the xcresult exists, the command is correct, and output is still empty.

---

## Section 4 — Per-Category Detail Blocks

---

### 5-A — Build Failure

**What it is:** Compilation or Xcode build step failed before any test ran. No test result JSON was written to `.test-results/latest.json`, OR `latest.json` exists but `total == 0`.

**Distinguishing signals:**
- No `latest.json` produced after `build.sh` completes
- `latest.json` exists but `total == 0` (silent failure — patrol exits 0 but ran nothing)
- `xcodebuild exited with code 65` or `code 70` in build log
- `Dart compilation failed` with file:line reference
- `no such module` in Xcode build output
- `Failed to build app with entrypoint test_bundle.dart`

#### xcodebuild Exit Code 65 — Sub-Categories

Exit code 65 is an omnibus error. The exit code alone is not actionable. Extract the first meaningful error line from the xcodebuild log and match below:

| Code-65 Sub-cause | Log snippet | Fix |
|-------------------|-------------|-----|
| Simulator not booted | `Unable to find a device matching the provided destination specifier` | Pre-boot: `xcrun simctl boot <UDID> \|\| true`; poll until "Booted" |
| Port conflict on 8081/8082 | `Test runner never began executing tests after launching` | `patrol test --test-server-port 8096 --app-server-port 8095` |
| Stale CocoaPods | `No podspec found` / dependency resolution errors | `cd ios && rm -rf Pods Podfile.lock && pod install` |
| Deployment target mismatch | `Compiling for iOS X.Y, but module was built for iOS A.B` | Align `IPHONEOS_DEPLOYMENT_TARGET` in Podfile post-install hook |
| Xcode/macOS version incompatibility | App installs but crashes on splash / cryptic build error | Update Xcode; clear DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData` |

#### xcresulttool Diagnostic Commands (Xcode 16+ / Xcode 26.x)

Use these subcommands for 5-A diagnosis. Do NOT use the deprecated `xcrun xcresulttool get --format json --path <path>` — that requires `--legacy` on Xcode 16+ and will error or return empty output.

```bash
# Quick pass/fail summary — most useful for initial triage
xcrun xcresulttool get test-results summary \
  --path /path/to/TestResults.xcresult \
  --compact

# Full test structure (pass/fail for each test)
xcrun xcresulttool get test-results tests \
  --path /path/to/TestResults.xcresult \
  --compact

# Detailed failure info for a specific test (failure message + stack trace)
xcrun xcresulttool get test-results test-details \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# Activity log (tap-by-tap action trace — what Patrol did)
xcrun xcresulttool get test-results activities \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# Inspect JSON schema at runtime (if output structure is unclear)
xcrun xcresulttool get test-results summary --schema
xcrun xcresulttool get test-results tests --schema
xcrun xcresulttool get test-results test-details --schema
```

Note: `get test-results` subcommands output JSON by default. `--compact` suppresses pretty-printing. There is no `--format json` flag for these subcommands.

#### Permitted Actions (5-A)

- Fix Xcode project configuration (deployment targets, build settings)
- Fix CocoaPods: run `pod install`, update Podfile, clear Pods/ and Podfile.lock
- Fix Dart code at the exact file:line indicated in the Dart compilation error
- Run `flutter pub get` after pubspec changes
- Clear DerivedData ONLY when stale-cache sub-cause is confirmed
- Align `IPHONEOS_DEPLOYMENT_TARGET` in Podfile post-install hook

#### Forbidden Actions (5-A)

- Touch test code or app logic before the build is clean
- Run `flutter clean` reflexively — only use it for stale-cache sub-cause (confirmed by DerivedData / `.dart_tool/` errors)
- Retry the build without reading the first meaningful error line from the log

**Loop phase:** [2] Build — go to [5] on build failure; return to [2] after fix.

---

### 5-B — Test Timeout / Finder Failure

**What it is:** The test started and ran, but Patrol's finders or pumping timed out waiting for a widget to appear, become visible, or for the UI to settle. The app may be partially correct — the widget may exist but be offscreen, behind an overlay, or waiting for an animation to complete.

**Decisive signal:** Exception class is `TimeoutException`, `WaitUntilVisibleTimeoutException`, or `WaitUntilExistsTimeoutException` in the first stack frame — NOT `TestFailure`.

**Key distinction from 5-C (bold rule):**

> **5-B throws a timeout exception; 5-C throws `TestFailure` with an `Expected:` / `Actual:` pair. Read the exception class in the first stack frame. This is the definitive signal. Do not classify by symptom alone.**

**Signal patterns:**
- `WaitUntilVisibleTimeoutException: Finder '...' found N widget(s) but none was/were visible`
- `WaitUntilExistsTimeoutException: Finder '...' found 0 widget(s)` (widget never appeared in tree)
- `pumpAndSettle timed out` (infinite animation — `CircularProgressIndicator`, Lottie, etc.)
- `TimeoutException after 0:0X:XX` (runner-level — whole test exceeded configured timeout)
- `Binding is already initialized` / `PatrolIntegrationTestBinding` (double-init causes test hang)

**Triage sub-steps:**
1. Take a11y tree snapshot before making any code changes
2. If widget appears in tree but is not visible → widget is offscreen or behind overlay → use `scrollTo()` or fix z-order
3. If widget is absent from tree → navigation/routing issue → widget was never rendered
4. If `pumpAndSettle timed out` → infinite animation → switch to `SettlePolicy.trySettle`
5. If runner-level timeout → test too long → increase `PatrolTesterConfig.visibleTimeout` or split test

#### Permitted Actions (5-B)

- Increase `visibleTimeout` or `existsTimeout` in `PatrolTesterConfig`
- Switch `settlePolicy` to `SettlePolicy.trySettle` (from `SettlePolicy.settle`)
- Add `scrollTo()` before interaction when widget is offscreen
- Add `waitUntilVisible()` before assertion when animation/loading delay is involved
- Remove `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` from test file (double-init fix)
- Fix routing logic in test setup if widget never appears (navigation not reached)

#### Forbidden Actions (5-B)

- Change `expect()` expected values
- Delete the failing test or assertion
- Use `patrol develop` instead of `patrol test`
- Add `await Future.delayed()` as a fix without first taking the a11y tree

**Loop phase:** [5] Triage → [6] Fix — return to [2] after fix.

---

### 5-C — Assertion Failure

**What it is:** The test ran to completion and Patrol found the widget, but `expect()` evaluated to false. The app's behavior does not match the test's specification. This is a genuine app bug.

**Decisive signal:** `TestFailure: Expected: <X> Actual: <Y>` — always contains both `Expected:` and `Actual:` labels in the failure message.

**Signal patterns:**
- `TestFailure: Expected: <true> Actual: <false>`
- `TestFailure: Expected: <'Welcome, Alice'> Actual: <'Welcome, '>`
- `expect($(finder), findsOneWidget)` → found 0 visible (hit-testable) widgets — when exception class is `TestFailure` (not a timeout)
- `expect($(finder), findsNWidgets(3))` → found 2

> **Hard Rule — Never change the `expect()` expected value to match broken app behavior. The assertion is the specification. Fix the app code, not the test.**

**Triage steps:**
1. Read the `Expected:` value — this is the spec/contract
2. Read the `Actual:` value — this is what the app produced
3. Trace the actual value backward through the stack to find where the wrong value originates
4. Fix the app-side code at that origin point

#### Permitted Actions (5-C)

- Fix app-side code at the exact file:line indicated in the stack trace
- Fix widget rendering logic that produces a wrong value
- Fix state management that computes or stores an incorrect value
- Fix data transformation or formatting functions that produce wrong output

#### Forbidden Actions (5-C)

- Change `expect()` expected values to match broken behavior
- Delete assertions or comment them out
- Relax matchers — `equals(5)` → `greaterThan(3)` is forbidden
- Change assertion thresholds to make the test pass without fixing the underlying bug

**Loop phase:** [5] Triage → [6] Fix — return to [2] after fix.

---

### 5-D — Environment / Cache Failure

**What it is:** The failure is in the local build environment, toolchain, or caching layer — not in app code or test logic. The same code would work on a clean machine or after resetting the environment. Common causes: simulator not booted, stale CocoaPods cache, missing PATH entry, signing xattr issue, port conflict.

**Signal patterns:**
- `Unable to find a destination matching` — simulator not booted or UDID stale
- `flutter pub get` failed — network or pubspec dependency conflict
- `com.apple.provenance` xattr signing error — Framework quarantine attribute
- `patrol: command not found` — `~/.pub-cache/bin` not in PATH
- `gRPC connection refused` / `PatrolAppService connection refused` — simulator not fully booted
- `CocoaPods could not find compatible versions` — stale pod specs
- Port conflict on 8081/8082 — another process holding the Patrol test server port

#### Permitted Actions (5-D) — ONLY These

- Re-boot simulator: `xcrun simctl boot <UDID> && xcrun simctl list devices | grep <UDID>`
- Fix PATH: export `~/.pub-cache/bin` in shell profile; re-activate patrol_cli
- Run `flutter clean && flutter pub get` — **only for 5-D, never for other categories**
- Run `xattr -cr /path/to/Flutter.framework` for provenance signing errors
- Run `pod install` or `pod install --repo-update` for CocoaPods conflicts
- Re-query simulator UDID: `xcrun simctl list devices --json`
- Change test server port: `patrol test --test-server-port 8096 --app-server-port 8095`

#### Forbidden Actions (5-D)

- Change any Dart or test code
- Run `flutter clean` for any category other than 5-D
- Rebuild without diagnosing the specific environment sub-cause

**Loop phase:** [1] Prepare environment or [6] Fix — depending on when discovered. Return to [1] after environment fix.

---

### 5-E — Unknown — Mandatory A11y Tree Step

**What it is:** The failure signal does not cleanly match categories 5-A through 5-D, signals conflict with each other, or `parse_failure.py` output is ambiguous. This is the catch-all category — it is not a valid final classification. The agent must gather more information before taking any action.

**Signal patterns:**
- `_pendingExceptionDetails != null` — Dart VM reports pending exception with no clear message
- False positive — test passes but observed behavior is wrong (visible in screenshot)
- Native crash / XCUITest crash — no Dart stack, only system-level signal
- Empty parse output — `failures` is null or `[]` despite a visible test failure in Xcode output

> **Mandatory First Action: Run `scripts/sim_snapshot.sh --tree` before ANY other action.**
>
> Do NOT make code changes until the a11y tree has been captured and reviewed. Speculative fixes in 5-E waste iterations and may obscure the real cause.

**Decision tree after taking a11y tree:**

1. **Tree explains the state** → re-classify as 5-B (widget present but not visible) or 5-C (widget absent because app logic is wrong) → apply that category's fix protocol
2. **Tree is inconclusive** → take screenshot with `scripts/sim_snapshot.sh --screenshot` for additional visual context
3. **Still unclear after tree + screenshot** → **STOP** — report the raw failure signal, tree output, and screenshot to the user; do not attempt further fixes

#### Forbidden Actions (5-E)

- Make any code change before taking the a11y tree
- Speculative fixes based on the failure message alone
- Treat empty parse output as "all tests passed"
- Classify as 5-E and continue without taking the a11y tree

**Loop phase:** [5] Triage — if re-classification succeeds, continue to [6] Fix. If still unclear after tree, STOP and report to user before any further iteration.

---

## Appendix — xcresulttool Version Check

```bash
# Determine which API syntax to use
XCRESULT_VERSION=$(xcrun xcresulttool --version 2>/dev/null | grep -oE '[0-9]+' | head -1)

if [ "${XCRESULT_VERSION}" -ge 23000 ]; then
  # Xcode 16+ (including Xcode 26.x) — use get test-results subcommands
  xcrun xcresulttool get test-results summary \
    --path "${XCRESULT_PATH}" \
    --compact
else
  # Xcode 15 and earlier — use legacy form
  xcrun xcresulttool get --format json \
    --path "${XCRESULT_PATH}"
fi
```

The xcresulttool version on the reference machine is **24757** (Xcode 26.4). This machine always uses `get test-results` subcommands.

---

## Appendix — Category Summary Table

| Category | Name | Loop Phase | Key Signal | Hard Constraint |
|----------|------|------------|-----------|-----------------|
| 5-A | Build Failure | [2] → [5] | No `latest.json`; `total == 0`; xcodebuild exit code | Never change test/app code before build is clean |
| 5-B | Test Timeout | [5] → [6] | `TimeoutException`, `WaitUntilVisibleTimeoutException` | Never delete the test; check a11y tree first |
| 5-C | Assertion Failure | [5] → [6] | `TestFailure: Expected: ... Actual: ...` | Never change the `expect()` expected value |
| 5-D | Environment Failure | [1] or [6] | Port conflict, missing PATH, signing xattr | Never change Dart code; `flutter clean` only here |
| 5-E | Unknown | [5] (stop if unclear) | No matching signal; conflicting signals | Must take a11y tree before any action |
