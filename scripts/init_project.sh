#!/usr/bin/env bash
# init_project.sh — one-shot Patrol + iOS setup for a Flutter project.
#
# Run from the Flutter project root (the directory that contains `pubspec.yaml`
# and `ios/Runner.xcodeproj`). For monorepo/example layouts, cd into the
# package dir first (e.g. `cd my_plugin/example && bash init_project.sh`).
#
# Usage:
#   bash init_project.sh [--dry-run] [--skip-pod-install] [--skip-pub-get]
#                        [--patrol-version "^4.5.0"]
#                        [--app-name <name>] [--bundle-id <id>] [--package-name <id>]
#
# What it does (each step is idempotent — safe to re-run):
#   1. Preflight: verify cwd is a Flutter project; check ruby / xcodeproj gem
#   2. Detect & prepend fvm .fvm/flutter_sdk/bin to PATH (walks up 8 levels)
#   3. Append ~/.pub-cache/bin to PATH
#   4. Infer app_name / bundle_id / package_name from existing project files
#   5. Patch pubspec.yaml: add `patrol` dev_dependency + `patrol:` config block
#   6. Patch ios/Podfile: platform 13.0, use_modular_headers!, RunnerUITests target
#   7. Patch ios/Runner.xcodeproj/project.pbxproj:
#        - objectVersion 70 → 60 (Xcode 26 + CocoaPods 1.16.x compat)
#        - ENABLE_USER_SCRIPT_SANDBOXING = YES → NO everywhere
#   8. Create RunnerUITests target via ruby + xcodeproj gem (if missing)
#      (includes: PBXNativeTarget, RunnerUITests.m, Info.plist, TEST_TARGET_NAME,
#       target dependency on Runner, framework/resources phases)
#   9. Write ios/RunnerUITests/RunnerUITests.m (Patrol PATROL_INTEGRATION_TEST_IOS_RUNNER)
#  10. Patch ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme:
#        - parallelizable = "YES" → "NO" (kills Xcode test-clone simulators)
#        - Ensure <TestableReference> to RunnerUITests exists
#  11. Scaffold patrol_test/smoke_test.dart (if missing) with intentional typo
#      so the agent has something to triage on first run
#  12. Update .gitignore: patrol_test/test_bundle.dart, integration_test/test_bundle.dart
#  13. Activate patrol_cli (using fvm dart if detected), flutter pub get, pod install
#
# Exit 0: all steps succeeded (or were already done)
# Exit 1: preflight failed
# Exit 2: a patch step failed
# Exit 3: pub/pod install failed
#
# Stdout: single-line JSON summary of what changed
# Stderr: progress messages per step
set -euo pipefail

# ── args ──────────────────────────────────────────────────────────────────────
DRY_RUN=0
SKIP_POD=0
SKIP_PUB=0
PATROL_VERSION="^4.5.0"
APP_NAME_ARG=""
BUNDLE_ID_ARG=""
PACKAGE_NAME_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)         DRY_RUN=1; shift ;;
    --skip-pod-install) SKIP_POD=1; shift ;;
    --skip-pub-get)    SKIP_PUB=1; shift ;;
    --patrol-version)  PATROL_VERSION="$2"; shift 2 ;;
    --app-name)        APP_NAME_ARG="$2"; shift 2 ;;
    --bundle-id)       BUNDLE_ID_ARG="$2"; shift 2 ;;
    --package-name)    PACKAGE_NAME_ARG="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,50p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "[init] unknown arg: $1" >&2; shift ;;
  esac
done

_say() { echo "[init] $*" >&2; }
_doit() {
  # _doit "<human description>" <shell cmd>
  local desc="$1"; shift
  if [ "$DRY_RUN" = "1" ]; then
    _say "DRY-RUN would: $desc"
    _say "           cmd: $*"
    return 0
  fi
  _say "$desc"
  "$@"
}

