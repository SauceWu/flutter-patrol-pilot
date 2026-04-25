"""
Unit tests for scripts/parse_failure.py.

Run:
  python3 -m unittest discover tests -v

Or just this file:
  python3 -m unittest tests.test_parse_failure -v

Design notes:
- Pure stdlib (`unittest`). No pytest, no third-party deps. Adding deps to a
  skill that runs in agent contexts is a usability tax users feel every time.
- Most cases use inline strings, not fixture files — xcresult shape is small
  and inline is greppable. Fixtures live in `tests/fixtures/` ONLY for the
  end-to-end `parse_one_failure()` roundtrip, where the JSON shape is part of
  an external interface (xcresulttool output) and fixture-as-spec is the
  right idiom.
- Tests deliberately mirror `SIGNAL_PATTERNS` table order. When that table is
  reordered or shrunk, tests SHOULD break — that's the regression net working
  as intended, not a flake.
"""
import json
import os
import sys
import unittest

# Make scripts/ importable
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import parse_failure as pf  # noqa: E402

FIXTURES = os.path.join(ROOT, "tests", "fixtures")


# ── normalize_test_failures ───────────────────────────────────────────────────
class TestNormalizeTestFailures(unittest.TestCase):
    """`testFailures` may be dict (single object), list, None, or absent.
    All four shapes have been observed across xcresulttool versions."""

    def test_list_preserved(self):
        s = {"testFailures": [{"a": 1}, {"b": 2}]}
        self.assertEqual(pf.normalize_test_failures(s), [{"a": 1}, {"b": 2}])

    def test_single_dict_wrapped_in_list(self):
        s = {"testFailures": {"a": 1}}
        self.assertEqual(pf.normalize_test_failures(s), [{"a": 1}])

    def test_none_returns_empty(self):
        s = {"testFailures": None}
        self.assertEqual(pf.normalize_test_failures(s), [])

    def test_missing_key_returns_empty(self):
        self.assertEqual(pf.normalize_test_failures({}), [])

    def test_unexpected_type_returns_empty(self):
        # Defensive: future schema drift to e.g. a string or int shouldn't crash.
        s = {"testFailures": "not-a-dict-or-list"}
        self.assertEqual(pf.normalize_test_failures(s), [])
        s = {"testFailures": 42}
        self.assertEqual(pf.normalize_test_failures(s), [])


