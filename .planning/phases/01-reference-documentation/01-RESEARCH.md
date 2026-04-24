# Phase 1: Reference Documentation - Research

**Researched:** 2026-04-24
**Domain:** Patrol 4.x test patterns · iOS/Xcode failure triage · xcresulttool Xcode 26.4 subcommand API
**Confidence:** HIGH (all critical claims verified via Context7 live docs + xcresulttool CLI introspection)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Failure Triage Table Design**
- Signal-first quick-reference table at the top for fast lookup during iteration
- Per-category detail blocks below with: signal patterns, permitted actions, forbidden actions, example fixes
- Category 5-E (unknown) must include mandatory a11y tree step before any action
- Include the specific xcresulttool Xcode 16+ subcommand syntax in 5-A examples
- Add "Total: 0 tests" detection rule as a 5-A subcategory (silent failure mode)
- Split xcodebuild code-65 into sub-categories in the 5-A detail block

**Patrol Patterns Cheatsheet Organization**
- Organized by concept: Finders → Interactions → Assertions → Pump/Settle strategies
- Patrol 4.x syntax throughout; show both `$.native` and `$.platform.mobile` aliases
- Include chained finders (`containing()`) and Symbol shorthand (`$(#key)`)
- List all finder argument types: String, RegExp, Type, Symbol, Key, IconData
- Include all SettlePolicy enum values with when-to-use guidance
- Note `SettlePolicy.trySettle` as the recommended template default

**Troubleshooting Doc Structure**
- Symptom → Cause → Fix numbered steps per issue
- Ordered by frequency (most common first)
- Each fix maps to which iteration-protocol phase handles it (5-A, 5-D, etc.)
- Cover: simulator boot failures, CocoaPods conflicts, xcresulttool deprecation, signing/provisioning errors, PatrolIntegrationTestBinding errors
- Note the `patrol doctor` command for first-run diagnosis

### Claude's Discretion
- Exact markdown formatting within sections (headers, code blocks, tables)
- Level of code examples in patrol-patterns.md (inline vs separate blocks)

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REF-01 | Failure triage table covers all known failure categories (5-A through 5-E) with signal patterns, actions, and forbidden actions — accurate enough for agent triage without ambiguity | Full signal set for 5-A through 5-E verified in FEATURES.md + PITFALLS.md; xcresulttool command syntax verified via CLI; exception class names (TestFailure vs TimeoutException) confirmed via Context7 |
| REF-02 | Patrol patterns cheatsheet covers finders, interactions, assertions, and pump strategies for Patrol 4.x — usable as a code generation reference | Complete finder API surface verified via Context7 (/leancodepl/patrol); all SettlePolicy values confirmed; $.platform.mobile vs $.native aliases confirmed |
| REF-03 | Troubleshooting doc covers the top iOS simulator / CocoaPods / signing / xcresulttool failure modes with specific resolution steps | Top failure modes from PITFALLS.md (verified HIGH confidence); xcresulttool exact commands verified via CLI introspection on machine |

</phase_requirements>

---

## Summary

Phase 1 produces three read-only reference documents consumed by the agent during the iteration loop. All three docs must be self-contained (no external links required for the agent to act) and reflect Patrol 4.x APIs and the xcresulttool API available on this machine (Xcode 26.4, xcresulttool version 24757).

The most load-bearing document is `failure-triage.md` — without it the agent applies wrong fix classes and wastes iterations. The signal-to-category mapping is fully specified in FEATURES.md and PITFALLS.md from prior research rounds; this research phase confirms all signal patterns, adds the `Total: 0` silent failure rule, and verifies the exact xcresulttool subcommand syntax for the current machine.

`patrol-patterns.md` is the second-highest priority: training-data knowledge of Patrol's `$` API is unreliable (agents frequently hallucinate `find.byText()` vanilla calls instead of `$('text')`, or miss `$.platform.mobile` in favor of the old `$.native`). The cheatsheet must be exhaustive enough to be the sole grounding doc for test code generation.

`troubleshooting.md` is the lookup doc for category 5-D (environment) and 5-A (build) fixes — ordered by frequency so the agent finds the most likely cause first.

**Primary recommendation:** Write failure-triage.md first (loop gate), patrol-patterns.md second (code generation), troubleshooting.md third (environment recovery). All three must be written in one phase.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Failure signal classification | Reference doc (failure-triage.md) | Agent reasoning at step [5] | Doc provides the lookup table; agent applies it |
| Patrol test code generation / repair | Reference doc (patrol-patterns.md) | Agent at steps [0] and [6] | Doc grounds API usage; agent instantiates patterns |
| iOS/Xcode/CocoaPods issue resolution | Reference doc (troubleshooting.md) | Agent at step [6] for 5-A/5-D | Doc provides ordered step sequences; agent executes |
| xcresult parsing | Script (parse_failure.py) — Phase 2 | Reference doc provides command syntax | Scripts are Phase 2; docs describe the commands |
| Iteration loop control | reference/iteration-protocol.md (existing) | All three new docs are consulted within the loop | iteration-protocol.md is the state machine; new docs are its lookup tables |

---

## Standard Stack

### The Three Output Files

| File | Purpose | Read At |
|------|---------|---------|
| `reference/failure-triage.md` | Signal → category → action lookup; forbidden actions; per-category detail blocks | Iteration loop step [5] Triage |
| `reference/patrol-patterns.md` | Patrol 4.x syntax cheatsheet for finders, interactions, assertions, pump/settle | Steps [0] (generate test) and [6] (fix test) |
| `reference/troubleshooting.md` | iOS/CocoaPods/signing/xcresulttool symptom→cause→fix steps | Step [6] for categories 5-A and 5-D |

These are **Markdown documents only** — no scripts, no Dart files, no configuration.

---

## Architecture Patterns

### System Architecture Diagram

