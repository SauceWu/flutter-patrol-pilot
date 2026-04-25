# Patrol 4.x Patterns Cheatsheet

**Usage:** This document is consulted at iteration loop step [0] (generate test) and step [6] (fix test).
All examples reflect Patrol 4.x APIs (patrol_cli 4.3.x — verified against 4.3.1 — patrol Flutter package 4.x).
When generating or repairing test code, treat this cheatsheet as the authoritative reference.
Do not rely on training data for Patrol API surface — agents frequently hallucinate vanilla `find.byText()` calls
and omit `$.platform.mobile` in favor of non-existent alternatives.

---

## Section 1 — Imports

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
```

For widget-only tests that do not require native automation, use `patrolWidgetTest()` with the same imports.
For full native automation (permissions, notifications, system toggles), use `patrolTest()`.

---

## Section 2 — Test Structure

Complete `patrolTest` skeleton with all `PatrolTesterConfig` fields:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  // NOTE: patrolSetUp — NOT setUp().
  // Vanilla setUp() does not integrate with Patrol's native automation lifecycle.
  // Use patrolSetUp for anything that interacts with the simulator or native layer.
  patrolSetUp(() async {
    // Runs before each patrolTest in this file.
    // Use for: clear shared prefs, reset auth state, configure mocks.
    // Safe to call platform APIs here (e.g., reset permissions state).
  });

  // NOTE: patrolTearDown — NOT tearDown().
  patrolTearDown(() async {
    // Runs after each patrolTest in this file.
    // Use for: cleanup app state, close notifications, reset toggles.
  });

  group('FeatureName', () {
    patrolTest(
      'description: user can X and should see Y',
      config: const PatrolTesterConfig(
        existsTimeout: Duration(seconds: 10),
        visibleTimeout: Duration(seconds: 10),
        settleTimeout: Duration(seconds: 10),
        settlePolicy: SettlePolicy.trySettle,       // recommended default
        dragDuration: Duration(milliseconds: 100),
        settleBetweenScrollsTimeout: Duration(seconds: 5),
        printLogs: true,
      ),
      ($) async {
        // ORDERING RULE: initApp() MUST be called BEFORE pumpWidgetAndSettle.
        // Calling it after will miss test-mode initializer side effects.
        // initApp();   // uncomment if the project has a test-mode initializer

        // Pump the widget tree and wait for it to settle.
        await $.pumpWidgetAndSettle(const MyApp());

        // Test steps go here.
        // Assertions go here.
      },
    );
  });
}
```

**Key notes:**
- `patrolSetUp` / `patrolTearDown` — NOT `setUp` / `tearDown`. Vanilla lifecycle hooks do not
  wire into Patrol's native automation lifecycle and cause intermittent failures on iOS.
- `initApp()` must be called BEFORE `pumpWidgetAndSettle`, never after.
- Patrol 4.0 removed the `bindingType` and `nativeAutomation` parameters from `patrolTest()`.
  Do not include them in any generated or repaired test code.
- Use `patrolWidgetTest()` (not `patrolTest()`) when native automation is not needed —
  it is lighter-weight and avoids native automation setup.

---

## Section 3 — Finders — `$()` Parameter Types

The `$()` callable creates a `PatrolFinder`. It accepts six distinct argument types:

```dart
// 1. String — exact text match
$('Log in')
$('Subscribe')

// 2. RegExp — pattern match against widget text
$(RegExp(r'Welcome.*'))
$(RegExp(r'^\d+ items?$'))

// 3. Type — match by widget type
$(TextField)
$(ElevatedButton)
$(ListView)
$(Scaffold)
$(ListTile)
$(Card)

// 4. Symbol — preferred shorthand; no Key() wrapper needed
$(#submitButton)    // equivalent to $(const Key('submitButton'))
$(#emailInput)
$(#loginButton)

// 5. Key — explicit Key object when Symbol shorthand is insufficient
$(const Key('my-button'))
$(Key('dynamic-$id'))

// 6. IconData — find by icon
$(Icons.add)
$(Icons.close)
$(Icons.arrow_back)

// Bonus: Semantics label — use find.bySemanticsLabel() as the argument
$(find.bySemanticsLabel('Edit profile'))
$(find.bySemanticsLabel('Close dialog'))
```