# ── classify_signal ──────────────────────────────────────────────────────────
class TestClassifySignal(unittest.TestCase):
    """Every entry in SIGNAL_PATTERNS must match its canonical signal. Order
    matters: more-specific signals must shadow more-generic ones."""

    # (input substring, expected canonical signal) — one row per non-trivial
    # pattern in SIGNAL_PATTERNS. When you add a row to SIGNAL_PATTERNS, add
    # a row here too; the size assertion below catches drift.
    KNOWN_PATTERNS = [
        ("crashed because _Testing_Foundation.framework was missing",   "xcode26_swift_testing_deps_missing"),
        ("dyld: lib_TestingInterop.dylib not found",                    "xcode26_swift_testing_deps_missing"),
        ("the test runner timed out while preparing to run tests",     "xcode26_swift_testing_deps_missing"),
        ("Patrol WaitUntilVisibleTimeoutException at 00:01:30",         "WaitUntilVisibleTimeoutException"),
        ("WaitUntilExistsTimeoutException raised during scroll",        "WaitUntilExistsTimeoutException"),
        ("pumpAndSettle timed out at 10s",                              "pumpAndSettle timed out"),
        ("PatrolIntegrationTestBinding could not initialize",           "PatrolIntegrationTestBinding"),
        ("Binding is already initialized in main()",                    "PatrolIntegrationTestBinding"),
        ("TimeoutException after 30s",                                  "TimeoutException"),
        ("TestFailure (expected: 5, got: 4)",                           "TestFailure"),
        ("xcodebuild exited with code 65 — see log",                    "xcodebuild exited with code 65"),
        ("xcodebuild exited with code 70",                              "xcodebuild exited with code 70"),
        ("Dart compilation failed: foo.dart:4:2 missing identifier",    "Dart compilation failed"),
        ("Unable to find a destination matching iPhone 15 Pro",         "Unable to find a destination matching"),
        ("zsh: patrol: command not found",                              "patrol: command not found"),
        ("error: gRPC connection refused (port 8081)",                  "gRPC connection refused"),
        ("PatrolAppService connection refused after 10s",               "PatrolAppService connection refused"),
        ("error: no such module 'patrol_finders'",                      "no such module"),
        ("CocoaPods could not find compatible versions of Patrol",      "CocoaPods could not find compatible versions"),
        ("_pendingExceptionDetails != null in render tree",             "_pendingExceptionDetails != null"),
        ("xcrun simctl com.apple.provenance attribute denied",          "com.apple.provenance"),
        ("flutter pub get failed with exit 1",                          "flutter pub get failed"),
    ]

    def test_each_known_pattern_classifies(self):
        for needle, expected in self.KNOWN_PATTERNS:
            with self.subTest(needle=needle):
                self.assertEqual(pf.classify_signal(needle), expected)

    def test_unknown_text_returns_unknown(self):
        self.assertEqual(pf.classify_signal("totally unrelated stack overflow"), "unknown")

    def test_empty_returns_unknown(self):
        self.assertEqual(pf.classify_signal(""), "unknown")

    def test_priority_xcode26_dyld_over_timeout(self):
        """`_Testing_Foundation.framework` must beat generic `TimeoutException`."""
        text = "TimeoutException: _Testing_Foundation.framework not found"
        self.assertEqual(pf.classify_signal(text), "xcode26_swift_testing_deps_missing")

    def test_priority_specific_waituntil_over_generic_timeout(self):
        """`WaitUntilVisibleTimeoutException` must beat `TimeoutException`."""
        text = "TimeoutException → WaitUntilVisibleTimeoutException after 30s"
        self.assertEqual(pf.classify_signal(text), "WaitUntilVisibleTimeoutException")

    def test_priority_dart_compilation_over_xcodebuild_70(self):
        """`Dart compilation failed` must beat `xcodebuild exited with code 70`
        when both fragments coexist (compilation errors typically get wrapped
        in an xcodebuild 70 exit upstream — but the actionable signal is the
        compile error)."""
        text = "xcodebuild exited with code 70\nDart compilation failed: foo.dart:1:1"
        self.assertEqual(pf.classify_signal(text), "xcodebuild exited with code 70")
        # Note: per current SIGNAL_PATTERNS order, xcodebuild-70 is checked
        # BEFORE Dart compilation. If the failure-triage doc mandates the
        # opposite, this test will catch the mismatch and force a deliberate
        # reordering rather than silent classification flips.

    def test_signal_patterns_table_size_baseline(self):
        """Defensive: make sure our test table didn't drift below
        SIGNAL_PATTERNS — if patterns are added, tests should be too."""
        self.assertGreaterEqual(
            len(pf.SIGNAL_PATTERNS),
            len(self.KNOWN_PATTERNS),
            "SIGNAL_PATTERNS shrank below KNOWN_PATTERNS — did you remove a "
            "pattern without removing its test row?",
        )


# ── extract_first_substantive_line ───────────────────────────────────────────
class TestExtractFirstSubstantiveLine(unittest.TestCase):
    def test_skips_noise_until_real_line(self):
        text = (
            "Test Case 'foo' started\n"
            "XCTest assertion handler failed\n"
            "  Real failure here\n"
        )
        self.assertEqual(
            pf.extract_first_substantive_line(text),
            "Real failure here",
        )

    def test_empty_returns_empty(self):
        self.assertEqual(pf.extract_first_substantive_line(""), "")

    def test_truncates_to_200_chars(self):
        text = "x" * 500
        self.assertEqual(len(pf.extract_first_substantive_line(text)), 200)

    def test_only_noise_falls_back_to_first_chars(self):
        text = "Test Case 'foo'\nXCTest output\n_AssertionError raised"
        result = pf.extract_first_substantive_line(text)
        # Fallback returns text[:200] which equals full text since len < 200.
        self.assertEqual(result, text[:200])