# Track what changed for final JSON summary
declare -a CHANGES=()
_changed() { CHANGES+=("$1"); }

# ── Step 1: preflight ─────────────────────────────────────────────────────────
_say "Step 1/13: preflight"

if [ ! -f pubspec.yaml ]; then
  echo "[init] ERROR: no pubspec.yaml in $(pwd) — run from Flutter project root" >&2
  exit 1
fi

if [ ! -d ios/Runner.xcodeproj ]; then
  echo "[init] ERROR: no ios/Runner.xcodeproj in $(pwd) — not a Flutter iOS project" >&2
  exit 1
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "[init] ERROR: ruby not found (macOS ships with one — PATH issue?)" >&2
  exit 1
fi

if ! ruby -e "require 'xcodeproj'" 2>/dev/null; then
  echo "[init] ERROR: ruby gem 'xcodeproj' not installed" >&2
  echo "[init]        install with: sudo gem install xcodeproj" >&2
  echo "[init]        (or: gem install --user-install xcodeproj, then add ~/.gem/ruby/<ver>/bin to PATH)" >&2
  exit 1
fi

for tool in xcrun xcodebuild python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[init] ERROR: required tool not found: $tool" >&2
    exit 1
  fi
done

# ── Step 2: fvm auto-detection ────────────────────────────────────────────────
_say "Step 2/13: fvm detection"
_fvm_dir="$PWD"
FVM_FOUND=""
for _i in 1 2 3 4 5 6 7 8; do
  if [ -d "$_fvm_dir/.fvm/flutter_sdk/bin" ]; then
    export PATH="$_fvm_dir/.fvm/flutter_sdk/bin:$PATH"
    FVM_FOUND="$_fvm_dir/.fvm/flutter_sdk"
    _say "  using $FVM_FOUND"
    break
  fi
  _parent="$(dirname "$_fvm_dir")"
  [ "$_parent" = "$_fvm_dir" ] && break
  _fvm_dir="$_parent"
done
[ -z "$FVM_FOUND" ] && _say "  no .fvm/ found — using system flutter/dart"

# ── Step 3: pub-cache/bin on PATH ────────────────────────────────────────────
_say "Step 3/13: pub-cache/bin on PATH"
if [ -d "$HOME/.pub-cache/bin" ] && [[ ":$PATH:" != *":$HOME/.pub-cache/bin:"* ]]; then
  export PATH="$PATH:$HOME/.pub-cache/bin"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "[init] ERROR: flutter not in PATH (even after fvm detection)" >&2
  exit 1
fi
_say "  flutter: $(which flutter)"
_say "  dart:    $(which dart)"

# ── Step 4: infer app metadata ────────────────────────────────────────────────
_say "Step 4/13: infer app metadata"

APP_NAME=""
if [ -n "$APP_NAME_ARG" ]; then
  APP_NAME="$APP_NAME_ARG"
else
  APP_NAME=$(grep -E '^name: ' pubspec.yaml 2>/dev/null | head -1 | sed 's/name: *//' | tr -d '"' | tr -d "'" || echo "")
fi

BUNDLE_ID=""
if [ -n "$BUNDLE_ID_ARG" ]; then
  BUNDLE_ID="$BUNDLE_ID_ARG"
else
  # Try project.pbxproj for the Runner target's bundle id
  BUNDLE_ID=$(grep -E 'PRODUCT_BUNDLE_IDENTIFIER = ' ios/Runner.xcodeproj/project.pbxproj 2>/dev/null \
    | grep -v "Tests\|xctest\|xctrunner" \
    | head -1 | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);.*/\1/' | tr -d '"' || echo "")
fi

PACKAGE_NAME=""
if [ -n "$PACKAGE_NAME_ARG" ]; then
  PACKAGE_NAME="$PACKAGE_NAME_ARG"