**Rule:** Prefer Symbol shorthand `$(#key)` when the widget has a semantic key — it is the most
readable and least fragile form. Use String finders for visible text labels. Use Type finders
to scope chains (see Section 4).

---

## Section 4 — Chained Finders

Patrol finders can be chained to narrow scope. Chaining replaces the need for complex `find.descendant()` calls.

```dart
// Find text inside a specific widget type
await $(ListView).$('Subscribe').tap();
await $(ListView).$(ListTile).$('Subscribe').tap();

// Multi-level chain — narrow by parent, then by key, then by text
await $(Scaffold).$(#box1).$('Log in').tap();

// containing() — find a parent widget that has a descendant matching a condition
// The outer widget must CONTAIN the inner pattern.
await $(ListTile).containing('Activated').$(#learnMore).tap();

// Multiple containing() filters — parent must contain ALL specified descendants
await $(Scrollable).containing(ElevatedButton).containing(Text).tap();

// Nested containing — combine $ finders inside containing()
await $(Scrollable).containing($(TextButton).$(Text)).tap();
```

**When to use `containing()` vs chaining:**
- Chain (`$(A).$(B)`) — A is the outer scope, B is searched within A's subtree.
- `containing(X)` — find the widget that wraps X; useful when you know the child but need the parent.

---

## Section 5 — Index Selection — `.at(n)` / `.first` / `.last`

When multiple widgets match a finder, use index selection to target a specific one.

```dart
await $(TextButton).at(0).tap();    // first match (0-indexed)
await $(TextButton).at(2).tap();    // third match (0-indexed)
await $(TextButton).first.tap();    // first match (equivalent to .at(0))
await $(TextButton).last.tap();     // last match in the widget tree

// Combine with chaining
await $(ListView).$(TextButton).at(1).tap();

// Combine with containing()
await $(ListTile).containing('Pro').$(ElevatedButton).first.tap();
```

---

## Section 6 — Predicate Filter — `.which<T>()`

Use `.which<T>()` to filter finders by arbitrary widget properties. The type parameter `T`
must match the widget type of the finder.

```dart
// Tap only the enabled ElevatedButton
await $(ElevatedButton)
    .which<ElevatedButton>((btn) => btn.enabled)
    .tap();

// Find a Text widget with a specific style
await $(Text)
    .which<Text>((t) => t.style?.color == Colors.red)
    .waitUntilVisible();

// Find a TextField with a specific hint text
await $(TextField)
    .which<TextField>((f) => f.decoration?.hintText == 'Email')
    .enterText('user@example.com');

// Combine .which() with index selection
await $(ElevatedButton)
    .which<ElevatedButton>((btn) => btn.enabled)
    .first
    .tap();
```

---

## Section 7 — Interactions

All interaction methods wait for the widget to be visible before acting (unlike raw `tester.tap()`).
Each method accepts optional `settlePolicy`, `visibleTimeout`, and `settleTimeout` overrides.

```dart
// --- Tap ---
await $(#loginButton).tap();
await $(#button).tap(
  settlePolicy: SettlePolicy.noSettle,
  visibleTimeout: Duration(seconds: 5),
  settleTimeout: Duration(seconds: 3),
);
await $('Submit').tap(settlePolicy: SettlePolicy.trySettle);

// --- Long Press ---
await $(#contextMenuTarget).longPress();
await $('Hold me').longPress(settlePolicy: SettlePolicy.trySettle);

// --- Enter Text (clears field first, then types) ---
await $(#emailField).enterText('user@example.com');
await $(#passwordInput).enterText('secret',
  settlePolicy: SettlePolicy.trySettle);
await $(TextField).at(0).enterText('first name');

// --- Scroll ---
// Scroll until widget becomes visible, then tap
await $('Delete account').scrollTo().tap();

// Scroll until widget is visible, then stop
await $('Terms of Service').scrollTo();

// Full control over scroll direction, container, and limit
await $(#bottomItem).scrollTo(
  view: find.byType(ListView),
  scrollDirection: AxisDirection.down,
  maxScrolls: 20,
);

// Scroll horizontally
await $(#rightPanel).scrollTo(
  scrollDirection: AxisDirection.right,
  maxScrolls: 10,
);

// --- Wait for existence in tree (not necessarily visible) ---
await $(#loadingIndicator).waitUntilExists();
await $(#dataRow).waitUntilExists(timeout: Duration(seconds: 20));

// --- Wait for visibility (hit-testable) ---
await $(#contentLoaded).waitUntilVisible();
await $(#contentLoaded).waitUntilVisible(timeout: Duration(seconds: 15));

// --- Get text from a Text widget ---
final label = $(#welcomeMessage).text;
final buttonLabel = $('Submit').text;
```

