# iOS Troubleshooting Reference

This document is used during iteration loop step **[6] Fix** for failure categories **5-A (build failure)** and **5-D (environment/cache failure)**.

Issues are ordered by frequency — check the top entries first. Execute fix steps in order — do not skip steps and do not jump ahead.

---

## First-Run Diagnosis: patrol doctor

Always run `patrol doctor` at the start of a new project session before attempting any build or test. It checks all six prerequisites in one command:

1. `patrol_cli` version (must be installed and on PATH)
2. Xcode and `xcode-select` configuration
3. iOS simulator availability
4. Flutter SDK version (>= 3.22 required)
5. CocoaPods installation
6. `RunnerUITests` target existence in the Xcode project

```bash
patrol doctor
```

If `patrol doctor` reports any failures, fix those issues before attempting any build or test. A clean `patrol doctor` output is the prerequisite for all subsequent steps.

---

## Issue 1 — xcodebuild Exit Code 65 (Most Common)

**Symptom:** `patrol build ios --simulator` fails with:
```
xcodebuild exited with code 65
```

**Cause:** Exit code 65 is an omnibus error — it covers at least 5 distinct sub-causes. The exit code alone tells you nothing. You must read the xcodebuild log to find the actual cause.

**Fix Steps:**

1. Extract the first meaningful error line from the xcodebuild log output (not just the exit code line). Look for lines starting with `error:` or containing recognizable substrings below.

2. **Sub-cause: Simulator not booted**
   - Log snippet: `Unable to find a device matching the provided destination specifier`
   - Fix: Boot the simulator and poll until ready:
     ```bash
     xcrun simctl boot <UDID> 2>/dev/null || true
     until xcrun simctl list devices | grep "$UDID" | grep -q "Booted"; do
       sleep 1
     done
     ```

3. **Sub-cause: Port conflict on 8081/8082**
   - Log snippet: `Test runner never began executing tests after launching`
   - Fix: Use alternate ports. Check what is holding the port first:
     ```bash
     sudo lsof -i -P | grep LISTEN | grep :8081
     patrol test --test-server-port 8096 --app-server-port 8095 --target <file>
     ```

4. **Sub-cause: Stale or missing CocoaPods**
   - Log snippet: `No podspec found` or linker errors mentioning pod names
   - Fix:
     ```bash
     cd ios && rm -rf Pods Podfile.lock && pod install && cd ..
     ```

5. **Sub-cause: Deployment target mismatch**
   - Log snippet: `Compiling for iOS X.Y, but module was built for iOS A.B`
   - Fix: Align `IPHONEOS_DEPLOYMENT_TARGET` across all targets in your `ios/Podfile` post-install hook:
     ```ruby
     post_install do |installer|
       installer.pods_project.targets.each do |target|
         target.build_configurations.each do |config|
           config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
         end
       end
     end
     ```
     Then run `cd ios && pod install`.

6. **Sub-cause: No clear sub-signal found**
   - Fix: Clear DerivedData and retry:
     ```bash
     rm -rf ~/Library/Developer/Xcode/DerivedData
     ```
   - Then retry the build. If it fails again with the same code 65, re-read the log carefully — a sub-cause was missed.

**Loop Phase:** [2] Build — category **5-A**

---

## Issue 2 — Simulator Not Booted / Boot Race Condition

**Symptom:** Build or install appears to succeed but the test runner hangs at "Waiting for app to start..." or fails with:
```
Could not find simulator
```
or the process hangs indefinitely with no output.

**Cause:** `xcrun simctl boot` is asynchronous. It returns immediately while the simulator continues booting in the background. If `patrol test` or `xcodebuild` starts before the simulator UI is ready, the session fails. This is a timing issue, not a code issue.

**Fix Steps:**

1. Boot the simulator, tolerating "already booted" gracefully:
   ```bash
   xcrun simctl boot <UDID> 2>/dev/null || true
   ```

2. Poll until the simulator reaches "Booted" state (not just "Booting"):
   ```bash
   until xcrun simctl list devices | grep "$UDID" | grep -q "Booted"; do
     sleep 1
   done
   ```

3. Verify the simulator is ready:
   ```bash
   xcrun simctl list devices | grep "$UDID"
   # Expected output: iPhone 16 (UDID) (Booted)
   ```