elif [ -f android/app/build.gradle ]; then
  PACKAGE_NAME=$(grep -E 'applicationId ' android/app/build.gradle 2>/dev/null \
    | head -1 | sed -E 's/.*applicationId *["'\'']([^"'\'' ]+)["'\''].*/\1/' || echo "")
elif [ -f android/app/build.gradle.kts ]; then
  PACKAGE_NAME=$(grep -E 'applicationId[[:space:]]*=' android/app/build.gradle.kts 2>/dev/null \
    | head -1 | sed -E 's/.*applicationId *= *"([^"]+)".*/\1/' || echo "")
fi

[ -z "$APP_NAME" ]    && APP_NAME="app"
[ -z "$BUNDLE_ID" ]   && BUNDLE_ID="com.example.app"
[ -z "$PACKAGE_NAME" ] && PACKAGE_NAME="$BUNDLE_ID"

_say "  app_name:     $APP_NAME"
_say "  bundle_id:    $BUNDLE_ID"
_say "  package_name: $PACKAGE_NAME"

# ── Step 5: patch pubspec.yaml ────────────────────────────────────────────────
_say "Step 5/13: pubspec.yaml"

PUBSPEC_CHANGED=0
if ! grep -qE '^[[:space:]]+patrol:' pubspec.yaml; then
  if [ "$DRY_RUN" = "1" ]; then
    _say "  DRY-RUN would add 'patrol: $PATROL_VERSION' under dev_dependencies"
  else
    # Insert under dev_dependencies: — find that line and inject after the
    # `sdk: flutter` line that typically follows.
    python3 - <<PY
import re, sys
p = 'pubspec.yaml'
with open(p, 'r') as f:
    content = f.read()

# Add 'patrol: <ver>' into dev_dependencies block
if re.search(r'^dev_dependencies:', content, re.MULTILINE):
    # Find the dev_dependencies block and insert a patrol entry at its end,
    # keeping two-space indentation.
    def _add_patrol(m):
        block = m.group(0)
        if re.search(r'^\s+patrol:\s', block, re.MULTILINE):
            return block
        return block.rstrip() + '\n  patrol: $PATROL_VERSION\n'

    content2 = re.sub(
        r'(^dev_dependencies:\n(?:[ \t].*\n)*)',
        _add_patrol, content, count=1, flags=re.MULTILINE)
    if content2 != content:
        content = content2
        print('added patrol dep')
    else:
        print('patrol already present under dev_dependencies')
else:
    content += '\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n  patrol: $PATROL_VERSION\n'
    print('added new dev_dependencies block')

with open(p, 'w') as f:
    f.write(content)
PY
    PUBSPEC_CHANGED=1
  fi
else
  _say "  patrol dev_dependency already present"
fi

if ! grep -qE '^patrol:' pubspec.yaml; then
  if [ "$DRY_RUN" = "1" ]; then
    _say "  DRY-RUN would append 'patrol:' config block (app_name/bundle_id/package_name)"
  else
    cat >> pubspec.yaml <<YAML

patrol:
  app_name: "$APP_NAME"
  bundle_id: $BUNDLE_ID
  package_name: $PACKAGE_NAME
YAML
    PUBSPEC_CHANGED=1
  fi
else
  _say "  patrol: config block already present"
fi

[ "$PUBSPEC_CHANGED" = "1" ] && _changed "pubspec.yaml"

# ── Step 6: ios/Podfile ───────────────────────────────────────────────────────
_say "Step 6/13: ios/Podfile"

PODFILE=ios/Podfile
PODFILE_CHANGED=0

if [ ! -f "$PODFILE" ]; then
  _say "  WARNING: $PODFILE missing — run `flutter create .` first? Skipping"
else
  # 6a. uncomment `platform :ios, '13.0'` (Patrol requires >= 13.0)
  if grep -qE '^# platform :ios' "$PODFILE"; then
    if [ "$DRY_RUN" = "1" ]; then
      _say "  DRY-RUN would uncomment platform :ios, '13.0'"
    else
      python3 - <<'PY'
import re
p = 'ios/Podfile'
s = open(p).read()
s2 = re.sub(r"^# platform :ios, '[0-9.]+'", "platform :ios, '13.0'", s, count=1, flags=re.MULTILINE)
if s2 != s:
    open(p, 'w').write(s2)
    print('uncommented platform')
PY
      PODFILE_CHANGED=1
    fi
  elif ! grep -qE "^platform :ios" "$PODFILE"; then
    if [ "$DRY_RUN" != "1" ]; then
      python3 - <<'PY'
p = 'ios/Podfile'
s = open(p).read()
if not s.startswith("platform"):
    open(p, 'w').write("platform :ios, '13.0'\n" + s)
    print('prepended platform directive')
PY
      PODFILE_CHANGED=1
    fi
  fi

  # 6b. Ensure `use_modular_headers!` is set somewhere (patrol needs modular @import).
  # Accept both top-level and target-nested forms; just verify the directive exists.
  if ! grep -qE '^\s*use_modular_headers!' "$PODFILE"; then
    if [ "$DRY_RUN" = "1" ]; then
      _say "  DRY-RUN would add 'use_modular_headers!' above the first target line"
    else
      python3 - <<'PY'
import re
p = 'ios/Podfile'
s = open(p).read()
# Insert right before the first `target '...' do` block if not already present.
if 'use_modular_headers!' not in s:
    s2 = re.sub(r"(^target ['\"].*?['\"] do)",
                r"use_modular_headers!\n\n\1",
                s, count=1, flags=re.MULTILINE)
    if s2 != s:
        open(p, 'w').write(s2)
        print('added use_modular_headers!')
PY
      PODFILE_CHANGED=1
    fi
  fi

  # 6c. Ensure a RunnerUITests target block exists that inherits from Runner
  if ! grep -qE "target ['\"]RunnerUITests['\"]" "$PODFILE"; then
    if [ "$DRY_RUN" = "1" ]; then
      _say "  DRY-RUN would append target 'RunnerUITests' block"
    else
      python3 - <<'PY'
import re
p = 'ios/Podfile'
s = open(p).read()
block = """\

target 'RunnerUITests' do
  inherit! :complete
end
"""
# Insert before the trailing `post_install do |installer|` line if present,
# otherwise append.
if "target 'RunnerUITests'" not in s:
    if re.search(r"^post_install do", s, re.MULTILINE):
        s2 = re.sub(r"(\n^post_install do)",
                    block + r"\1",
                    s, count=1, flags=re.MULTILINE)
    else:
        s2 = s.rstrip() + "\n" + block
    if s2 != s:
        open(p, 'w').write(s2)
        print('added RunnerUITests target block')
PY
      PODFILE_CHANGED=1
    fi
  fi
fi

[ "$PODFILE_CHANGED" = "1" ] && _changed "ios/Podfile"

# ── Step 7: patch project.pbxproj (Xcode 26 compat) ───────────────────────────
_say "Step 7/13: project.pbxproj (Xcode 26 compat)"

PBXPROJ=ios/Runner.xcodeproj/project.pbxproj
PBXPROJ_CHANGED=0

# 7a. objectVersion 70 → 60 (CocoaPods xcodeproj gem can't parse 70)
if grep -qE 'objectVersion = 70;' "$PBXPROJ" 2>/dev/null; then
  if [ "$DRY_RUN" = "1" ]; then
    _say "  DRY-RUN would downgrade objectVersion 70 → 60"
  else
    sed -i '' 's/objectVersion = 70;/objectVersion = 60;/g' "$PBXPROJ"
    _say "  objectVersion 70 → 60"
    PBXPROJ_CHANGED=1
  fi
fi

# 7b. ENABLE_USER_SCRIPT_SANDBOXING = YES → NO
# Xcode 26 adds this to new targets; Flutter's scripts need to write to build/.
if grep -qE 'ENABLE_USER_SCRIPT_SANDBOXING = YES' "$PBXPROJ" 2>/dev/null; then
  if [ "$DRY_RUN" = "1" ]; then
    _say "  DRY-RUN would flip ENABLE_USER_SCRIPT_SANDBOXING YES → NO"
  else
    sed -i '' 's/ENABLE_USER_SCRIPT_SANDBOXING = YES/ENABLE_USER_SCRIPT_SANDBOXING = NO/g' "$PBXPROJ"
    _say "  sandboxing YES → NO"
    PBXPROJ_CHANGED=1
  fi
fi

[ "$PBXPROJ_CHANGED" = "1" ] && _changed "ios/Runner.xcodeproj/project.pbxproj (xcode26 fixes)"

# ── Step 8: create RunnerUITests target via xcodeproj gem (if missing) ────────
_say "Step 8/13: RunnerUITests target"

# Use ruby to inspect the project for a RunnerUITests target.
HAS_TARGET=$(ruby -r xcodeproj -e "
p = Xcodeproj::Project.open('ios/Runner.xcodeproj')
puts p.targets.any? { |t| t.name == 'RunnerUITests' } ? 'yes' : 'no'
" 2>/dev/null || echo "no")

if [ "$HAS_TARGET" = "yes" ]; then
  _say "  RunnerUITests target already exists — skipping creation"
else
  if [ "$DRY_RUN" = "1" ]; then
    _say "  DRY-RUN would create RunnerUITests UI test target via xcodeproj gem"
  else
    _say "  creating RunnerUITests UI test target..."
    mkdir -p ios/RunnerUITests

    # Write a minimal Info.plist for the UITest bundle
    cat > ios/RunnerUITests/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>$(DEVELOPMENT_LANGUAGE)</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key>
  <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
PLIST

    # Spawn ruby to mutate the xcodeproj
    PATROL_BUNDLE_ID="${BUNDLE_ID}.RunnerUITests" \
    RUNNER_BUNDLE_ID="$BUNDLE_ID" \
    ruby -r xcodeproj <<'RUBY'
project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

runner = project.targets.find { |t| t.name == 'Runner' }
raise "Runner target not found in #{project_path}" unless runner

# Create the UI test target
test_target = project.new_target(
  :ui_test_bundle, 'RunnerUITests', :ios, '13.0',
  project.products_group
)

# Build settings (Patrol + Xcode 26 hygiene)
test_target.build_configurations.each do |config|
  bs = config.build_settings
  bs['IPHONEOS_DEPLOYMENT_TARGET']     = '13.0'
  bs['PRODUCT_BUNDLE_IDENTIFIER']      = ENV['PATROL_BUNDLE_ID']
  bs['PRODUCT_NAME']                   = '$(TARGET_NAME)'
  bs['TEST_TARGET_NAME']               = 'Runner'
  bs['CODE_SIGN_STYLE']                = 'Automatic'
  bs['ENABLE_USER_SCRIPT_SANDBOXING']  = 'NO'
  bs['GENERATE_INFOPLIST_FILE']        = 'NO'
  bs['INFOPLIST_FILE']                 = 'RunnerUITests/Info.plist'
  bs['LD_RUNPATH_SEARCH_PATHS']        = ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks']
  bs['SWIFT_EMIT_LOC_STRINGS']         = 'NO'
end

# Create the RunnerUITests group + add RunnerUITests.m as a source file
group = project.main_group.find_subpath('RunnerUITests', true)
group.set_source_tree('<group>')
group.set_path('RunnerUITests')
m_ref = group.new_reference('RunnerUITests.m')
test_target.source_build_phase.add_file_reference(m_ref)

# Ensure Info.plist file reference is tracked (not added to a build phase)
plist_ref = group.files.find { |f| f.path == 'Info.plist' } \
  || group.new_reference('Info.plist')
# no build phase membership for Info.plist — Xcode reads it via INFOPLIST_FILE

# Depend on Runner so the app-under-test is built/installed before the UI test
test_target.add_dependency(runner)

project.save
puts "created RunnerUITests target"
RUBY

    _changed "created RunnerUITests xcodeproj target"
  fi
fi

# ── Step 9: write ios/RunnerUITests/RunnerUITests.m (always overwrite) ────────
_say "Step 9/13: RunnerUITests.m (Patrol bootstrap macro)"

if [ "$DRY_RUN" = "1" ]; then
  _say "  DRY-RUN would write ios/RunnerUITests/RunnerUITests.m"
else
  mkdir -p ios/RunnerUITests
  cat > ios/RunnerUITests/RunnerUITests.m <<'OBJC'
// Generated by flutter-patrol-pilot/init_project.sh
// DO NOT edit by hand. Safe to regenerate.
//
// This macro expands into the XCUITest entry point that drives the
// Patrol-instrumented Flutter app. PATROL_ENABLED / FULL_ISOLATION /
// CLEAR_PERMISSIONS Swift flags are injected by `patrol build` — Xcode GUI
// `Cmd+B` will not succeed here, and that is expected.

@import XCTest;
@import patrol;
@import ObjectiveC.runtime;

PATROL_INTEGRATION_TEST_IOS_RUNNER(RunnerUITests)
OBJC
  _changed "ios/RunnerUITests/RunnerUITests.m"
fi

# ── Step 10: patch Runner.xcscheme ────────────────────────────────────────────
_say "Step 10/13: Runner.xcscheme"

SCHEME=ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme
SCHEME_CHANGED=0

if [ ! -f "$SCHEME" ]; then
  _say "  WARNING: $SCHEME not found"
else
  # 10a. parallelizable = YES → NO (prevents Xcode from cloning the sim)
  if grep -q 'parallelizable = "YES"' "$SCHEME"; then
    if [ "$DRY_RUN" = "1" ]; then
      _say "  DRY-RUN would flip parallelizable YES → NO in TestableReferences"
    else
      sed -i '' 's/parallelizable = "YES"/parallelizable = "NO"/g' "$SCHEME"
      _say "  parallelizable YES → NO (no more test-clone sims)"
      SCHEME_CHANGED=1
    fi
  fi

  # 10b. Ensure a TestableReference for RunnerUITests exists in <Testables>
  if ! grep -q 'BlueprintName = "RunnerUITests"' "$SCHEME"; then
    if [ "$DRY_RUN" = "1" ]; then
      _say "  DRY-RUN would add TestableReference(RunnerUITests) to <Testables>"
    else
      ruby -r xcodeproj <<'RUBY'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
test_target = project.targets.find { |t| t.name == 'RunnerUITests' }
abort '[init] ERROR: RunnerUITests target missing at scheme patch' unless test_target

scheme_path = 'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme'
scheme = Xcodeproj::XCScheme.new(scheme_path)

# Skip if already in scheme
already = scheme.test_action.testables.any? { |t|
  t.buildable_references.any? { |b| b.target_name == 'RunnerUITests' }
}
unless already
  ref = Xcodeproj::XCScheme::TestAction::TestableReference.new(test_target)
  # Patrol UI tests must not parallelize (no sim cloning).
  ref.parallelizable = false
  scheme.test_action.add_testable(ref)
  scheme.save!
  puts "added RunnerUITests to Runner.xcscheme Testables"
end
RUBY
      SCHEME_CHANGED=1
    fi
  fi
fi

[ "$SCHEME_CHANGED" = "1" ] && _changed "ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme"

# ── Step 11: patrol_test scaffold ─────────────────────────────────────────────
_say "Step 11/13: patrol_test/ scaffold"

if [ ! -f patrol_test/smoke_test.dart ]; then
  if [ "$DRY_RUN" = "1" ]; then
    _say "  DRY-RUN would create patrol_test/smoke_test.dart"
  else
    mkdir -p patrol_test
    cat > patrol_test/smoke_test.dart <<'DART'
// Smoke test for verifying the flutter-patrol-pilot skill is wired up.
//
// Intentionally contains a typo ('Fluter') that the agent should catch on the
// first iteration. Once the typo is fixed (to 'Flutter'), the test passes and
// you can use this file as the baseline for your real tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('smoke: minimal app renders hello text', ($) async {
    await $.pumpWidgetAndSettle(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Hello Flutter')),
        ),
      ),
    );

    // INTENTIONAL TYPO — the widget tree contains 'Hello Flutter' but the
    // finder looks for 'Hello Fluter'. Classify as 5-D (test_design) and fix.
    expect($('Hello Fluter'), findsOneWidget);
  });
}
DART
    _changed "patrol_test/smoke_test.dart"
  fi