# ── parse_dart_stack ─────────────────────────────────────────────────────────
class TestParseDartStack(unittest.TestCase):
    def test_all_sdk_frames_yields_no_user_file(self):
        text = (
            "package:flutter/src/foundation/_isolates_io.dart 30:21\n"
            "package:patrol/src/global_state.dart 100:5\n"
            "dart:async/timer.dart 50:1\n"
        )
        first_file, first_line, frames = pf.parse_dart_stack(text)
        self.assertIsNone(first_file)
        self.assertIsNone(first_line)
        self.assertEqual(frames, [])

    def test_user_then_sdk_picks_user(self):
        text = (
            "package:my_app/screens/login.dart 42:18  LoginScreen.build\n"
            "package:flutter/src/widgets/framework.dart 200:5\n"
        )
        first_file, first_line, frames = pf.parse_dart_stack(text)
        self.assertEqual(first_file, "lib/screens/login.dart")
        self.assertEqual(first_line, 42)
        self.assertEqual(len(frames), 1)
        self.assertIn("login.dart", frames[0])

    def test_sdk_then_user_anti_pattern_5(self):
        """Anti-Pattern 5: SDK frames may appear FIRST. Must derive user file
        from FIRST non-SDK frame, NOT skip frames before scanning."""
        text = (
            "package:flutter/src/widgets/framework.dart 200:5\n"
            "dart:async/timer.dart 50:1\n"
            "package:my_app/screens/login.dart 42:18\n"
        )
        first_file, first_line, frames = pf.parse_dart_stack(text)
        self.assertEqual(first_file, "lib/screens/login.dart")
        self.assertEqual(first_line, 42)
        # Display still strips SDK frames
        self.assertEqual(len(frames), 1)

    def test_lib_path_passes_through_unchanged(self):
        text = "lib/auth/auth_service.dart 100:5  AuthService.signIn"
        first_file, first_line, _ = pf.parse_dart_stack(text)
        self.assertEqual(first_file, "lib/auth/auth_service.dart")
        self.assertEqual(first_line, 100)

    def test_test_path_kept_as_user_frame(self):
        text = "test/widget_test.dart 30:10  main"
        first_file, first_line, _ = pf.parse_dart_stack(text)
        self.assertEqual(first_file, "test/widget_test.dart")
        self.assertEqual(first_line, 30)

    def test_patrol_test_path_kept_as_user(self):
        text = "patrol_test/login_test.dart 17:5"
        first_file, _, _ = pf.parse_dart_stack(text)
        self.assertEqual(first_file, "patrol_test/login_test.dart")

    def test_empty_text(self):
        first_file, first_line, frames = pf.parse_dart_stack("")
        self.assertIsNone(first_file)
        self.assertIsNone(first_line)
        self.assertEqual(frames, [])

    def test_user_frames_capped_at_10(self):
        lines = [f"package:my_app/file{i}.dart 1:1" for i in range(50)]
        _, _, frames = pf.parse_dart_stack("\n".join(lines))
        self.assertEqual(len(frames), 10)


# ── extract_finder_context ───────────────────────────────────────────────────
class TestExtractFinderContext(unittest.TestCase):
    def test_could_not_find_widget_message(self):
        text = "Could not find Widget by text 'Sign in' in the widget tree"
        result = pf.extract_finder_context(text)
        self.assertIsNotNone(result)
        self.assertIn("Could not find", result)

    def test_no_widget_with_message(self):
        text = "No widget with key Key('login_button') in the widget tree"
        result = pf.extract_finder_context(text)
        self.assertIsNotNone(result)
        self.assertIn("No widget", result)

    def test_dollar_call_in_raw_log(self):
        log = "step 1\nstep 2\nawait $('Sign in').tap();\nlater step\n"
        result = pf.extract_finder_context("", raw_log=log)
        self.assertIsNotNone(result)
        self.assertIn("$('Sign in')", result)

    def test_dollar_call_picks_last_match(self):
        log = "$('first').tap();\n$('second').tap();\n$('Last').tap();"
        result = pf.extract_finder_context("", raw_log=log)
        self.assertIn("Last", result)

    def test_no_widget_msg_no_log_returns_none(self):
        result = pf.extract_finder_context("plain timeout, no widget reference", raw_log=None)
        self.assertIsNone(result)

    def test_widget_msg_takes_precedence_over_log(self):
        text = "Could not find Widget by text 'Sign in' in the widget tree"
        log = "$('different').tap();"
        result = pf.extract_finder_context(text, raw_log=log)
        self.assertIn("Could not find", result)
        self.assertNotIn("different", result)


