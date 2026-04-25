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

## Issue 12 — `Module 'patrol' not found` in RunnerUITests

**Symptom:** Compiling `RunnerUITests.m` in Xcode (or via `xcodebuild`) fails with:
```
RunnerUITests.m:2:9: fatal error: module 'patrol' not found
@import patrol;
        ^
```

**Cause:** The `RunnerUITests` target was added to `Runner.xcodeproj` (manually in Xcode GUI, or by the patrol setup doc), but the project `Podfile` has no matching `target 'RunnerUITests'` block. Without it, `pod install` never generates `Pods-Runner-RunnerUITests.xcconfig`, and the `patrol.framework` is never linked into the UI test binary — hence `@import patrol` cannot resolve.

**Fix Steps:**

1. Open `ios/Podfile` and ensure the `Runner` target declaration uses modular headers and nests `RunnerUITests` with `inherit! :complete` (NOT `:search_paths`, which is for unit tests):
   ```ruby
   target 'Runner' do
     use_frameworks!
     use_modular_headers!      # required so `@import patrol` resolves

     flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

     target 'RunnerTests' do
       inherit! :search_paths
     end

     target 'RunnerUITests' do
       inherit! :complete      # pulls patrol.framework into the UITests binary
     end
   end
   ```

2. Re-run `pod install`:
   ```bash
   cd ios && pod install
   ```

3. Confirm the generated xcconfig exists:
   ```bash
   ls "ios/Pods/Target Support Files/Pods-Runner-RunnerUITests/"
   # must contain Pods-Runner-RunnerUITests.{debug,release,profile}.xcconfig
   ```

4. Retry `patrol build ios --simulator`. **Do NOT press Cmd+B in Xcode to test compilation** — `RunnerUITests.m` uses `PATROL_INTEGRATION_TEST_IOS_RUNNER()`, whose macro expansion depends on `-D CLEAR_PERMISSIONS=...` and `-D FULL_ISOLATION=...` flags that only `patrol build` / `patrol test` inject. Xcode GUI builds will always fail with `use of undeclared identifier 'CLEAR_PERMISSIONS'`. This is expected — not a bug.

**Loop Phase:** [1] Prepare environment (one-time setup) — category **5-A**

---

## Issue 13 — CocoaPods Fails on `objectVersion '70'` (Xcode 26+)

**Symptom:** `pod install` fails with:
```
[Xcodeproj] Unable to find compatibility version string for object version '70'
```

**Cause:** Xcode 26 writes `project.pbxproj` with `objectVersion = 70` (the new synced-folder format). CocoaPods's `xcodeproj` gem (up to 1.27.0, as shipped with CocoaPods 1.16.2) only understands up to objectVersion 63. When Xcode 26 auto-upgrades the project file — which happens the first time you add a target in the GUI — subsequent `pod install` runs break.