4. Only after seeing "(Booted)" should you run any build or test command.

**Loop Phase:** [1] Prepare environment

---

## Issue 3 — CocoaPods Version Conflicts

**Symptom:**
```
CocoaPods could not find compatible versions for pod 'X'
```
or the build fails with linker errors that reference pod names.

**Cause:** The `Podfile.lock` has become stale after updating `pubspec.yaml` plugin versions. The locked versions conflict with what the updated plugins require. Alternatively, the local CocoaPods spec repository is outdated after a long gap between development sessions.

**Fix Steps (run in order — do not skip ahead):**

1. Regenerate the iOS plugin registrant (must happen before `pod install`):
   ```bash
   flutter pub get
   ```

2. Standard pod install (resolves most conflicts):
   ```bash
   cd ios && pod install && cd ..
   ```

3. If step 2 fails — update spec repository:
   ```bash
   cd ios && pod install --repo-update && cd ..
   ```

4. If step 3 fails — remove stale lockfile and reinstall:
   ```bash
   cd ios && rm -rf Pods Podfile.lock && pod install && cd ..
   ```

5. If step 4 fails — clean entire pod cache:
   ```bash
   cd ios && pod cache clean --all && pod repo update && pod install && cd ..
   ```

6. **NEVER run `pod update` without specifying a pod name.** `pod update` (with no arguments) updates all pods to their latest versions, which may introduce breaking changes that are unrelated to the original conflict.

**Loop Phase:** [2] Build — category **5-A**

---

## Issue 4 — xcresulttool Command Deprecated (Xcode 16+)

**Symptom:** `parse_failure.py` returns `{}` or a null `failures` array. The xcodebuild log or tool output contains:
```
This command is deprecated
```
All failures resolve to category 5-E (unknown) even when failures are visible in the Xcode UI.

**Cause:** The old `xcrun xcresulttool get --format json --path <path>` command (the "get object" subcommand) was deprecated in Xcode 16. Without the `--legacy` flag, the tool either errors or returns empty output. Because `parse_failure.py` receives empty output, it cannot classify failures, and everything defaults to 5-E. This completely blocks the triage step.

**Fix Steps:**

1. Check Xcode version:
   ```bash
   xcodebuild -version | head -1
   # Example: Xcode 26.4
   ```

2. Check xcresulttool version (version >= 23000 means Xcode 16+ behavior):
   ```bash
   xcrun xcresulttool --version
   # Example: xcresulttool version 24757
   ```

3. For Xcode 16+ (including Xcode 26.x): use the `get test-results` subcommand group:
   ```bash
   # Quick summary — most useful for triage (totalTestCount, passedTests, failedTests)
   xcrun xcresulttool get test-results summary \
     --path /path/to/TestResults.xcresult \
     --compact

   # All tests with pass/fail structure
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

   # Inspect JSON schema at runtime (when field names are unclear)
   xcrun xcresulttool get test-results summary --schema
   ```

4. If the old form is temporarily needed (e.g., compatibility shim):
   ```bash
   xcrun xcresulttool get --legacy --path /path/to/TestResults.xcresult --format json
   ```
   Note: `--legacy` is a temporary bridge — it will be removed in a future Xcode release.

5. Update `parse_failure.py` to detect the Xcode version and use the correct subcommand path. Branch on `xcresulttool --version` output: version >= 23000 uses `get test-results`; version < 23000 uses `get --format json`.

**Verification command** (should return JSON with `totalTestCount`, `passedTests`, `failedTests`):
```bash
xcrun xcresulttool get test-results summary --path <xcresult_path> --compact
```

**Loop Phase:** [5] Triage — this issue blocks triage entirely. Fix before diagnosing any other failure.

---

## Issue 5 — PatrolIntegrationTestBinding Double-Initialization

**Symptom:** Test crashes at startup with:
```
Binding is already initialized to IntegrationTestWidgetsFlutterBinding
```
Zero tests execute. The failure appears before any test logic runs.

**Cause:** A test file or setup helper calls `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`, which conflicts with Patrol's own binding initialization. Patrol 2.x and later auto-initializes `PatrolBinding` — calling a second binding initializer is fatal and crashes the test runner before any test runs.

