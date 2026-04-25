#!/usr/bin/env python3
"""
parse_failure.py — xcresult failure extractor for flutter-ios-agent-test.

Usage:
  python3 parse_failure.py <xcresult_path> [--log <patrol_log>] [--out <json_file>]

Stdout: single JSON object { source, xcresult_path, xcresult_version, failures[] }
Exit 0: success (empty failures[] is valid — means no failures found)
Exit 1: xcresult path not found or xcresulttool unavailable
Exit 2: JSON parse error from xcresulttool output
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time


# ── constants ─────────────────────────────────────────────────────────────────

# Dart VM stack frame: "package:myapp/foo.dart 42:18  MethodName"
# or "lib/src/foo.dart 42:18  MethodName"
DART_FRAME_RE = re.compile(
    r'(package:[^\s]+\.dart|(?:lib|test|patrol_test|integration_test)/[^\s]+\.dart)'
    r'\s+(\d+)(?::\d+)?'
    r'(?:\s+(.+))?'
)

# SDK package prefixes — used to strip frames from raw_stack display.
# CRITICAL: Do NOT strip before deriving file/line from first non-SDK frame.
SDK_PREFIXES = (
    "package:flutter/",
    "package:flutter_test/",
    "package:patrol/",
    "package:patrol_finders/",
    "package:test/",
    "package:test_api/",
    "package:stack_trace/",
    "dart:",
    "package:async/",
)

# Noise lines to skip when extracting the signal (first substantive error line)
NOISE_PATTERNS = (
    "XCTest",
    "Expected failure",
    "Test Case",
    "dart:async",
    "package:flutter_test",
    "package:patrol",
    "package:test",
    "_AssertionError",
)

# Widget-not-found message from xcresult failure text
FINDER_WIDGET_RE = re.compile(
    r'(No widget (?:with|found).*?(?:in the widget tree|$)|'
    r'Finder.*?found \d+ widgets?.*?$|'
    r'Could not find.*?Widget.*?$)',
    re.MULTILINE
)

# Last $() / await $ call from raw patrol log
FINDER_CALL_RE = re.compile(
    r'(await\s+\$\([^)]+\)|\$\([^)]+\))',
)

# Signal patterns aligned to failure-triage.md Section 2 Quick-Reference Signal Table.
# Order matters: check most-specific signals first to avoid false matches.
SIGNAL_PATTERNS = [
    ("_Testing_Foundation.framework",       "xcode26_swift_testing_deps_missing"),
    ("lib_TestingInterop.dylib",            "xcode26_swift_testing_deps_missing"),
    ("test runner timed out while preparing", "xcode26_swift_testing_deps_missing"),
    ("WaitUntilVisibleTimeoutException",    "WaitUntilVisibleTimeoutException"),
    ("WaitUntilExistsTimeoutException",     "WaitUntilExistsTimeoutException"),
    ("pumpAndSettle timed out",             "pumpAndSettle timed out"),
    ("PatrolIntegrationTestBinding",        "PatrolIntegrationTestBinding"),
    ("Binding is already initialized",      "PatrolIntegrationTestBinding"),
    ("TimeoutException",                    "TimeoutException"),
    ("TestFailure",                         "TestFailure"),
    ("xcodebuild exited with code 65",      "xcodebuild exited with code 65"),
    ("xcodebuild exited with code 70",      "xcodebuild exited with code 70"),
    ("Dart compilation failed",             "Dart compilation failed"),
    ("Unable to find a destination",        "Unable to find a destination matching"),
    ("patrol: command not found",           "patrol: command not found"),
    ("gRPC connection refused",             "gRPC connection refused"),
    ("PatrolAppService connection",         "PatrolAppService connection refused"),
    ("no such module",                      "no such module"),
    ("CocoaPods could not find",            "CocoaPods could not find compatible versions"),
    ("_pendingExceptionDetails",            "_pendingExceptionDetails != null"),
    ("com.apple.provenance",                "com.apple.provenance"),
    ("flutter pub get",                     "flutter pub get failed"),
]


# ── xcresulttool helpers ──────────────────────────────────────────────────────

def get_xcresulttool_version() -> int:
    """
    Returns xcresulttool integer version, e.g. 24757.
    Gate: >= 23000 → new API (Xcode 16+ / Xcode 26.x).
    Returns 0 on any error.
    """
    try:
        r = subprocess.run(
            ["xcrun", "xcresulttool", "--version"],
            capture_output=True, text=True, timeout=10
        )
        # Output: "xcresulttool version 24757, schema version: 0.1.0"
        m = re.search(r'version\s+(\d+)', r.stdout)
        return int(m.group(1)) if m else 0
    except Exception:
        return 0


def run_xcresulttool(args: list, timeout: int = 60) -> dict:
    """Run xcresulttool subcommand and return parsed JSON dict. Raises on error."""
    r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(
            f"xcresulttool failed (exit {r.returncode}): {r.stderr[:500]}"
        )
    return json.loads(r.stdout)


def get_summary(xcresult_path: str, ver: int) -> dict:
    """
    Fetch xcresult summary. Uses new API (>= 23000) or legacy form.
    IMPORTANT: new API does NOT accept --format json flag.
    """
    if ver >= 23000:
        # Xcode 16+ / Xcode 26.x — new get test-results API
        cmd = [
            "xcrun", "xcresulttool", "get", "test-results", "summary",
            "--path", xcresult_path, "--compact"
        ]
    else:
        # Xcode 15 and earlier — legacy form
        cmd = [
            "xcrun", "xcresulttool", "get",
            "--format", "json", "--path", xcresult_path
        ]
    return run_xcresulttool(cmd)


def get_test_details(xcresult_path: str, test_id: str, ver: int) -> dict:
    """
    Fetch per-test detail node (TestDetails). Returns {} on failure (non-fatal).
    Legacy API does not support per-test details directly.
    """
    if ver < 23000:
        return {}
    try:
        cmd = [
            "xcrun", "xcresulttool", "get", "test-results", "test-details",
            "--path", xcresult_path, "--test-id", test_id, "--compact"
        ]
        return run_xcresulttool(cmd, timeout=60)
    except Exception:
        return {}


# ── testFailures normalization ────────────────────────────────────────────────

def normalize_test_failures(summary: dict) -> list:
    """
    testFailures may be a dict (single object, current schema) or list.
    CRITICAL: Always normalize with isinstance() to handle both forms.
    Returns empty list if field is absent or None.
    """
    failures = summary.get("testFailures", None)
    if failures is None:
        return []
    elif isinstance(failures, list):
        return failures
    elif isinstance(failures, dict):
        return [failures]
    else:
        return []


# ── TestNode tree traversal ───────────────────────────────────────────────────

def extract_failure_messages(node: dict, depth: int = 0) -> list:
    """
    Recursively collect text from 'Failure Message' nodeType nodes.
    Each such node's 'name' (and optionally 'details') field contains the failure text.
    """
    messages = []
    if node.get("nodeType") == "Failure Message":
        text = node.get("name", "") or node.get("details", "")
        if text:
            messages.append(text)
    for child in node.get("children", []):
        messages.extend(extract_failure_messages(child, depth + 1))
    return messages


def collect_details_failure_text(details: dict) -> str:
    """Extract all Failure Message text from a TestDetails response."""
    all_msgs = []
    for test_run in details.get("testRuns", []):
        all_msgs.extend(extract_failure_messages(test_run))
    return "\n".join(all_msgs)


# ── signal classification ─────────────────────────────────────────────────────

def classify_signal(failure_text: str) -> str:
    """
    Return a canonical signal string aligned to failure-triage.md Section 2.
    Checks SIGNAL_PATTERNS in priority order; returns "unknown" if no match.
    """
    for needle, canonical in SIGNAL_PATTERNS:
        if needle in failure_text:
            return canonical
    return "unknown"


def extract_first_substantive_line(failure_text: str) -> str:
    """
    Return the first non-empty, non-noise line from failure_text (max 200 chars).
    Used as human-readable summary when signal is "unknown".
    """
    for line in failure_text.splitlines():
        line = line.strip()
        if not line:
            continue
        if any(noise in line for noise in NOISE_PATTERNS):
            continue
        return line[:200]
    return failure_text[:200]


# ── Dart stack parsing ────────────────────────────────────────────────────────

def parse_dart_stack(text: str) -> tuple:
    """
    Returns (first_user_file, first_user_line, user_frames[:10]).

    CRITICAL (Anti-Pattern 5): Derive first_user_file/line from the FIRST non-SDK frame.
    Do NOT skip SDK frames before searching for the first user-code frame.
    Then strip SDK frames from raw_stack for display.

    Steps:
    1. Iterate all Dart frames in order (SDK + user mixed).
    2. First non-SDK frame encountered → record as file/line reference.
    3. Collect only non-SDK frames into user_frames (SDK stripped for display).
    """
    all_frames = []  # (pkg_path, lineno, method_str) — ALL frames in order

    for line in text.splitlines():
        m = DART_FRAME_RE.search(line)
        if not m:
            continue
        pkg_path = m.group(1)
        lineno = int(m.group(2))
        method = (m.group(3) or "").strip()
        all_frames.append((pkg_path, lineno, method))

    first_user_file = None
    first_user_line = None
    user_frames = []

    for pkg_path, lineno, method in all_frames:
        is_sdk = any(pkg_path.startswith(p) for p in SDK_PREFIXES)

        # First non-SDK frame → derive file + line reference (BEFORE stripping)
        if not is_sdk and first_user_file is None:
            if pkg_path.startswith("package:"):
                # "package:myapp/auth/auth_service.dart" → "lib/auth/auth_service.dart"
                parts = pkg_path.split("/", 1)
                first_user_file = "lib/" + parts[1] if len(parts) > 1 else pkg_path
            else:
                first_user_file = pkg_path
            first_user_line = lineno

        # raw_stack: include only non-SDK frames (SDK stripped for display)
        if not is_sdk:
            frame_str = f"{pkg_path} {lineno}"
            if method:
                frame_str += f"  {method}"
            user_frames.append(frame_str)

    return first_user_file, first_user_line, user_frames[:10]


# ── finder context ────────────────────────────────────────────────────────────

def extract_finder_context(failure_text: str, raw_log=None):
    """
    Return the widget-not-found message or last $() call before failure.
    Checks xcresult failure text first; falls back to raw patrol log.
    Returns None if no finder context found.
    """
    # Try xcresult failure text for widget-not-found message
    m = FINDER_WIDGET_RE.search(failure_text)
    if m:
        return m.group(0).strip()[:300]

    # Try raw patrol log: last $() or await $ call
    if raw_log:
        matches = list(FINDER_CALL_RE.finditer(raw_log))
        if matches:
            return matches[-1].group(0).strip()[:300]

    return None


# ── per-failure parser ────────────────────────────────────────────────────────

def parse_one_failure(raw_tf: dict, details: dict, raw_log) -> dict:
    """
    Parse one TestFailure entry from xcresulttool summary + its TestDetails node.

    raw_tf fields (from summary testFailures entry):
      testName, targetName, failureText, testIdentifier, testIdentifierString

    details: TestDetails response (may be empty dict on legacy/error — non-fatal)
    """
    test_name = raw_tf.get("testName", "")
    test_id_str = raw_tf.get("testIdentifierString", "")

    # Primary failure text: prefer TestDetails tree (richer content), fall back to summary
    summary_failure_text = raw_tf.get("failureText", "")
    detail_text = collect_details_failure_text(details) if details else ""
    failure_text = detail_text if detail_text else summary_failure_text

    # Signal classification (aligned to failure-triage.md Section 2)
    signal = classify_signal(failure_text)

    # For "unknown" signals, use first substantive line as signal display
    if signal == "unknown":
        signal_display = extract_first_substantive_line(failure_text) or "unknown"
    else:
        signal_display = signal

    # Dart stack parsing: file, line, raw_stack (SDK frames stripped from display)
    first_file, first_line, raw_stack = parse_dart_stack(failure_text)

    # Finder context: widget-not-found message or last $() call
    finder_ctx = extract_finder_context(failure_text, raw_log)

    # Message: full contiguous block before the stack trace starts
    message_lines = []
    in_stack = False
    for line in failure_text.splitlines():
        if DART_FRAME_RE.search(line):
            in_stack = True
        if not in_stack:
            message_lines.append(line)
    message = "\n".join(message_lines).strip() or failure_text[:500]

    return {
        "test_name": test_name,
        "test_identifier_string": test_id_str,
        "category": None,           # agent fills from failure-triage.md signal table
        "signal": signal_display,
        "file": first_file,
        "line": first_line,
        "message": message,
        "raw_stack": raw_stack,
        "finder_context": finder_ctx,
        "xcode_failure_text": summary_failure_text,  # raw verbatim for agent fallback
    }


# ── error output helper ───────────────────────────────────────────────────────

def emit_error(xcresult_path: str, ver: int, msg: str) -> None:
    """Print structured error JSON to stdout. Called before sys.exit on fatal errors."""
    out = {
        "source": "xcresult",
        "xcresult_path": os.path.abspath(xcresult_path),
        "xcresult_version": ver,
        "failures": None,
        "error": msg,
    }
    print(json.dumps(out, indent=2))


# ── main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Parse xcresult bundle into structured failure signal JSON"
    )
    parser.add_argument(
        "xcresult_path",
        help="Path to .xcresult bundle"
    )
    parser.add_argument(
        "--log",
        default=None,
        help="Optional path to raw patrol/xcodebuild log (supplements finder_context)"
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Optional output file path (JSON written here in addition to stdout)"
    )
    args = parser.parse_args()

    xcresult_path = args.xcresult_path

    # 1. Validate xcresult path exists
    if not os.path.exists(xcresult_path):
        emit_error(xcresult_path, 0, f"xcresult path not found: {xcresult_path}")
        sys.exit(1)

    # 2. Detect xcresulttool version (gate: >= 23000 → new API)
    ver = get_xcresulttool_version()
    print(f"[parse_failure] xcresulttool version: {ver}", file=sys.stderr)

    if ver == 0:
        emit_error(xcresult_path, ver,
                   "xcresulttool not found — is Xcode installed and xcrun in PATH?")
        sys.exit(1)

    # 3. Fetch summary to enumerate failed tests
    try:
        summary = get_summary(xcresult_path, ver)
    except json.JSONDecodeError as e:
        emit_error(xcresult_path, ver, f"JSON parse error from xcresulttool summary: {e}")
        sys.exit(2)
    except RuntimeError as e:
        emit_error(xcresult_path, ver, str(e))
        sys.exit(1)

    # 4. Normalize testFailures field (may be dict OR list — isinstance() required)
    raw_failures = normalize_test_failures(summary)
    print(
        f"[parse_failure] Found {len(raw_failures)} failure(s) in summary",
        file=sys.stderr
    )

    # 5. Load optional raw patrol/xcodebuild log (supplements finder_context extraction)
    raw_log = None
    if args.log and os.path.exists(args.log):
        try:
            with open(args.log, encoding="utf-8", errors="replace") as f:
                raw_log = f.read()
        except OSError as e:
            print(f"[parse_failure] WARNING: could not read --log file: {e}",
                  file=sys.stderr)

    # 6. Parse each failure: fetch per-test details, extract signal/stack/finder
    failures = []
    for raw_tf in raw_failures:
        test_id = raw_tf.get("testIdentifierString", "")
        print(f"[parse_failure] Fetching details for: {test_id}", file=sys.stderr)
        details = get_test_details(xcresult_path, test_id, ver) if test_id else {}
        failures.append(parse_one_failure(raw_tf, details, raw_log))

    # 7. Build top-level output object
    output = {
        "source": "xcresult",
        "xcresult_path": os.path.abspath(xcresult_path),
        "xcresult_version": ver,
        "failures": failures,
    }
    out_str = json.dumps(output, indent=2)

    # 8. Emit to stdout (JSON only — progress has gone to stderr)
    print(out_str)

    # 9. Optionally write to --out file
    if args.out:
        out_path = os.path.abspath(args.out)
        out_dir = os.path.dirname(out_path)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        try:
            with open(out_path, "w", encoding="utf-8") as f:
                f.write(out_str)
            print(f"[parse_failure] Output written to {args.out}", file=sys.stderr)
        except OSError as e:
            print(f"[parse_failure] WARNING: could not write --out file: {e}",
                  file=sys.stderr)

    # Exit 0 whether or not failures were found (empty failures[] is valid)
    sys.exit(0)


if __name__ == "__main__":
    main()