```
Agent receives failure JSON from parse_failure.py
        |
        v
[5] Triage Step
        |
        +--- reads --> reference/failure-triage.md
        |              (signal → category → action → forbidden)
        |
        v
Category assigned (5-A / 5-B / 5-C / 5-D / 5-E)
        |
        +-- 5-B or 5-C fix --> reads --> reference/patrol-patterns.md
        |                                (correct finder/pump/assert syntax)
        |
        +-- 5-A or 5-D fix --> reads --> reference/troubleshooting.md
        |                                (step-by-step resolution)
        |
        +-- 5-E unknown -----> sim_snapshot.sh --tree
                                     |
                                     v
                            re-classify or STOP
```

### Recommended Project Structure

These docs live in the `reference/` folder that already contains `iteration-protocol.md`:

```
reference/
├── iteration-protocol.md   (existing — the loop state machine)
├── failure-triage.md       (new — signal→category→action table)
├── patrol-patterns.md      (new — Patrol 4.x syntax cheatsheet)
└── troubleshooting.md      (new — iOS/Xcode/CocoaPods fix steps)
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| xcresult parsing commands | Custom xcresulttool wrapper | Exact commands from STACK.md + verified below | Commands are machine-specific; use verified syntax |
| Patrol finder API reference | Agent training data | patrol-patterns.md (Context7-verified) | Training data hallucinates non-existent Patrol APIs |
| Failure signal patterns | Agent pattern-matching heuristics | failure-triage.md signal table | Deterministic table beats probabilistic reasoning for triage |

---

## Content Specification Per Document

This section is the core of the research — it tells the planner exactly what content to write in each section of each document.

---

### DOC 1: `reference/failure-triage.md`

#### Section 1 — Quick-Reference Signal Table (top of doc, fast lookup)

The table has four columns: `Signal` | `Category` | `First Action` | `Forbidden`

Every row below is required. The planner writes this verbatim as a Markdown table.

[VERIFIED: FEATURES.md + PITFALLS.md + Context7]

| Signal (from parse_failure.py output) | Category | First Action | Forbidden |
|---------------------------------------|----------|--------------|-----------|
| `xcodebuild exited with code 65` | 5-A | Sub-diagnose: check log for port conflict / missing pod / signing / sim-not-booted — see 5-A detail block | Change Dart/test code before diagnosing sub-cause |
| `xcodebuild exited with code 70` | 5-A | Fix RunnerUITests signing/provisioning; use `--allow-provisioning-updates` | Change app code |
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
| `expect($(finder), findsOneWidget)` → found 0 widgets | 5-C | Check which widget should render this; fix app code that controls rendering | Delete the assertion |
| `Unable to find a destination matching` | 5-D | Simulator not booted or UDID stale; re-run `boot_sim.sh` | Change code |
| `flutter pub get` failed | 5-D | Network issue or bad pubspec; fix pubspec, retry pub get | Touch test/app code |
| `com.apple.provenance` xattr signing error | 5-D | `xattr -cr /path/to/Flutter.framework` | Regenerate signing certificates |
| `patrol: command not found` | 5-D | Add `~/.pub-cache/bin` to PATH; re-run `dart pub global activate patrol_cli` | Change code |
| `gRPC connection refused` / `PatrolAppService connection refused` | 5-D | Simulator not fully booted before test; wait for "Booted" state, not just "Booting" | Change code |
| `CocoaPods could not find compatible versions` | 5-D | Run `flutter pub get && cd ios && pod install` in order; if fails: `--repo-update` | Change app code |
| Port conflict `8081`/`8082` — `Test runner never began executing` | 5-D | `patrol test --test-server-port 8096 --app-server-port 8095`; check ports with `lsof` | Rebuild without diagnosing |
| `_pendingExceptionDetails != null` | 5-E | Take a11y tree; if still unclear → STOP and report | Speculative code changes |
| False positive (test marked passed, behavior wrong) | 5-E | Take screenshot; escalate to user | Any fix without human confirmation |
| `No signal / empty parse output` (null failures array) | 5-E | Check xcresult path validity; check Xcode version → xcresulttool command mismatch | Treat as pass |
| Native crash / Dart stack absent / XCUITest crash | 5-E | Take a11y tree; STOP if tree inconclusive | Speculative code changes |

#### Section 2 — Pre-Triage Checklist (before matching signals)

[VERIFIED: PITFALLS.md — C-6 xcresulttool, CONTEXT.md specifics]

Before applying the table above:

1. **Validate xcresult output**: if `parse_failure.py` returned `null` or empty `failures` array → this is 5-D/5-E, NOT a test failure. Check xcresult path exists and xcresulttool command was correct.
2. **Check total test count**: if `total == 0` in `latest.json` → treat as 5-A (silent failure), not success.
3. **Verify xcresulttool command version**: `xcrun xcresulttool --version` → if >= 23000, use `get test-results summary` subcommand syntax; do NOT use `get --format json` without `--legacy`.

#### Section 3 — Per-Category Detail Blocks

Each block has: What it is | Signal patterns (expanded) | Permitted actions | Forbidden actions | Example fix with xcresulttool command where applicable.

**Category 5-A: Build Failure**

What it is: Compilation or Xcode build step failed before any test ran. No test result JSON was written to `.test-results/latest.json`.

Distinguishing signal: No `latest.json` produced, OR `latest.json` exists but `total == 0`.

xcodebuild code-65 sub-categories (MUST be in this block):
[VERIFIED: PITFALLS.md C-1]

| Code-65 Sub-cause | Log snippet | Fix |
|-------------------|-------------|-----|
| Simulator not booted | `Unable to find a device matching the provided destination specifier` | Pre-boot: `xcrun simctl boot <UDID> || true`; poll until "Booted" |
| Port conflict on 8081/8082 | `Test runner never began executing tests after launching` | `patrol test --test-server-port 8096 --app-server-port 8095` |
| Stale CocoaPods | `No podspec found` / dependency resolution errors | `cd ios && rm -rf Pods Podfile.lock && pod install` |
| Deployment target mismatch | `Compiling for iOS X.Y, but module was built for iOS A.B` | Align `IPHONEOS_DEPLOYMENT_TARGET` in Podfile post-install hook |
| Xcode/macOS version incompatibility | App installs but crashes on splash | Update Xcode; clear DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData` |

xcresulttool example commands for 5-A diagnostic (include verbatim):
[VERIFIED: CLI introspection on this machine — Xcode 26.4, xcresulttool 24757]