This error is also triggered by running Patrol tests through VSCode's built-in "play" button, which invokes Flutter's `integration_test` runner instead of the Patrol CLI.

**Fix Steps:**

1. Search all Patrol test files for the offending call and remove it:
   ```dart
   // REMOVE this line from all patrol test files:
   IntegrationTestWidgetsFlutterBinding.ensureInitialized();
   ```

2. Also remove any vanilla binding initializers in `setUp` or `setUpAll` blocks:
   ```dart
   // REMOVE these from Patrol test setUp/setUpAll:
   WidgetsFlutterBinding.ensureInitialized();
   ```

3. Do not modify `FlutterError.onError` in Patrol test files — Patrol manages this internally.

4. Always run Patrol tests via the CLI, never via the Flutter test runner:
   ```bash
   # Correct:
   patrol test --target patrol_test/my_test.dart --device <UDID>

   # Wrong — triggers double-initialization:
   flutter test integration_test/my_test.dart
   ```

**Loop Phase:** [2]/[3] — category **5-A** (configuration failure, not app logic)

---

## Issue 6 — Code Signing Errors for Simulator Builds

**Symptom:**
```
No signing certificate 'iOS Development' found
```
or Xcode log shows `RunnerUITests.xctest` signing step failing. `patrol build ios --simulator` fails at the signing phase.

**Cause:** The `RunnerUITests` target may have `CODE_SIGNING_REQUIRED = YES` explicitly set, overriding the simulator default. Simulator builds do not require real code signing. Additionally, entitlements that require real certificates (Push Notifications, App Groups) may be enabled even for simulator configurations.

**Fix Steps:**

1. In Xcode, select the `RunnerUITests` target. Go to Build Settings and confirm the following for Debug (Simulator) configurations:
   - `CODE_SIGNING_REQUIRED` = `NO`
   - `CODE_SIGNING_ALLOWED` = `NO`
   - `CODE_SIGN_IDENTITY` = `""` (empty string — not "iPhone Developer")

2. Remove any entitlements that cannot function in the simulator (e.g., `aps-environment` for Push Notifications, `com.apple.developer.associated-domains` for Universal Links). These entitlements require a provisioning profile and will fail simulator signing.

3. Verify that automatic signing is configured consistently for both the `Runner` target and the `RunnerUITests` target. Mismatched team IDs cause signing errors.

4. After making project changes, reinstall pods and retry:
   ```bash
   cd ios && pod install && cd ..
   ```

**Loop Phase:** [2] Build — category **5-A**

---

## Issue 7 — "Total: 0 Tests" Silent Failure

**Symptom:** `patrol test` exits with code 0 (indicating success) but the test summary shows:
```
Total: 0
```
No test output is produced. The agent may interpret this as all tests passing.

**Causes (three distinct root causes):**