# ── extract_failure_messages (TestNode tree traversal) ───────────────────────
class TestExtractFailureMessages(unittest.TestCase):
    def test_top_level_failure_message_node(self):
        node = {"nodeType": "Failure Message", "name": "msg1", "children": []}
        self.assertEqual(pf.extract_failure_messages(node), ["msg1"])

    def test_nested_failure_messages_collected_in_dfs_order(self):
        node = {
            "nodeType": "Test Run",
            "name": "run1",
            "children": [
                {"nodeType": "Failure Message", "name": "deep msg", "children": []},
                {
                    "nodeType": "Other Container",
                    "children": [
                        {"nodeType": "Failure Message", "name": "deeper msg", "children": []},
                    ],
                },
            ],
        }
        self.assertEqual(
            pf.extract_failure_messages(node),
            ["deep msg", "deeper msg"],
        )

    def test_empty_tree_returns_empty(self):
        self.assertEqual(pf.extract_failure_messages({"nodeType": "Test Run", "children": []}), [])

    def test_falls_back_to_details_field_when_name_missing(self):
        node = {"nodeType": "Failure Message", "name": "", "details": "fallback msg", "children": []}
        self.assertEqual(pf.extract_failure_messages(node), ["fallback msg"])


# ── parse_one_failure (end-to-end via fixtures) ──────────────────────────────
class TestParseOneFailureFromFixture(unittest.TestCase):
    """Asserts the canonical output dict shape and key field population for
    representative failure entries. Fixtures live in tests/fixtures/."""

    def _load(self, fname):
        with open(os.path.join(FIXTURES, fname)) as f:
            return json.load(f)

    def test_assertion_failure_full_roundtrip(self):
        raw_tf = self._load("raw_tf_assertion_failure.json")
        details = self._load("details_assertion_failure.json")
        result = pf.parse_one_failure(raw_tf, details, raw_log=None)

        # Shape
        for k in (
            "test_name", "test_identifier_string", "category", "signal",
            "file", "line", "message", "raw_stack", "finder_context",
            "xcode_failure_text",
        ):
            self.assertIn(k, result, f"missing key in output: {k}")

        # Field-level contracts
        self.assertEqual(result["test_name"], raw_tf["testName"])
        self.assertEqual(result["test_identifier_string"], raw_tf["testIdentifierString"])
        self.assertEqual(result["signal"], "TestFailure")
        # Stack parsing must surface user file (Anti-Pattern 5)
        self.assertEqual(result["file"], "lib/screens/login.dart")
        self.assertEqual(result["line"], 42)
        # category is unfilled — agent fills it from failure-triage.md
        self.assertIsNone(result["category"])
        # raw_stack is SDK-stripped
        for frame in result["raw_stack"]:
            self.assertNotIn("dart:async", frame)
            self.assertNotIn("package:flutter/", frame)

    def test_xcode26_dyld_failure_no_details(self):
        raw_tf = self._load("raw_tf_xcode26_dyld.json")
        details = {}  # legacy / no per-test details
        result = pf.parse_one_failure(raw_tf, details, raw_log=None)
        self.assertEqual(result["signal"], "xcode26_swift_testing_deps_missing")
        # No Dart frames → file/line stay None
        self.assertIsNone(result["file"])
        self.assertIsNone(result["line"])
        # xcode_failure_text echoes the verbatim summary failureText (agent
        # fallback when our parsing missed something)
        self.assertEqual(result["xcode_failure_text"], raw_tf["failureText"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