```bash
# Xcode 16+ (including Xcode 26.x which is based on Xcode 17+): use get test-results subcommands
# DO NOT use the old: xcrun xcresulttool get --format json --path <path>
# That form is deprecated; without --legacy it errors out.

# Quick summary (most useful for triage)
xcrun xcresulttool get test-results summary \
  --path /path/to/TestResults.xcresult \
  --compact

# All tests (pass/fail structure)
xcrun xcresulttool get test-results tests \
  --path /path/to/TestResults.xcresult \
  --compact

# Detailed failure info for a specific test
xcrun xcresulttool get test-results test-details \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# Activity log (tap-by-tap trace)
xcrun xcresulttool get test-results activities \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# Inspect JSON schema at runtime (if structure is unclear)
xcrun xcresulttool get test-results summary --schema
```

Permitted actions: Fix Xcode project configuration, CocoaPods, Podfile, Dart code at indicated file:line. Run `pod install`. Clear DerivedData (only when stale cache confirmed).

Forbidden actions: Touch test code or app logic before build is clean. Run `flutter clean` reflexively (only for stale cache sub-cause).

**Category 5-B: Test Timeout / Finder Failure**

What it is: The test started and Patrol's finders or pumping timed out waiting for a widget or for the UI to settle.

Distinguishing signal: Exception class is `TimeoutException` or `WaitUntilVisibleTimeoutException` or `WaitUntilExistsTimeoutException` — NOT `TestFailure`.
[VERIFIED: FEATURES.md — "the error type in the stack frame is the definitive signal"]

Key distinction from 5-C: 5-B throws a timeout exception; 5-C throws `TestFailure` with `Expected:` / `Actual:` pair. Check the exception class in the first stack frame.

Permitted actions: Increase `visibleTimeout`/`existsTimeout` in `PatrolTesterConfig`. Switch to `SettlePolicy.trySettle`. Add `scrollTo()` before interaction. Add `waitUntilVisible()` before assertion. Remove spurious `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` calls.

Forbidden actions: Change expected values. Delete the test. Use `patrol develop` instead of `patrol test`.

**Category 5-C: Assertion Failure**

What it is: Test ran to completion but `expect()` evaluated false. App behavior does not match test expectation.

Distinguishing signal: `TestFailure: Expected: <X> Actual: <Y>` — always has `Expected:` and `Actual:` pair in the failure message.
[VERIFIED: FEATURES.md]

HARD RULE (repeat verbatim in doc): "Never change the `expect()` expected value to match the broken app behavior. The assertion is the spec. Fix the app code."

Permitted actions: Fix app-side code at file:line indicated in stack. Fix widget rendering logic. Fix state management that produces wrong value.

Forbidden actions: Change `expect()` expected values. Delete assertions. Relax matchers (`equals(5)` → `greaterThan(3)`).

**Category 5-D: Environment / Cache Failure**

What it is: The failure is in the local build environment or caching layer, not in code.

Permitted actions (ONLY these): Re-boot simulator. Fix PATH. Run `flutter clean && flutter pub get` (ONLY this category). Run `xattr -cr` for signing. Update CocoaPods. Re-query simulator UDID.

Forbidden actions: Change any Dart/test code. Run `flutter clean` for any other category.

**Category 5-E: Unknown — Mandatory a11y Tree Step**

What it is: Signal does not cleanly match 5-A through 5-D, or signals conflict.

MANDATORY FIRST ACTION: Take a11y tree snapshot (`scripts/sim_snapshot.sh --tree`). If tree explains state → re-classify as 5-B or 5-C. If still unclear → take screenshot. If still unclear → STOP and report to user. DO NOT make speculative fixes.

---

### DOC 2: `reference/patrol-patterns.md`

#### Section 1 — Imports

[VERIFIED: Context7 /leancodepl/patrol]

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
```

For widget-only tests (no native automation): use `patrolWidgetTest()` with same imports.

#### Section 2 — Test Structure

[VERIFIED: Context7 /leancodepl/patrol — patrolSetUp/patrolTearDown lifecycle section]

```dart
void main() {
  patrolSetUp(() async {
    // Runs before each patrolTest in this file
    // Use for: clear shared prefs, reset auth state
    // NOTE: NOT setUp() — vanilla setUp() does not integrate with Patrol's native lifecycle
  });

  patrolTearDown(() async {
    // Runs after each patrolTest
    // NOTE: NOT tearDown()
  });

  group('FeatureName', () {
    patrolTest(
      'description: user can X and should see Y',
      config: const PatrolTesterConfig(
        existsTimeout: Duration(seconds: 10),
        visibleTimeout: Duration(seconds: 10),
        settleTimeout: Duration(seconds: 10),
        settlePolicy: SettlePolicy.trySettle,  // recommended default
        dragDuration: Duration(milliseconds: 100),
        settleBetweenScrollsTimeout: Duration(seconds: 5),
        printLogs: true,
      ),
      ($) async {
        // 1. initApp() BEFORE pumpWidgetAndSettle — order matters
        // initApp();   // uncomment if project has test-mode initializer

        // 2. Pump widget tree
        await $.pumpWidgetAndSettle(const MyApp());

        // 3. Test steps
        // 4. Assertions
      },
    );
  });
}
```

Key notes (must appear in doc):
- `patrolSetUp`/`patrolTearDown` — NOT `setUp`/`tearDown`. Vanilla versions do not integrate with Patrol's native automation lifecycle.
- `initApp()` must be called BEFORE `pumpWidgetAndSettle`, never after.
- Patrol 4.0 removed `bindingType` and `nativeAutomation` params from `patrolTest()`. Do not include them.
- Use `patrolWidgetTest()` (not `patrolTest()`) when native automation is not needed.

#### Section 3 — Finder Types (all argument types for `$()`)

[VERIFIED: Context7 /leancodepl/patrol — finder types section]

The `$()` callable creates a `PatrolFinder`. Argument types:

```dart
// By exact text (String)
$('Log in')
$('Subscribe')

// By text pattern (RegExp)
$(RegExp(r'Welcome.*'))
$(RegExp(r'^\d+ items?$'))