---

## Section 8 — Assertions

Patrol finders work with all standard `flutter_test` matchers. Additionally, Patrol adds
`.exists` and `.visible` boolean properties for non-blocking checks.

```dart
// Standard flutter_test matchers
expect($('Log in'), findsOneWidget);
expect($('Log in'), findsNothing);
expect($(Card), findsNWidgets(3));
expect($(Card), findsWidgets);          // one or more

// .exists — non-blocking boolean property, no timeout, checks widget tree presence
expect($(#myWidget).exists, isTrue);
expect($('Error message').exists, isFalse);
if ($(#optionalBanner).exists) {
  await $(#optionalBanner).tap();
}

// .visible — checks hit-testability (not just tree presence)
// A widget can exist in the tree but not be visible (clipped, opacity-0, behind overlay).
expect($('Log in').visible, isTrue);
expect($('Log in').visible, equals(true));
if ($('Skip').visible) {
  await $('Skip').tap();
}

// Combine with chaining for scoped assertions
expect($(ListView).$('Subscribe'), findsOneWidget);
expect($(#errorBanner).$('Retry').visible, isTrue);
```

---

## Section 9 — SettlePolicy — All Values

`SettlePolicy` is an enum with exactly **3 values**. Choose based on the animation behavior of
the screen under test.

| Value | Maps to | When to Use |
|-------|---------|-------------|
| `SettlePolicy.settle` | `pumpAndSettle()` | Finite animations only. THROWS `FlutterError` if frames are still pending after `settleTimeout`. Use only when you need to guarantee a fully-settled state and know no infinite animations run. |
| `SettlePolicy.trySettle` | `pumpAndTrySettle()` | **Recommended default.** Pumps frames for `settleTimeout`, then continues WITHOUT throwing even if frames remain. Works for both finite and infinite animations (e.g., `CircularProgressIndicator`, Lottie, shimmer). |
| `SettlePolicy.noSettle` | `pump()` | Single-frame pump only. Use when the animation MUST continue (e.g., you need to observe an in-progress animation state, or you are triggering a step inside an animation). |

**Important:** The default value changed in patrol_finders v2 from `SettlePolicy.settle` to
`SettlePolicy.trySettle`. Always set `settlePolicy: SettlePolicy.trySettle` as the template
default in `PatrolTesterConfig` to avoid infinite-animation timeouts.

```dart
// Global config — set default for all actions in this test
config: const PatrolTesterConfig(
  settlePolicy: SettlePolicy.trySettle,   // recommended template default
  settleTimeout: Duration(seconds: 10),
),

// Per-action override — overrides the global config for one action
await $(#animatedButton).tap(settlePolicy: SettlePolicy.noSettle);
await $(#staticForm).tap(settlePolicy: SettlePolicy.settle);
await $(#loadingButton).tap(settlePolicy: SettlePolicy.trySettle);
```

---

## Section 10 — Native / Platform Automation — `$.platform.mobile` vs `$.native`

`$.platform.mobile` is the canonical Patrol 4.0 API. `$.native` is the older alias that maps
to the same implementation — both work. Use `$.platform.mobile` in new code; recognize `$.native`
when reading existing tests.

```dart
// --- Permissions ---
// ALWAYS guard with isPermissionDialogVisible() to handle re-runs where permission
// was already granted. Calling grant/deny when no dialog is present will throw.
if (await $.platform.mobile.isPermissionDialogVisible()) {
  await $.platform.mobile.grantPermissionWhenInUse();
  // Alternatives:
  // await $.platform.mobile.grantPermissionOnlyThisTime();
  // await $.platform.mobile.denyPermission();
}
// Precise (fine) location — call after granting permission
await $.platform.mobile.selectFineLocation();

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
await $.platform.mobile.swipeBack();      // iOS back gesture (swipe from left edge)
await $.platform.mobile.pullToRefresh();
await $.platform.mobile.pressVolumeUp();
await $.platform.mobile.pressVolumeDown();

// --- Device Info / Simulator State ---
await $.platform.mobile.setMockLocation(37.7749, -122.4194);
final bool isVirtual = await $.platform.mobile.isVirtualDevice(); // always true on simulator

// --- Old alias $.native — still works, shown here for reading existing tests ---
if (await $.native.isPermissionDialogVisible()) {
  await $.native.grantPermissionWhenInUse();
}
await $.native.pressHome();
await $.native.openNotifications();
await $.native.tapOnNotificationByIndex(0);
await $.native.swipeBack();
await $.native.enableWifi();
await $.native.disableWifi();
```