1. Wrong `--target` path — pointing at a directory instead of a specific `.dart` file, or a typo in the filename.
2. Test file uses `testWidgets()` instead of `patrolTest()` — Patrol's test discovery only registers `patrolTest()` calls.
3. Dependency conflict causing test discovery failure (Patrol issue #2573) — a recently added package breaks the test bundle compilation silently.

**Fix Steps:**

1. Verify `--target` points to a specific `.dart` file, not a directory:
   ```bash
   # Correct:
   patrol test --target patrol_test/login_test.dart

   # Wrong (directory):
   patrol test --target patrol_test/
   ```

2. Open the test file and confirm it uses `patrolTest()`:
   ```dart
   // Correct — Patrol discovers this:
   patrolTest('user can log in', ($) async { ... });

   // Wrong — Patrol ignores this:
   testWidgets('user can log in', (tester) async { ... });
   ```

3. Run `patrol doctor` to check for environment issues that block test discovery.

4. If a dependency was recently added, regenerate everything:
   ```bash
   flutter pub get && cd ios && pod install && cd ..
   ```

5. Run with `--verbose` to see test discovery output and spot the exact failure:
   ```bash
   patrol test --target patrol_test/my_test.dart --verbose
   ```

**Loop Phase:** [4] Decide — treat `total == 0` as a **5-A** failure, not success. Never proceed as if tests passed when total is zero.

---

## Issue 8 — Stale App Binary on Simulator

**Symptom:** Tests fail with "widget not found" errors for UI elements that exist in the newly built code. The app version shown in the simulator About screen does not match the version in `pubspec.yaml`.

**Cause:** `xcrun simctl install` can silently fail to replace an existing app if there is a bundle ID conflict or entitlements mismatch. The old binary remains installed and the new binary is never written. The test runner interacts with the old app version.

**Fix Steps:**

1. Explicitly uninstall the old app before every install:
   ```bash
   xcrun simctl uninstall booted <bundle_id> 2>/dev/null || true
   xcrun simctl install booted /path/to/build/ios_integ/Build/Products/Debug-iphonesimulator/Runner.app
   ```
   The `|| true` ensures the script continues if the app was not previously installed.

2. Verify the installed version by launching the app and checking the About screen. The version must match `pubspec.yaml`.

3. If install repeatedly fails — factory reset the simulator (last resort, clears all data):
   ```bash
   xcrun simctl shutdown <UDID>
   xcrun simctl erase <UDID>
   xcrun simctl boot <UDID>
   ```
   After erase, re-install the app from scratch.

**Loop Phase:** [2] Build & install

---

## Issue 9 — arm64 Architecture Mismatch on Apple Silicon

**Symptom:** Build fails with:
```
building for iOS Simulator-arm64 but attempting to link with file built for iOS Simulator-x86_64
```
This failure only occurs on M1, M2, or M3 Macs. The same project builds successfully on Intel Macs.

**Cause:** Some CocoaPods only include one architecture slice in their prebuilt binary. On Apple Silicon Macs running an arm64 simulator, the linker encounters an x86_64-only binary and fails.

**Fix:** Add a `post_install` hook to `ios/Podfile` that excludes the conflicting architecture for simulator builds:

```ruby
post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
  end
end
```

Then reinstall pods:
```bash
cd ios && pod install && cd ..
```

Note: This hook tells the simulator build to exclude `arm64` from CocoaPod binaries, forcing use of the Rosetta (x86_64) slice. This is a known workaround for pods that have not yet published fat/universal binaries.

**Loop Phase:** [2] Build — category **5-A**

---

## Issue 10 — DerivedData Stale Cache

**Symptom:** Cryptic Xcode errors that do not correspond to any recent code change:
- `Session.modulevalidation`
- `no such file or directory` pointing to paths inside `.dart_tool/` or `build/`
- `Module compiled with Swift X.Y cannot be imported by Swift A.B`

**Cause:** Xcode's DerivedData directory stores precompiled modules, build indexes, and intermediate artifacts. After Flutter version updates, SDK changes, or Xcode updates, these cached artifacts become stale and cause spurious build failures that look like code errors.

**Fix:**

1. Delete DerivedData:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```

2. Retry the build. DerivedData will be rebuilt automatically.

3. Run `flutter clean` **only** when you are also seeing stale Flutter build artifacts (`.dart_tool/` path errors or `build/` corruption). Do **not** run `flutter clean` for every build failure — it is slow and rarely necessary.

**Loop Phase:** [2] Build — category **5-D** (environment/cache, not 5-A)

Note: DerivedData issues are classified as 5-D (environment), not 5-A (build), because the fix is environmental cleanup rather than code or configuration correction.

---

## Issue 11 — `com.apple.provenance` xattr Signing Error

**Symptom:**
```
xattr: [Errno 1] Operation not permitted: 'Flutter.framework'
```
or:
```
errSecInternalComponent
```
appearing during code signing of `Flutter.framework` or other framework bundles. The build fails at the signing phase despite correct signing configuration.

**Cause:** macOS Gatekeeper places a `com.apple.provenance` extended attribute on files downloaded from the internet (quarantine). This attribute blocks the Xcode code-signing step from signing the framework. Flutter.framework downloaded via `flutter pub get` or extracted from an archive may carry this attribute.

**Fix Steps:**

1. Find the Flutter.framework location:
   ```bash
   find . -name "Flutter.framework" -type d 2>/dev/null
   # Typical location: ios/Flutter/Flutter.framework
   ```

2. Remove all extended attributes from Flutter.framework recursively:
   ```bash
   xattr -cr /path/to/Flutter.framework
   ```

3. Also clear the entire `build/` directory of xattrs (catches other quarantined frameworks):
   ```bash
   xattr -cr build/
   ```

4. Retry the build.

**Loop Phase:** [2] Build — category **5-D** (environment, not 5-A — the fix is removing a system attribute, not changing code or configuration)

---

## Common Errors to Avoid — Prohibited Actions

The following actions are frequently attempted but are incorrect. They either mask the real problem, introduce new problems, or waste iterations.

| Prohibited Action | Why It Is Wrong | Correct Approach |
|---|---|---|
| Running `flutter clean` for every build failure | Slow and rarely fixes the actual issue; masks the real sub-cause | Only run `flutter clean` for category 5-D (stale cache) when `.dart_tool/` or `build/` artifacts are confirmed stale |
| Retrying the build without reading the log first | The same cause produces the same failure; retrying wastes an iteration | Extract the first `error:` line from the xcodebuild log and match it to a sub-cause before retrying |
| Running `pod update` without a pod name | Updates all pods to latest versions; may introduce unrelated breaking changes | Run `pod update <specific_pod_name>` only when you know which pod needs updating |
| Editing Dart or test code to fix a 5-A or 5-D failure | 5-A and 5-D failures are in the build environment, not in code logic | Fix the Xcode project, Podfile, PATH, or environment as described in the relevant issue above |
| Making speculative UI fixes for 5-E failures without taking the a11y tree first | The widget state is unknown — speculative changes waste iterations and may make things worse | Always run `scripts/sim_snapshot.sh --tree` before any fix attempt for category 5-E |
| Running `pod install` without running `flutter pub get` first | `pod install` uses the iOS plugin registrant generated by `flutter pub get`; stale registrant causes pod resolution errors | Always run `flutter pub get` before `cd ios && pod install` |

---

## Quick xcresulttool Reference (Xcode 16+ / xcresulttool >= 23000)

The following commands are the canonical API for Xcode 16 and later. Do **not** use `xcrun xcresulttool get --format json` (the old "get object" subcommand) without `--legacy`.

```bash
# Get pass/fail summary — use this first for triage
xcrun xcresulttool get test-results summary \
  --path /path/to/TestResults.xcresult \
  --compact

# Get full test list with pass/fail per test
xcrun xcresulttool get test-results tests \
  --path /path/to/TestResults.xcresult \
  --compact

# Get failure details for a specific test
xcrun xcresulttool get test-results test-details \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# Get activity log (tap/swipe trace)
xcrun xcresulttool get test-results activities \
  --path /path/to/TestResults.xcresult \
  --test-id "RunnerUITests/ExampleTest/testSomeFeature()" \
  --compact

# Inspect JSON schema at runtime
xcrun xcresulttool get test-results summary --schema
xcrun xcresulttool get test-results tests --schema
xcrun xcresulttool get test-results test-details --schema
```

The `.xcresult` bundle is written to `DerivedData` by default. The exact path varies; search with:
```bash
find ~/Library/Developer/Xcode/DerivedData -name "*.xcresult" -newer /tmp -maxdepth 6 2>/dev/null
```

---

## Loop Phase Summary

| Issue | Loop Phase | Category |
|---|---|---|
| Issue 1 — xcodebuild exit code 65 | [2] Build | 5-A |
| Issue 2 — Simulator not booted / race condition | [1] Prepare environment | — |
| Issue 3 — CocoaPods version conflicts | [2] Build | 5-A |
| Issue 4 — xcresulttool deprecated (Xcode 16+) | [5] Triage | 5-D blocks triage |
| Issue 5 — PatrolIntegrationTestBinding double-init | [2]/[3] | 5-A |
| Issue 6 — Code signing errors for simulator builds | [2] Build | 5-A |
| Issue 7 — "Total: 0 Tests" silent failure | [4] Decide | 5-A |
| Issue 8 — Stale app binary on simulator | [2] Build & install | — |
| Issue 9 — arm64 architecture mismatch (Apple Silicon) | [2] Build | 5-A |
| Issue 10 — DerivedData stale cache | [2] Build | 5-D |
| Issue 11 — com.apple.provenance xattr signing error | [2] Build | 5-D |