Cross-reference: CocoaPods issues [#12840](https://github.com/CocoaPods/CocoaPods/issues/12840) and [#12889](https://github.com/CocoaPods/CocoaPods/issues/12889).

**Fix Steps:**

1. Check the current object version:
   ```bash
   rg -n "objectVersion" ios/Runner.xcodeproj/project.pbxproj | head -1
   # if it reports 70, this issue applies
   ```

2. Downgrade the project format (safe — Xcode 26 still opens projects at version 60):
   ```bash
   cp ios/Runner.xcodeproj/project.pbxproj ios/Runner.xcodeproj/project.pbxproj.bak-v70
   sed -i '' 's/objectVersion = 70;/objectVersion = 60;/' ios/Runner.xcodeproj/project.pbxproj
   ```

3. Re-run `pod install`. It should now complete.

4. Note: Flutter's `patrol build ios` invokes `flutter build` which internally calls "Upgrading project.pbxproj" and rewrites it at a Flutter-compatible version (~54), so you typically don't need to re-run the sed step. But if you open the project in Xcode 26 and save, the version may bump again — re-apply the sed if `pod install` breaks again.

**Loop Phase:** [1] Prepare environment — category **5-D** (environment/tooling mismatch)

---

## Issue 14 — `Sandbox: mkdir deny(1) file-write-create ... RunnerUITests.xctest`

**Symptom:** `patrol build ios --simulator` fails (exit 65) with (visible only with `--verbose`):
```
error: Sandbox: mkdir(22856) deny(1) file-write-create .../RunnerUITests.xctest
  (in target 'RunnerUITests' from project 'Runner')
mkdir: ... RunnerUITests.xctest: Operation not permitted
```

**Cause:** Xcode 15+ introduced a "User Script Sandboxing" build setting (`ENABLE_USER_SCRIPT_SANDBOXING`). For any target created in the Xcode GUI on Xcode 26, the default is `YES`. When the build runs Flutter's `Thin Binary` / `xcode_backend.sh` run scripts (which need to write into `build/`), the sandbox denies the write and xcodebuild exits 65.

The Flutter SDK's bundled `Runner` target template sets this to `NO` automatically, but `RunnerUITests` — when created manually in the Xcode GUI — inherits the Xcode 26 default of `YES`.

**Fix Steps:**

1. Confirm the settings:
   ```bash
   rg -n "ENABLE_USER_SCRIPT_SANDBOXING" ios/Runner.xcodeproj/project.pbxproj
   # look for any `= YES;` lines — these are the problem
   ```

2. Flip them all to `NO`:
   ```bash
   sed -i '' 's/ENABLE_USER_SCRIPT_SANDBOXING = YES;/ENABLE_USER_SCRIPT_SANDBOXING = NO;/g' \
     ios/Runner.xcodeproj/project.pbxproj
   ```

3. Retry the build.

Alternatively, in Xcode GUI: select the `RunnerUITests` target → Build Settings → search "User Script Sandboxing" → set all three configurations (Debug/Release/Profile) to `No`.

**Loop Phase:** [2] Build — category **5-A** (build configuration)

---

## Issue 15 — "Clone 1 / Clone 2 / Clone 3" Simulators Spawned During Tests

**Symptom:** Running `patrol test --device <UDID>` (or any tooling that ends up calling `xcodebuild test-without-building`) causes Xcode to spawn several additional simulators with names like `iPhone 17 Pro Max (Clone 1)`, `… (Clone 2)`, `… (Clone 3)`. After the run (or a Ctrl+C) these clones typically disappear, but while tests are running you see multiple Simulator windows, fans spin up, and Patrol's native↔app port handshake may flake because the target app landed on a clone instead of the sim you asked for.

**Cause — this is Xcode's "Use parallel testing" feature, not a patrol bug.**

`xcodebuild test-without-building` defaults to `-parallel-testing-enabled YES`. When enabled, Xcode duplicates the destination simulator (via `simctl clone`) and distributes test classes across the clones, tearing them down when the run ends. This is useful for a large unit-test bundle; it is actively harmful for a Patrol UI test that needs a single, stable sim to drive the app.

Two independent trigger points turn this on:

1. **The Runner scheme marks testable references as parallelizable.** Look at `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`:
   ```xml
   <TestableReference
      skipped = "NO"
      parallelizable = "YES">   <!-- clones the sim per test -->
      <BuildableReference … BlueprintName = "RunnerUITests" …/>
   </TestableReference>
   ```

2. **The xctestrun Xcode emits bakes `ParallelizationEnabled = true` into each test target** (verify with `plutil -p build/ios_integ/Build/Products/Runner_iphonesimulator*.xctestrun`). `patrol_cli 4.3.x` then invokes `xcodebuild test-without-building` without passing `-parallel-testing-enabled NO` (see `~/.pub-cache/hosted/pub.dev/patrol_cli-4.3.1/lib/src/crossplatform/app_options.dart:279`), so Xcode is free to clone.

As a secondary aggravator, patrol_cli 4.3.x also passes `-destination platform=iOS Simulator,OS=<v>,name=<name>` (not `id=<UDID>`). If you happen to have several sims sharing the target's name across runtimes, xcodebuild may boot the wrong one in addition to the clones. Renaming the target sim is a tidy precaution but does NOT stop cloning — only disabling parallel testing does.

**Fix Steps (immediate recovery):**

1. Kill any active test processes and shut down every sim:
   ```bash
   pkill -9 -f xcodebuild 2>/dev/null || true
   pkill -9 -f "patrol test" 2>/dev/null || true
   pkill -9 -f RunnerUITests 2>/dev/null || true
   xcrun simctl shutdown all
   killall "Simulator" 2>/dev/null || true
   ```

2. Verify the clones are gone (they are ephemeral and usually do not appear in `simctl list devices` once shut down):
   ```bash
   xcrun simctl list devices booted   # expect: no booted sims (or only your target)
   ```

**Fix Steps (prevention) — applied by this skill since v0.3:**

1. **`scripts/run_test.sh` no longer calls `patrol test` by default.** It discovers the xctestrun produced by `patrol build ios --simulator` and drives `xcodebuild test-without-building` itself, always with:
   ```bash
   xcodebuild test-without-building \
     -xctestrun <…>.xctestrun \
     -only-testing RunnerUITests/RunnerUITests \
     -destination "id=<UDID>" \
     -parallel-testing-enabled NO \
     -disable-concurrent-destination-testing \
     -resultBundlePath .test-results/iter-N/result.xcresult
   TEST_RUNNER_PATROL_TEST_PORT=8081 \
   TEST_RUNNER_PATROL_APP_PORT=8082
   ```
   This eliminates cloning, forces `id=<UDID>` so name collisions cannot misroute the run, and hands the Patrol native server / app client the default ports they expect.

2. **`scripts/build.sh` patches the xctestrun after `patrol build` finishes**, flipping every `ParallelizationEnabled` dict key to `false`. Redundant with `-parallel-testing-enabled NO`, but the two together are belt-and-suspenders: if you later shell out to `xcodebuild` yourself and forget the flag, the xctestrun still declines to clone.

3. **(Optional) Disable parallelization in the scheme** so Xcode UI runs (not going through the skill) behave the same way. Edit `ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme` and flip both `parallelizable = "YES"` → `"NO"`:
   ```bash
   sed -i '' 's/parallelizable = "YES"/parallelizable = "NO"/g' \
     ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
   ```
   Commit the change so other contributors get the same behavior.

4. **`--isolate-sim` is a defense-in-depth flag**, not the primary fix. It shuts down any simulator that this run booted (via an EXIT trap) and proactively shuts down non-target booted sims before testing starts. With the direct `xcodebuild` path above, it is almost never needed — but it is still useful if you mix `--use-patrol` (legacy path) into a run.

5. **`--use-patrol` is the legacy escape hatch.** It routes through `patrol test` and therefore hits the clone/`name=` bugs. Only use it when debugging something unrelated to those issues.

**Loop Phase:** [1] Prepare environment — category **5-D** (environment / tooling defaults interfere with the run)

---

## Issue 16 — `Library not loaded: @rpath/_Testing_Foundation.framework` / `lib_TestingInterop.dylib` (Xcode 26 Swift Testing)

### Symptom

`xcodebuild test-without-building` (or `patrol test` on Xcode 26) hangs for ~6 minutes on:

```
t = nans Wait for <bundle_id> to idle
```

then reports:

```
Testing failed:
  RunnerUITests-Runner (<pid>) encountered an error (The test runner timed out while preparing to run tests.)
** TEST EXECUTE FAILED **
```

Manually launching the app (`xcrun simctl launch --console-pty <UDID> <bundle_id>`) reveals the true cause — a dyld linker error at startup:

```
dyld[<pid>]: Library not loaded: @rpath/_Testing_Foundation.framework/_Testing_Foundation
  Referenced from: .../Runner.app/Frameworks/libXCTestSwiftSupport.dylib
  Reason: tried [20+ paths]... (no such file)
```

or

```
dyld[<pid>]: Library not loaded: @rpath/lib_TestingInterop.dylib
  Referenced from: .../Runner.app/Frameworks/Testing.framework/Testing
```

### Root cause

Xcode 26 / Swift 6.1 introduced a new "Swift Testing" runtime layer. The stock `libXCTestSwiftSupport.dylib` and `Testing.framework` that Flutter embeds into `Runner.app/Frameworks/` now hard-depend on:

- `_Testing_Foundation.framework`
- `_Testing_CoreGraphics.framework`
- `_Testing_CoreImage.framework`
- `_Testing_UIKit.framework`
- `lib_TestingInterop.dylib`

Flutter's build pipeline (`patrol build ios` → `flutter build ios --debug --simulator`) does **not** copy these new files into the app bundle, and the iOS 26.x simruntime does **not** ship them in its system library path. Result: Runner.app dyld-crashes on launch; XCUITest never sees the app reach "idle"; 6-minute test-runner timeout.

This affects **both** `Runner.app` (the app-under-test) and `RunnerUITests-Runner.app` (the XCTRunner host) — both bundles need the fix.

### Fix — automatic (recommended)

`scripts/build.sh` (v0.3+) detects Xcode 26 and copies the missing files from the iPhoneSimulator platform into both `.app/Frameworks/` directories **before** calling `xcrun simctl install`. The log shows:

```
[build.sh] injected _Testing_Foundation.framework → Runner.app
[build.sh] injected lib_TestingInterop.dylib → Runner.app
[build.sh] injected _Testing_Foundation.framework → RunnerUITests-Runner.app
...
[build.sh] Xcode-26 Swift Testing deps: injected 10 file(s) across app bundles
```

Sources the script pulls from (change if your Xcode is non-standard):

```
/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks/_Testing_*.framework
/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/usr/lib/lib_TestingInterop.dylib
```

The script resolves the Xcode root via `xcrun --sdk iphonesimulator --show-sdk-platform-path`, so `xcode-select -s` and non-default Xcode locations Just Work.

This is a no-op on Xcode <26 (the source files don't exist, so the per-file existence check skips them).

### Fix — manual (only if build.sh is not available / CI can't run the script)

```bash
UDID=<your_sim_udid>
BUNDLE_ID=dev.example.yourapp
RUNNER_BUNDLE_ID=${BUNDLE_ID}.RunnerUITests.xctrunner   # or inspect Info.plist

APP_UNDER_TEST=$(xcrun simctl get_app_container $UDID $BUNDLE_ID)
RUNNER_APP=$(xcrun simctl get_app_container $UDID $RUNNER_BUNDLE_ID)
XCODE_FW=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks
XCODE_LIB=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/usr/lib

for app in "$APP_UNDER_TEST" "$RUNNER_APP"; do
  cp -R "$XCODE_FW/_Testing_Foundation.framework" "$app/Frameworks/"
  cp -R "$XCODE_FW/_Testing_CoreGraphics.framework" "$app/Frameworks/"
  cp -R "$XCODE_FW/_Testing_CoreImage.framework" "$app/Frameworks/"
  cp -R "$XCODE_FW/_Testing_UIKit.framework" "$app/Frameworks/"
  cp "$XCODE_LIB/lib_TestingInterop.dylib" "$app/Frameworks/"
done
```

Note: `xcrun simctl install` strips and re-copies the app bundle, so any frameworks injected this way to the sim container are lost on next install. Inject into the **build output** (`build/ios_integ/Build/Products/Debug-iphonesimulator/*.app/Frameworks/`) before `simctl install`, so the injected copies come along for the ride.

### How to confirm the fix worked

Before fix:
```
$ xcrun simctl launch --console-pty <UDID> <bundle_id>
dyld[...]: Library not loaded: @rpath/_Testing_Foundation.framework/_Testing_Foundation
```

After fix (app launches cleanly, process stays alive):
```
$ xcrun simctl launch --console-pty <UDID> <bundle_id>
<bundle_id>: 51593
```

Then the test runs in seconds, not minutes.

### Detecting this issue from an xcresult / test.log

When the run_test.sh parser sees a failure like:

```
"The test runner timed out while preparing to run tests."
```

and the test.log shows the UITest process reached `Wait for <bundle> to idle` but never got past it, check `test.log` for the `PatrolServer: INFO: Server started` line — if that appears but there is no corresponding `PatrolAppServiceClient: connected` line, the app-under-test never made it past dyld, which means Issue 16.

**Loop Phase:** [1] Prepare environment — category **5-A** (missing runtime dependency blocks app launch)

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
| Issue 12 — `Module 'patrol' not found` in RunnerUITests | [1] Prepare | 5-A |
| Issue 13 — CocoaPods fails on `objectVersion '70'` (Xcode 26+) | [1] Prepare | 5-D |
| Issue 14 — `ENABLE_USER_SCRIPT_SANDBOXING = YES` denies script writes | [2] Build | 5-A |
| Issue 15 — "Clone 1/2/3" sims spawned (Xcode parallel testing) | [1] Prepare | 5-D |
| Issue 16 — `_Testing_Foundation.framework` / `lib_TestingInterop.dylib` not loaded (Xcode 26) | [1] Prepare | 5-A |
