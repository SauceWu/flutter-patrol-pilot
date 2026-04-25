# Tests

Unit tests for the parts of `flutter-patrol-pilot` that have non-trivial
internal logic — primarily `scripts/parse_failure.py`, the **signal
extractor that decides what category every test failure goes into**.
A regression here silently flips agent behavior (e.g. a TimeoutException
suddenly gets classified as a TestFailure), so this is the highest-value
piece of the skill to keep under test.

Pure stdlib only — no `pytest`, no `pip install`. The skill is loaded into
agent contexts that don't always have a Python venv handy.

## Run

From the skill root:

```bash
python3 -m unittest discover tests -v
```

Just one file:

```bash
python3 -m unittest tests.test_parse_failure -v
```

A specific test:

```bash
python3 -m unittest tests.test_parse_failure.TestParseDartStack.test_sdk_then_user_anti_pattern_5
```

Expected: **36 tests, all passing, < 0.1s.** If the suite takes longer
than a second something is wrong (no test should hit the network or
spawn `xcrun`).

## Layout

```text
tests/
├── __init__.py                              # marks `tests` as a package
├── README.md                                # this file
├── test_parse_failure.py                    # 36 cases, 8 TestCase classes
└── fixtures/
    ├── README.md                            # source-of-truth for each fixture
    ├── raw_tf_assertion_failure.json        # one xcresult testFailures entry
    ├── details_assertion_failure.json       # companion TestDetails tree
    └── raw_tf_xcode26_dyld.json             # Xcode 26 dyld signal, no details
```

## What's covered

| Function in `parse_failure.py` | Test class | # cases |
|---|---|---|
| `normalize_test_failures()` | `TestNormalizeTestFailures` | 5 (list / dict / None / missing / unexpected type) |
| `classify_signal()` | `TestClassifySignal` | 22 known patterns + 2 unknown + 3 priority ordering + 1 size guard |
| `extract_first_substantive_line()` | `TestExtractFirstSubstantiveLine` | 4 (noise filter / empty / truncate / fallback) |
| `parse_dart_stack()` | `TestParseDartStack` | 8 (SDK only / user only / mixed / Anti-Pattern 5 / package→lib / test path / patrol_test path / 10-frame cap) |
| `extract_finder_context()` | `TestExtractFinderContext` | 6 (widget msg / no-widget msg / `$()` log / log priority / fallback / msg-over-log precedence) |
| `extract_failure_messages()` | `TestExtractFailureMessages` | 4 (top-level / nested / empty / `details` fallback) |
| `parse_one_failure()` end-to-end | `TestParseOneFailureFromFixture` | 2 (assertion-failure roundtrip / no-details xcode26 case) |

**Not covered** (deliberately, would require subprocess mocking or live xcrun):

- `get_xcresulttool_version()` — single subprocess call, low complexity
- `run_xcresulttool()` — thin wrapper
- `get_summary()` / `get_test_details()` — also thin wrappers
- `main()` end-to-end CLI — covered indirectly by `parse_one_failure()` tests + manual smoke

If a future change makes one of these non-trivial, add a test class with a
`unittest.mock.patch('subprocess.run', ...)` decorator.

## Design principles (read before adding tests)

1. **One subTest per row, not 22 separate methods.** `classify_signal`'s
   pattern table is checked via `subTest()` so failure messages identify
   exactly which row fell over.
2. **Priority tests are the regression net.** When `SIGNAL_PATTERNS` is
   reordered, `test_priority_*` cases will catch silent classification
   flips — this is by design, not a flake.
3. **Size assertion guards drift.** `test_signal_patterns_table_size_baseline`
   ensures the test catalog grows with the production catalog. If you add
   a new `SIGNAL_PATTERNS` entry, also add a `KNOWN_PATTERNS` row.
4. **Fixtures are minimal but realistic.** They model the *shape* of
   `xcresulttool` output, not customer data. See `fixtures/README.md` for
   the schema-of-record per fixture.
5. **No flakes, no network, no real xcrun.** If a test ever needs a real
   tool, isolate it behind `@unittest.skipUnless(shutil.which("xcrun"))`.

## Adding a new SIGNAL_PATTERNS entry

The minimum viable patch:

1. Add the `(needle, canonical)` tuple to `SIGNAL_PATTERNS` in `scripts/parse_failure.py`.
2. Add a row to `TestClassifySignal.KNOWN_PATTERNS` in `test_parse_failure.py`.
3. If your new signal is more-specific than an existing one (e.g. another
   variant of `TimeoutException`), add a `test_priority_*` method asserting
   it shadows the generic one.
4. Document the canonical in `reference/failure-triage.md` Section 2 quick-reference table — the agent looks up `category` from there.

Run `python3 -m unittest discover tests -v` and ship.