else
  _say "  patrol_test/smoke_test.dart already exists — keeping"
fi

# ── Step 12: .gitignore ───────────────────────────────────────────────────────
_say "Step 12/13: .gitignore"

GI=.gitignore
GI_CHANGED=0
touch "$GI"
for pat in "patrol_test/test_bundle.dart" "integration_test/test_bundle.dart" ".test-results/"; do
  if ! grep -qxF "$pat" "$GI"; then
    if [ "$DRY_RUN" = "1" ]; then
      _say "  DRY-RUN would add '$pat' to .gitignore"
    else
      printf '%s\n' "$pat" >> "$GI"
      _say "  + $pat"
      GI_CHANGED=1
    fi
  fi
done
[ "$GI_CHANGED" = "1" ] && _changed ".gitignore"

# ── Step 13: activate patrol_cli + pub get + pod install ──────────────────────
_say "Step 13/13: tooling install"

if [ "$DRY_RUN" = "1" ]; then
  _say "  DRY-RUN skipping tool install"
else
  _say "  activating patrol_cli..."
  if [ -n "$FVM_FOUND" ]; then
    (fvm dart pub global deactivate patrol_cli >/dev/null 2>&1 || true)
    fvm dart pub global activate patrol_cli >&2 || true
  else
    (dart pub global deactivate patrol_cli >/dev/null 2>&1 || true)
    dart pub global activate patrol_cli >&2 || true
  fi

  if [ "$SKIP_PUB" = "0" ]; then
    _say "  flutter pub get..."
    if [ -n "$FVM_FOUND" ]; then
      fvm flutter pub get >&2 || { echo "[init] ERROR: flutter pub get failed" >&2; exit 3; }
    else
      flutter pub get >&2 || { echo "[init] ERROR: flutter pub get failed" >&2; exit 3; }
    fi
  fi

  if [ "$SKIP_POD" = "0" ]; then
    _say "  pod install..."
    ( cd ios && pod install >&2 ) || { echo "[init] ERROR: pod install failed" >&2; exit 3; }
  fi
fi

# ── summary JSON ──────────────────────────────────────────────────────────────
SUMMARY=$(python3 -c "
import sys, json
changes = sys.argv[1:]
print(json.dumps({
  'success': True,
  'dry_run': bool(int('$DRY_RUN')),
  'fvm_sdk': '${FVM_FOUND}' or None,
  'app_name': '$APP_NAME',
  'bundle_id': '$BUNDLE_ID',
  'package_name': '$PACKAGE_NAME',
  'patrol_version': '$PATROL_VERSION',
  'changes': changes,
  'next_steps': [
    'Boot a simulator: xcrun simctl boot <UDID>',
    'Build + install:  bash <skill>/scripts/build.sh --sim <UDID> --target patrol_test/smoke_test.dart',
    'Run tests:        bash <skill>/scripts/run_test.sh --sim <UDID> --target patrol_test/smoke_test.dart',
    'The scaffolded smoke test has an intentional typo — agent must triage + fix it on first run.'
  ]
}))
" ${CHANGES[@]+"${CHANGES[@]}"})

echo "$SUMMARY"
echo "[init] done." >&2