**iOS-only note:** `$.native.pressRecentApps()` is Android-only. Calling it in an iOS test
causes a **compile error** — it is not available in the iOS native automation layer. Do not
include it in any iOS-targeted test code.

---

## Section 11 — Pump / Settle

```dart
// Pump whole widget tree and settle — call once at the start of each test,
// before any interactions.
await $.pumpWidgetAndSettle(const MyApp());

// Manual single-frame pump — rarely needed; use when you need frame-level control.
await $.pump();
await $.pump(Duration(seconds: 1));    // pump frames for a duration

// Explicit settle variants — rarely needed; prefer settlePolicy parameter on actions.
await $.pumpAndSettle();              // equivalent to SettlePolicy.settle
await $.pumpAndTrySettle();           // equivalent to SettlePolicy.trySettle

// Recommended usage pattern for most tests:
// Step 1: pump the widget tree once at the start
await $.pumpWidgetAndSettle(const MyApp());
// Step 2: use settlePolicy on each action (or set globally in PatrolTesterConfig)
await $(#button).tap(settlePolicy: SettlePolicy.trySettle);
// Step 3: only call $.pump() manually when you need frame-level animation control
await $.pump(Duration(milliseconds: 200));  // advance animation by 200ms
```

---

## Section 12 — Anti-Patterns — Common Mistakes

The following patterns are incorrect in Patrol 4.x tests. Applying them causes test failures
that are difficult to diagnose because they appear as environment or timing issues, not syntax errors.

**1. Using `setUp()` instead of `patrolSetUp()`**

```dart
// WRONG — vanilla setUp() does not wire into Patrol's native automation lifecycle.
// Causes intermittent failures when setup code interacts with the simulator.
setUp(() async {
  // ...
});

// CORRECT
patrolSetUp(() async {
  // ...
});
```

**2. Calling `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`**

```dart
// WRONG — causes fatal double-initialization crash at test startup.
// Patrol 2.x+ auto-initializes PatrolBinding; a second binding init call is fatal.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized(); // REMOVE THIS
  // ...
}

// CORRECT — remove the line entirely. Patrol handles binding initialization.
void main() {
  patrolSetUp(() async { ... });
  // ...
}
```

**3. Using `SettlePolicy.settle` as the default**

```dart
// WRONG — throws FlutterError when any infinite animation is running
// (CircularProgressIndicator, Lottie, shimmer, etc.)
config: const PatrolTesterConfig(
  settlePolicy: SettlePolicy.settle,  // dangerous default
),

// CORRECT — trySettle pumps for settleTimeout then continues without throwing.
config: const PatrolTesterConfig(
  settlePolicy: SettlePolicy.trySettle,  // recommended default
),
```

**4. Running tests via `flutter test integration_test/` instead of `patrol test`**

```bash
# WRONG — runs Flutter's integration_test runner, not Patrol's runner.
# Loses native automation, permission handling, and Patrol lifecycle hooks.
flutter test integration_test/

# WRONG — also wrong; does not trigger PatrolBinding setup.
flutter test patrol_test/

# CORRECT — always use the patrol CLI.
patrol test --target patrol_test/my_test.dart --device-id <UDID>
```

**5. Calling Android-only native APIs on iOS**

```dart
// WRONG — pressRecentApps() is Android-only.
// This causes a COMPILE ERROR on iOS — the method does not exist in the iOS layer.
await $.native.pressRecentApps();      // compile error on iOS
await $.platform.mobile.pressRecentApps();  // compile error on iOS

// CORRECT — check whether the API has an iOS equivalent.
// For iOS back-navigation, use swipeBack():
await $.platform.mobile.swipeBack();  // iOS-compatible
```

**6. Missing permission dialog guard**