// By widget type (Type)
$(TextField)
$(ElevatedButton)
$(ListView)
$(Scaffold)

// By Symbol key — preferred, no Key() wrapper needed
$(#submitButton)    // equivalent to $(const Key('submitButton'))
$(#emailInput)

// By explicit Key object
$(const Key('my-button'))
$(Key('dynamic-$id'))

// By IconData
$(Icons.add)
$(Icons.close)
$(Icons.arrow_back)

// By Semantics label — use find.bySemanticsLabel()
$(find.bySemanticsLabel('Edit profile'))
```

#### Section 4 — Chained Finders (containing())

[VERIFIED: Context7 /leancodepl/patrol — chained finders section]

```dart
// Find text inside a specific widget type
await $(ListView).$('Subscribe').tap();
await $(ListView).$(ListTile).$('Subscribe').tap();

// Multi-level chain
await $(Scaffold).$(#box1).$('Log in').tap();

// containing() — find parent that has a descendant matching
await $(ListTile).containing('Activated').$(#learnMore).tap();

// Multiple containing() filters — parent must contain ALL descendants
await $(Scrollable).containing(ElevatedButton).containing(Text).tap();

// Nested containing
await $(Scrollable).containing($(TextButton).$(Text)).tap();
```

#### Section 5 — Index Selection

[VERIFIED: Context7 /leancodepl/patrol]

```dart
await $(TextButton).at(2).tap();    // third match (0-indexed)
await $(TextButton).first.tap();    // first match
await $(TextButton).last.tap();     // last match
```

#### Section 6 — Predicate Filter (.which())

[VERIFIED: Context7 /leancodepl/patrol]

```dart
await $(ElevatedButton)
    .which<ElevatedButton>((btn) => btn.enabled)
    .tap();
```

#### Section 7 — Interaction Methods

[VERIFIED: Context7 /leancodepl/patrol — PatrolFinder actions section]

```dart
// Tap — waits for visible before acting (unlike tester.tap)
await $(#loginButton).tap();
await $(#button).tap(
  settlePolicy: SettlePolicy.noSettle,
  visibleTimeout: Duration(seconds: 5),
  settleTimeout: Duration(seconds: 3),
);

// Long press
await $(#contextMenuTarget).longPress();

// Enter text — clears field first
await $(#emailField).enterText('user@example.com');
await $(#passwordInput).enterText('secret',
  settlePolicy: SettlePolicy.trySettle);

// Scroll until widget appears
await $('Delete account').scrollTo().tap();   // scroll then tap
await $('Subscribe').scrollTo();              // scroll only
await $(#bottomItem).scrollTo(
  view: find.byType(ListView),
  scrollDirection: AxisDirection.down,
  maxScrolls: 20,
);

// Wait for widget in tree (not necessarily visible)
await $(#loadingIndicator).waitUntilExists();

// Wait for widget to be visible and hit-testable
await $(#contentLoaded).waitUntilVisible();
await $(#contentLoaded).waitUntilVisible(timeout: Duration(seconds: 15));

// Get text from Text widget
final label = $(#welcomeMessage).text;
```

#### Section 8 — Assertions

[VERIFIED: Context7 /leancodepl/patrol — making assertions section]

```dart
// Standard flutter_test matchers work with $ finders
expect($('Log in'), findsOneWidget);
expect($('Log in'), findsNothing);
expect($(Card), findsNWidgets(3));
expect($(Card), findsWidgets);     // one or more

// .exists — non-blocking boolean, no timeout
expect($(#myWidget).exists, isTrue);
expect($('Error').exists, isFalse);

// .visible — checks hit-testability (not just tree presence)
expect($('Log in').visible, equals(true));
expect($('Log in').visible, isTrue);
```

#### Section 9 — SettlePolicy: All Values and When to Use

[VERIFIED: Context7 /leancodepl/patrol — SettlePolicy section; official docs text confirmed]

SettlePolicy is an enum with exactly **3 values**:

| Value | Maps to | When to Use |
|-------|---------|-------------|
| `SettlePolicy.settle` | `pumpAndSettle()` | Finite animations only; THROWS if frames still pending after timeout. Use when you need to guarantee a fully-settled state. |
| `SettlePolicy.trySettle` | `pumpAndTrySettle()` | **Recommended default.** Pumps frames for settleTimeout, then continues without throwing even if frames remain. Works for both finite and infinite animations (e.g., `CircularProgressIndicator`, Lottie). |
| `SettlePolicy.noSettle` | `pump()` | Single frame pump only. Use when animation MUST continue (e.g., you need to observe in-progress animation state). |

Default changed in patrol_finders v2: `SettlePolicy.trySettle` is now the default. The template default should be `SettlePolicy.trySettle`.

```dart
// Global config
config: const PatrolTesterConfig(
  settlePolicy: SettlePolicy.trySettle,  // recommended template default
)

// Per-action override
await $(#animatedButton).tap(settlePolicy: SettlePolicy.noSettle);
await $(#form).tap(settlePolicy: SettlePolicy.settle);
```

#### Section 10 — Native / Platform Automation

[VERIFIED: Context7 /leancodepl/patrol — native automation section]

Patrol 4.0: `$.platform.mobile` is the canonical API. `$.native` is the older alias — both work. Show both since existing tests use `$.native`.

```dart
// --- Permissions ---
// Always guard with isPermissionDialogVisible() to handle re-runs where permission already granted
if (await $.platform.mobile.isPermissionDialogVisible()) {
  await $.platform.mobile.grantPermissionWhenInUse();
  // or: await $.platform.mobile.grantPermissionOnlyThisTime();
  // or: await $.platform.mobile.denyPermission();
}
await $.platform.mobile.selectFineLocation();  // precise location

// --- Notifications ---
await $.platform.mobile.openNotifications();
final notifications = await $.platform.mobile.getNotifications();
await $.platform.mobile.tapOnNotificationByIndex(0);
await $.platform.mobile.tapOnNotificationBySelector(
  Selector(textContains: 'New message'),
  timeout: Duration(seconds: 5),
);
await $.platform.mobile.closeNotifications();

// --- Navigation ---
await $.platform.mobile.pressHome();
await $.platform.mobile.openApp(appId: 'com.example.app');
await $.platform.mobile.openUrl('https://example.com');

// --- System Toggles ---
await $.platform.mobile.enableWifi();
await $.platform.mobile.disableWifi();
await $.platform.mobile.enableCellular();
await $.platform.mobile.enableDarkMode();
await $.platform.mobile.enableAirplaneMode();

// --- Gestures ---
await $.platform.mobile.swipe(
  from: const Offset(0.5, 0.8),
  to: const Offset(0.5, 0.2),
  steps: 12,
);
await $.platform.mobile.swipeBack();     // iOS back gesture (swipe from left edge)
await $.platform.mobile.pullToRefresh();
await $.platform.mobile.pressVolumeUp();
await $.platform.mobile.pressVolumeDown();

// --- Device Info / Simulator Only ---
await $.platform.mobile.setMockLocation(37.7749, -122.4194);
final bool isVirtual = await $.platform.mobile.isVirtualDevice(); // always true on simulator

// --- Old alias ($.native) — still works, show for reference ---
if (await $.native.isPermissionDialogVisible()) {
  await $.native.grantPermissionWhenInUse();
}
await $.native.pressHome();
await $.native.swipeBack();
```

#### Section 11 — Pump / Settle Reference

[VERIFIED: Context7 /leancodepl/patrol]

```dart
// Pump whole widget tree and settle (use after pumpWidget, before interactions)
await $.pumpWidgetAndSettle(const MyApp());

// Manual pumps
await $.pump();                        // single frame
await $.pump(Duration(seconds: 1));    // pump for duration

// pumpAndSettle variants (rarely needed directly — use settlePolicy in actions)
await $.pumpAndSettle();
await $.pumpAndTrySettle();

// The right pattern for most tests:
// 1. pumpWidgetAndSettle once at the start
await $.pumpWidgetAndSettle(const MyApp());
// 2. Use settlePolicy: SettlePolicy.trySettle on each action (or set in config)
await $(#button).tap(settlePolicy: SettlePolicy.trySettle);
// 3. Only use $.pump() when you need manual frame control
```

#### Section 12 — Anti-Patterns (must include)

- `setUp()` instead of `patrolSetUp()` — vanilla `setUp` does not wire into Patrol's native automation lifecycle; causes intermittent failures on iOS
- `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` — fatal double-init; remove entirely from Patrol test files
- `SettlePolicy.settle` as default — throws on infinite animations (loading spinners, Lottie); use `trySettle`
- `flutter test integration_test/` — runs the wrong runner; always use `patrol test`
- Calling `$.native.*` on iOS for Android-only features (`pressRecentApps()`) — compile error on iOS
- Missing permission guard — `grantPermissionWhenInUse()` without `isPermissionDialogVisible()` check fails on re-runs

---

### DOC 3: `reference/troubleshooting.md`

Ordered by frequency. Each entry: Symptom | Cause | Fix Steps | Loop Phase

[VERIFIED: PITFALLS.md — full source with GitHub issue references]

#### Issue 1 — xcodebuild Exit Code 65 (Most Common)

Symptom: `patrol build ios --simulator` fails with `xcodebuild exited with code 65`

Cause: Omnibus error covering 5 distinct sub-causes; the exit code alone is meaningless.

Fix steps:
1. Extract the first meaningful error line from the xcodebuild log (not just the exit code)
2. If `Unable to find a device matching the provided destination specifier` → simulator not booted; run `xcrun simctl boot <UDID>` and poll until "Booted"
3. If `Test runner never began executing tests after launching` → port conflict on 8081/8082; run `patrol test --test-server-port 8096 --app-server-port 8095`; confirm with `sudo lsof -i -P | grep LISTEN | grep :8081`
4. If `No podspec found` or dependency resolution errors → `cd ios && rm -rf Pods Podfile.lock && pod install`
5. If `Compiling for iOS X.Y, but module was built for iOS A.B` → align `IPHONEOS_DEPLOYMENT_TARGET` across all targets in Podfile post-install hook
6. If no clear sub-signal → clear DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData`; retry build

Loop phase: [2] Build → category 5-A

#### Issue 2 — Simulator Not Booted / Boot Race Condition

Symptom: Build or install appears to succeed but test runner hangs at "Waiting for app to start…" or fails with "Could not find simulator"

Cause: `xcrun simctl boot` is asynchronous. It returns immediately while the simulator continues booting. Patrol/xcodebuild starts before the simulator is ready.

Fix steps:
1. `xcrun simctl boot <UDID> 2>/dev/null || true`  (tolerate "already booted")
2. Poll: `until xcrun simctl list devices | grep "$UDID" | grep -q "Booted"; do sleep 1; done`
3. Verify: `xcrun simctl list devices | grep "$UDID"` should show `(Booted)`
4. Only then run build/test

Loop phase: [1] Prepare environment

#### Issue 3 — CocoaPods Version Conflicts

Symptom: `CocoaPods could not find compatible versions for pod 'X'`; or build fails with linker errors mentioning pod names

Cause: Stale `Podfile.lock` after updating `pubspec.yaml` plugins; or local pod spec repo outdated after a long gap.

Fix steps (in order — do not skip ahead):
1. `flutter pub get` (regenerates iOS plugin registrant — must run first)
2. `cd ios && pod install` (usually enough)
3. If fails: `pod install --repo-update`
4. If fails: `rm -rf Pods Podfile.lock && pod install`
5. If fails: `pod cache clean --all && pod repo update && pod install`
6. NEVER run `pod update` without a specific pod name — updates all pods to latest, may introduce breaking changes

Loop phase: [2] Build → category 5-A

#### Issue 4 — xcresulttool Command Deprecated (Xcode 16+)

Symptom: `parse_failure.py` returns `{}` or null `failures` array; log contains "This command is deprecated"; all failures resolve to 5-E

Cause: `xcrun xcresulttool get --format json --path <path>` (old "get object" subcommand) is deprecated in Xcode 16 and requires `--legacy` flag. Without it, the tool either errors or returns empty output.

Fix steps:
1. Check Xcode version: `xcodebuild -version | head -1`
2. Check xcresulttool version: `xcrun xcresulttool --version` (version >= 23000 = Xcode 16+)
3. For Xcode 16+ (including Xcode 26.x): use `get test-results` subcommands:
   ```bash
   xcrun xcresulttool get test-results summary --path <path> --compact
   ```
4. If you must use the old form temporarily: `xcrun xcresulttool get --legacy --path <path> --format json`
5. Update `parse_failure.py` to detect Xcode version and branch accordingly

Verification: `xcrun xcresulttool get test-results summary --path <xcresult> --compact` should return JSON with `totalTestCount`, `passedTests`, `failedTests` fields.

Loop phase: [5] Triage — blocks triage entirely if broken; fix before any other diagnosis

#### Issue 5 — PatrolIntegrationTestBinding Double-Initialization

Symptom: `"Binding is already initialized to IntegrationTestWidgetsFlutterBinding"` crash at test startup; zero tests execute

Cause: Test file (or helper) calls `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` which conflicts with Patrol's own binding. Patrol 2.x+ auto-initializes `PatrolBinding` — a second initializer call is fatal.

Also triggered by: running Patrol tests via VSCode's built-in test runner (play button), which invokes Flutter's integration_test runner instead of the Patrol CLI.

Fix steps:
1. Remove `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` from all Patrol test files
2. Remove `WidgetsFlutterBinding.ensureInitialized()` from Patrol test `setUp`/`setUpAll`
3. Do not modify `FlutterError.onError` in Patrol test files
4. Only run tests via `patrol test`, never via `flutter test integration_test/`

Loop phase: [2]/[3] — category 5-A (configuration failure, not app logic)

#### Issue 6 — Code Signing Errors for Simulator Builds

Symptom: `patrol build ios --simulator` fails with signing errors; `No signing certificate 'iOS Development' found`; or Xcode log shows `RunnerUITests.xctest` signing step failing

Cause: `RunnerUITests` target may have `CODE_SIGNING_REQUIRED = YES` explicitly set, overriding the simulator default. Or entitlements that require real signing (Push Notifications, App Groups) are enabled even for simulator.

Fix steps:
1. In Xcode project settings for `RunnerUITests` target → Build Settings → confirm:
   - `CODE_SIGNING_REQUIRED = NO` (for simulator configurations)
   - `CODE_SIGNING_ALLOWED = NO` (for simulator configurations)
   - `CODE_SIGN_IDENTITY = ""` (empty string, not "iPhone Developer")
2. Remove entitlements that cannot be used in simulator (e.g., Push Notification entitlement)
3. Verify automatic signing is configured consistently for both `Runner` and `RunnerUITests` targets
4. After changes: `cd ios && pod install && cd ..`; then retry build

Loop phase: [2] Build → category 5-A

#### Issue 7 — "Total: 0 Tests" Silent Failure

Symptom: `patrol test` exits 0 (success) but summary shows `Total: 0`; no test output

Causes:
1. Wrong `--target` path (directory instead of file, or typo)
2. Test file uses `testWidgets()` instead of `patrolTest()`
3. Dependency conflict causing test discovery failure (Patrol issue #2573)

Fix steps:
1. Verify `--target` points to a specific `.dart` file, not a directory
2. Check test file: must use `patrolTest(...)`, not `testWidgets(...)`
3. Run `patrol doctor` to check overall environment
4. If a recent dependency was added: `flutter pub get && cd ios && pod install`
5. Run with `--verbose` flag to see test discovery output: `patrol test --target <file> --verbose`

Loop phase: [4] Decide — treat `total == 0` as 5-A failure, not success

#### Issue 8 — Stale App Binary on Simulator

Symptom: Tests fail with "widget not found" errors for UI that exists in the new code; app version shown in simulator doesn't match `pubspec.yaml`

Cause: `xcrun simctl install` can silently fail to replace an app if there's a bundle ID or entitlements conflict. The old binary remains installed.

Fix steps:
1. Explicitly uninstall before every install:
   ```bash
   xcrun simctl uninstall booted <bundle_id> 2>/dev/null || true
   xcrun simctl install booted /path/to/Runner.app
   ```
2. Verify installed version: launch app on simulator and check About screen
3. If install repeatedly fails: `xcrun simctl erase <UDID>` (factory reset simulator) — last resort

Loop phase: [2] Build & install

#### Issue 9 — arm64 Architecture Mismatch on Apple Silicon

Symptom: Build fails with `building for iOS Simulator-arm64 but attempting to link with file built for iOS Simulator-x86_64`; only on M1/M2/M3 Macs

Cause: CocoaPod only bundles one architecture slice.

Fix: Add to bottom of `ios/Podfile`:
```ruby
post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
  end
end
```
Then `cd ios && pod install`.

Loop phase: [2] Build → category 5-A

#### Issue 10 — DerivedData Stale Cache

Symptom: Cryptic Xcode errors: `Session.modulevalidation`, `no such file or directory` pointing to `.dart_tool/` or `build/`; `Module compiled with Swift X.Y cannot be imported by Swift A.B`

Cause: Stale precompiled modules in Xcode DerivedData.

Fix: `rm -rf ~/Library/Developer/Xcode/DerivedData` then retry build.

Run `flutter clean` ONLY when also seeing stale Flutter build artifacts (`.dart_tool/`, `build/` issues). Do NOT run `flutter clean` for every build failure.

Loop phase: [2] Build → category 5-D (environment/cache), not 5-A

#### Issue 11 — `patrol doctor` for First-Run Diagnosis

Always run `patrol doctor` at the start of a new project session. It checks:
- patrol_cli version
- Xcode and xcode-select configuration
- iOS simulator availability
- Flutter SDK version
- CocoaPods installation
- RunnerUITests target existence

If `patrol doctor` fails, fix those issues before attempting any build/test.

---

## Common Pitfalls

### Pitfall 1: Treating xcresulttool "get object" Output as Valid on Xcode 16+

**What goes wrong:** `parse_failure.py` silently returns empty JSON; all failures become 5-E (unknown); a11y tree is captured every iteration; loop wastes iterations on phantom unknowns.
**Why it happens:** xcresulttool deprecated `get --format json` (the old "get object" subcommand) in Xcode 16. Without `--legacy` flag it either errors or returns empty.
**How to avoid:** Always use `get test-results summary --path <path> --compact` for Xcode 16+. Guard with `xcodebuild -version` major version check.
**Warning signs:** Log contains "This command is deprecated"; `failures` array is null or empty despite visible test output.

### Pitfall 2: SettlePolicy.settle Causing Infinite Timeout on Loading Spinners

**What goes wrong:** Test hangs indefinitely at `pumpAndSettle` because `CircularProgressIndicator` or Lottie animation never stops. Eventually times out as 5-B.
**Why it happens:** `SettlePolicy.settle` calls `pumpAndSettle()` which throws if any frames are still pending after `settleTimeout`. Infinite animations always have pending frames.
**How to avoid:** Use `SettlePolicy.trySettle` as the default (in `PatrolTesterConfig`). Only use `SettlePolicy.settle` for screens you know are fully static.
**Warning signs:** `pumpAndSettle timed out` error; test hangs exactly at `settleTimeout`.

### Pitfall 3: "Widget Not Found" Misclassified as 5-C Instead of 5-B

**What goes wrong:** Agent edits app code to "add the missing widget" but the widget actually exists in the tree — it's just not hit-testable (behind overlay, clipped, opacity-0).
**Why it happens:** `expect($('Submit'), findsOneWidget)` failure looks like an assertion failure (5-C) but the root cause is timing/visibility (5-B).
**How to avoid:** Before any fix, take a11y tree snapshot. If the widget appears in the tree, it's 5-B (visibility/timing), not 5-C (app logic). The exception class is the definitive signal: `TestFailure` = 5-C, any `TimeoutException` = 5-B.
**Warning signs:** "Found 0 visible (hit-testable) widgets" in the failure message (distinct from "found 0 widgets").

### Pitfall 4: Total: 0 Tests Mistaken for All Tests Passing

**What goes wrong:** Agent concludes all tests passed and exits loop early. No tests actually ran.
**Why it happens:** `patrol test` exits 0 when it finds no tests to run. `total == 0` is indistinguishable from "all pass" unless explicitly checked.
**How to avoid:** `scripts/run_test.sh` must explicitly check `total > 0` after each run. Treat `total == 0` as category 5-A failure.
**Warning signs:** Build log shows "Test summary: Total: 0"; no `[patrolTest]` lines in server log.

---

## Code Examples

### xcresulttool — Summary Parsing (Xcode 16+)

[VERIFIED: CLI introspection — machine has Xcode 26.4, xcresulttool version 24757]

```bash
# Step 1: Get pass/fail summary
xcrun xcresulttool get test-results summary \
  --path /path/to/TestResults.xcresult \
  --compact

# Step 2: If failed, get list of all tests
xcrun xcresulttool get test-results tests \
  --path /path/to/TestResults.xcresult \
  --compact

# Step 3: Get detailed failure info for specific test
xcrun xcresulttool get test-results test-details \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# Step 4: Get activity trace (tap sequence)
xcrun xcresulttool get test-results activities \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# Schema inspection (if JSON structure is unclear at runtime)
xcrun xcresulttool get test-results summary --schema
xcrun xcresulttool get test-results tests --schema
xcrun xcresulttool get test-results test-details --schema
```

Note: `xcresulttool get test-results` is a subcommand group. Available sub-subcommands on this machine (version 24757): `summary`, `tests`, `test-details`, `activities`, `insights`, `metrics`. There is no `--format json` flag for these subcommands — they output JSON by default; `--compact` suppresses pretty-printing.

### Patrol 4.x — Complete patrolTest Structure

[VERIFIED: Context7 /leancodepl/patrol]

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolSetUp(() async {
    // setup — NOT setUp()
  });

  patrolTearDown(() async {
    // teardown — NOT tearDown()
  });

  group('Login', () {
    patrolTest(
      'user can log in with valid credentials',
      config: const PatrolTesterConfig(
        existsTimeout: Duration(seconds: 10),
        visibleTimeout: Duration(seconds: 10),
        settlePolicy: SettlePolicy.trySettle,
      ),
      ($) async {
        initApp();  // before pumpWidgetAndSettle
        await $.pumpWidgetAndSettle(const MyApp());

        await $(#emailField).enterText('user@example.com');
        await $(#passwordField).enterText('secret');
        await $(#loginButton).tap();

        expect($('Welcome'), findsOneWidget);
      },
    );
  });
}
```

### SettlePolicy — All Three Values

[VERIFIED: Context7 /leancodepl/patrol]

```dart
// settle: pumpAndSettle() — throws on infinite animation
await $(#button).tap(settlePolicy: SettlePolicy.settle);

// trySettle: pumpAndTrySettle() — pumps for settleTimeout, continues without throwing
await $(#button).tap(settlePolicy: SettlePolicy.trySettle);  // recommended default

// noSettle: pump() — single frame, use when animation must continue
await $(#button).tap(settlePolicy: SettlePolicy.noSettle);
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `$.native.*` | `$.platform.mobile.*` | Patrol 4.0 (Dec 2025) | Both work; use `$.platform.mobile` in new code |
| `integration_test/` default test dir | `patrol_test/` default | Patrol 4.0 | Scripts must target `patrol_test/` unless opt-in to old name |
| `bindingType` param in `patrolTest()` | Removed (always PatrolBinding) | Patrol 3.0 | Do not include in new test code |
| `nativeAutomation: true` param | Removed (always enabled in `patrolTest`) | Patrol 3.0 | Use `patrolWidgetTest()` for no-native tests |
| `andSettle` method on finders | `settlePolicy` parameter | patrol_finders v2 | `andSettle` removed entirely |
| `SettlePolicy.settle` as default | `SettlePolicy.trySettle` as default | patrol_finders v2 | Template default must be `trySettle` |
| `xcrun xcresulttool get --format json` | `xcrun xcresulttool get test-results summary --compact` | Xcode 16 | Old form requires `--legacy` flag; new subcommands are the canonical API |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `$.native.pressRecentApps()` is Android-only (no iOS equivalent) | DOC 2 anti-patterns | Would incorrectly flag valid iOS code; LOW risk — confirmed in FEATURES.md but not re-verified in this session |
| A2 | `PatrolTesterConfig.printLogs: true` is a valid field in Patrol 4.x | DOC 2 Section 2 | Planner would include invalid config field; Context7 shows it but could be version-gated |
| A3 | xcresulttool `get test-results metrics` subcommand is available on all Xcode 26.x machines | DOC 3 xcresulttool section | Metrics subcommand listed in CLI help on this machine; may not exist on Xcode 16.x |

If A1-A3 are wrong, the impact is limited (one config field or one API note). All critical claims (SettlePolicy values, finder API, xcresulttool subcommand syntax for summary/tests/test-details) are VERIFIED.

---

## Open Questions

1. **`xcresulttool get test-results test-details --test-id` format**
   - What we know: The `--test-id` flag takes a "Test identifier URL or identifier string" (from CLI help)
   - What's unclear: Whether the identifier format is `"ClassName/methodName()"` or a URL-form ID
   - Recommendation: In troubleshooting.md, document the string form `"RunnerUITests/ExampleTest/testSomeFeature()"` and note that `--schema` flag can show expected format at runtime

2. **Exact JSON field names in `xcresulttool get test-results summary` output**
   - What we know: STACK.md documents `totalTestCount`, `passedTests`, `failedTests`, `testFailures[]`
   - What's unclear: Exact field names for test failure details in `testFailures[]` entries on this machine's schema version (0.1.0)
   - Recommendation: `parse_failure.py` (Phase 2) should run `--schema` on first invocation to verify; troubleshooting.md notes to use `--schema` flag when structure is unclear

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode / xcodebuild | xcresulttool commands | Yes | 26.4 (Build 17E192) | — |
| xcresulttool | failure-triage.md command syntax | Yes | 24757, schema 0.1.0 | — |
| patrol_cli | patrol-patterns.md validation | Not checked | — | Docs are based on verified Context7 source |
| Flutter SDK | All docs reference it | Not checked | — | Docs specify >= 3.22 requirement |

xcresulttool subcommands verified available on this machine: `get test-results summary`, `get test-results tests`, `get test-results test-details`, `get test-results activities`, `get test-results insights`, `get test-results metrics`.

The old `get object` subcommand is deprecated (listed in help as deprecated, recommending `get test-report` instead). All docs must use the `get test-results` subcommand group.

---

## Validation Architecture

The three reference docs produced in Phase 1 are Markdown content — not code. Automated testing does not apply. Validation is qualitative:

**Phase 1 gate criteria (manual):**
1. failure-triage.md: every signal row in the Quick-Reference Table matches exactly one category; all 5 categories (5-A through 5-E) have detail blocks; xcresulttool commands are exact CLI-verified syntax
2. patrol-patterns.md: all 6 finder argument types present; all 3 SettlePolicy values documented; `$.native` and `$.platform.mobile` both shown; anti-patterns section present
3. troubleshooting.md: at least 10 issues ordered by frequency; each issue has Symptom + Cause + numbered Fix steps + Loop Phase mapping; `patrol doctor` mentioned for first-run

---

## Security Domain

Not applicable to this phase. Phase 1 produces Markdown reference documents only — no code, no network calls, no credentials, no user input handling. ASVS categories V2-V6 do not apply.

---

## Sources

### Primary (HIGH confidence — verified in this session)
- Context7 `/leancodepl/patrol` — SettlePolicy enum values and mapping to pumpAndSettle/pumpAndTrySettle/pump; finder types (String, RegExp, Type, Symbol, Key, IconData); PatrolFinder actions (tap, longPress, enterText, scrollTo, waitUntilVisible, waitUntilExists, .text, .exists, .visible); patrolSetUp/patrolTearDown lifecycle; PatrolTesterConfig fields; patrolTest/patrolWidgetTest distinction; $.platform.mobile vs $.native API surface; Patrol 4.0 breaking changes (removed bindingType, nativeAutomation params; renamed patrol_test/ dir; patrol_finders v2 changes)
- xcresulttool CLI introspection — `xcrun xcresulttool help`, `xcrun xcresulttool get --help`, `xcrun xcresulttool get test-results --help`, `xcrun xcresulttool get test-results summary --help`, `xcrun xcresulttool get test-results test-details --help` on machine with Xcode 26.4 / xcresulttool 24757
- `.planning/research/FEATURES.md` — complete 5-A through 5-E signal patterns with exception class names; signal/category/action quick-reference table; Patrol finder API code examples
- `.planning/research/PITFALLS.md` — C-1 through C-7 critical pitfalls; M-1 through M-7 moderate pitfalls; loop-phase warning table
- `.planning/research/STACK.md` — xcresulttool Xcode 16+ breaking change documentation; patrol_cli 4.3.1 commands; iOS native setup requirements

### Secondary (MEDIUM confidence)
- `.planning/phases/01-reference-documentation/01-CONTEXT.md` — locked decisions for all three docs; integration points (which loop step reads each doc)
- `.planning/REQUIREMENTS.md` — REF-01, REF-02, REF-03 acceptance criteria
- `reference/iteration-protocol.md` — loop phase numbers [0]–[7] used as references in all three docs

### Tertiary (LOW confidence)
- None — all claims in this research are HIGH or MEDIUM confidence with verified sources

---

## Metadata

**Confidence breakdown:**
- failure-triage.md content: HIGH — all signal patterns verified in FEATURES.md (which cited 10+ GitHub issues); xcresulttool commands verified via CLI on this machine
- patrol-patterns.md content: HIGH — all finder types, SettlePolicy values, and interaction methods verified via Context7 live docs
- troubleshooting.md content: HIGH for 5-A/5-D issues (verified in PITFALLS.md with issue references); MEDIUM for exact xcresulttool field names in JSON output (schema version 0.1.0 — field names should be verified when first xcresult is parsed)

**Research date:** 2026-04-24
**Valid until:** 2026-05-24 for Patrol API (stable); 2026-05-08 for xcresulttool CLI (Xcode releases are frequent)
