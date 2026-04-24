// patrol_test_template.dart
// ──────────────────────────────────────────────────────────────────────────────
// Copy this file into your patrol_test/ directory and rename it.
// Requires: flutter pub add patrol --dev && dart pub global activate patrol_cli
// Run with: patrol test --target patrol_test/your_test_name.dart
// ──────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

// Import your app's main entry point:
// import 'package:your_app/main.dart';

// ── Optional: app initialization ─────────────────────────────────────────────
// If your app needs test-mode initialization (e.g. mock services, feature flags)
// define initApp() here or import it from a test helper:
//
// void initApp() {
//   // e.g. HttpOverrides.global = MockHttpOverrides();
// }

void main() {
  // ── File-level setup / teardown ─────────────────────────────────────────────
  // Use patrolSetUp / patrolTearDown — NOT setUp / tearDown.
  // Vanilla setUp() does not integrate with Patrol's native automation lifecycle.

  patrolSetUp(() async {
    // Runs before each patrolTest in this file.
    // e.g. clear SharedPreferences, reset auth state, seed test data.
  });

  patrolTearDown(() async {
    // Runs after each patrolTest in this file.
    // e.g. sign out, clear caches.
  });

  // ── Test group ──────────────────────────────────────────────────────────────
  group('FeatureName', () {
    patrolTest(
      'user can [action] and should see [outcome]',

      // ── Tester config ────────────────────────────────────────────────────────
      // settlePolicy: SettlePolicy.trySettle is the recommended default.
      // It pumps frames during settleTimeout and does NOT throw if frames are
      // still pending — safe for infinite animations (loading spinners, Lottie).
      //
      // Use SettlePolicy.settle only when you need guaranteed full-settle and
      // there are no infinite animations.
      config: const PatrolTesterConfig(
        existsTimeout: Duration(seconds: 10),
        visibleTimeout: Duration(seconds: 10),
        settleTimeout: Duration(seconds: 10),
        settlePolicy: SettlePolicy.trySettle, // recommended default
        dragDuration: Duration(milliseconds: 100),
        settleBetweenScrollsTimeout: Duration(seconds: 5),
        printLogs: true,
      ),

      ($) async {
        // ── 1. Initialize app (if needed) ─────────────────────────────────────
        // initApp() must be called BEFORE pumpWidgetAndSettle, not after.
        // initApp();

        // ── 2. Pump the widget tree ───────────────────────────────────────────
        // Replace MyApp() with your app's root widget.
        // await $.pumpWidgetAndSettle(const MyApp());

        // ── 3. Interact ───────────────────────────────────────────────────────
        // Finder examples — see reference/patrol-patterns.md for full reference:
        //
        //   $('Button text')          // String match
        //   $(#semanticsKey)          // Symbol key (preferred)
        //   $(ElevatedButton)         // Widget type
        //   $(Icons.add)              // IconData
        //   $(RegExp(r'Item \d+'))    // RegExp
        //
        // await $('Log in').tap();
        // await $(#emailInput).enterText('user@example.com');
        // await $('Submit').scrollTo().tap();

        // ── 4. Native interactions (iOS) ──────────────────────────────────────
        // Use $.platform.mobile for native automation (Patrol 4.x canonical API).
        // $.native is an alias that also works but $.platform.mobile is preferred.
        //
        // if (await $.platform.mobile.isPermissionDialogVisible()) {
        //   await $.platform.mobile.grantPermissionWhenInUse();
        // }
        // await $.platform.mobile.pressHome();
        // await $.platform.mobile.openApp(appId: 'com.example.yourapp');

        // ── 5. Assert ─────────────────────────────────────────────────────────
        // RULE: Never change the expected value in expect() to make a test pass.
        // If expect() fails, the app behavior is wrong — fix the app, not the test.
        //
        // expect($('Welcome'), findsOneWidget);
        // expect($('Error'), findsNothing);
        // expect($(Card), findsNWidgets(3));
        // expect($('Submit').visible, isTrue);
      },
    );
  });
}