```dart
// WRONG — if permission was already granted on a previous run,
// no dialog appears and this call throws.
await $.platform.mobile.grantPermissionWhenInUse();

// CORRECT — always check first. The guard makes the test idempotent across re-runs.
if (await $.platform.mobile.isPermissionDialogVisible()) {
  await $.platform.mobile.grantPermissionWhenInUse();
}
```

---

## Section 13 — Patrol 4.x API Changes Quick Reference

| Old API | Current API | Status | Notes |
|---------|-------------|--------|-------|
| `$.native.*` | `$.platform.mobile.*` | Both valid | `$.native` is an alias; use `$.platform.mobile` in new code |
| `integration_test/` test directory | `patrol_test/` test directory | Changed in 4.0 | Scripts must target `patrol_test/` unless project opted into old name |
| `patrolTest(..., bindingType: ...)` | `patrolTest(...)` — no `bindingType` | Removed in 4.0 | PatrolBinding is always used; param removed entirely |
| `patrolTest(..., nativeAutomation: true)` | `patrolTest(...)` — always enabled | Removed in 4.0 | Use `patrolWidgetTest()` for no-native tests |
| `$(finder).andSettle` method on finders | `settlePolicy` parameter on actions | Removed in patrol_finders v2 | Pass `settlePolicy:` to `tap()`, `enterText()`, etc. |
| `SettlePolicy.settle` as default | `SettlePolicy.trySettle` as default | Changed in patrol_finders v2 | Template default MUST be `trySettle` |

---

## Appendix — Complete Working Test Example

This is a fully-correct, copy-pasteable Patrol 4.x test using all major patterns:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolSetUp(() async {
    // Reset any persisted auth state before each test.
    // initApp();  // uncomment if project has test-mode initializer
  });

  patrolTearDown(() async {
    // Clean up after each test.
  });

  group('Login Feature', () {
    patrolTest(
      'user can log in with valid credentials and see welcome screen',
      config: const PatrolTesterConfig(
        existsTimeout: Duration(seconds: 10),
        visibleTimeout: Duration(seconds: 10),
        settleTimeout: Duration(seconds: 10),
        settlePolicy: SettlePolicy.trySettle,
        dragDuration: Duration(milliseconds: 100),
        settleBetweenScrollsTimeout: Duration(seconds: 5),
        printLogs: true,
      ),
      ($) async {
        await $.pumpWidgetAndSettle(const MyApp());

        // Finder types demonstration
        await $(#emailField).enterText('user@example.com');           // Symbol
        await $(#passwordField).enterText('secret');                   // Symbol
        await $('Log in').tap();                                       // String

        // Assertion
        expect($('Welcome, User'), findsOneWidget);
        expect($('Welcome, User').visible, isTrue);

        // Permission guard pattern
        if (await $.platform.mobile.isPermissionDialogVisible()) {
          await $.platform.mobile.grantPermissionWhenInUse();
        }
      },
    );

    patrolTest(
      'user sees error when credentials are invalid',
      config: const PatrolTesterConfig(
        settlePolicy: SettlePolicy.trySettle,
      ),
      ($) async {
        await $.pumpWidgetAndSettle(const MyApp());

        // Chain + index selection
        await $(ListView).$(TextField).at(0).enterText('bad@example.com');
        await $(ListView).$(TextField).at(1).enterText('wrongpassword');

        // which() predicate filter
        await $(ElevatedButton)
            .which<ElevatedButton>((btn) => btn.enabled)
            .tap();

        // containing() chain
        await $(Card).containing('Error').$(#retryButton).tap();

        // .exists non-blocking check
        expect($('Invalid credentials').exists, isTrue);
        expect($(#welcomeBanner).exists, isFalse);
      },
    );

    patrolTest(
      'user can scroll to and tap a deep list item',
      config: const PatrolTesterConfig(
        settlePolicy: SettlePolicy.trySettle,
      ),
      ($) async {
        await $.pumpWidgetAndSettle(const MyApp());
        await $('Profile').tap();

        // Scroll to item then act
        await $('Delete Account').scrollTo(
          view: find.byType(ListView),
          scrollDirection: AxisDirection.down,
          maxScrolls: 30,
        );
        await $('Delete Account').tap();

        // RegExp finder
        expect($(RegExp(r'Are you sure.*')), findsOneWidget);
      },
    );
  });
}
```
