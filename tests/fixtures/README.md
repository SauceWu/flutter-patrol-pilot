# Test fixtures

JSON snippets representing the shape of `xcresulttool` output and individual
`testFailures` / `TestDetails` entries — used by `tests/test_parse_failure.py`
to assert end-to-end parsing behavior without depending on a live xcresult
bundle.

| File | Source | Used by |
|---|---|---|
| `raw_tf_assertion_failure.json` | One entry from a real `testFailures` array (Xcode 16+ new API). Plausible app-code stack with SDK frames mixed in. | `TestParseOneFailureFromFixture::test_assertion_failure_fixture` |
| `details_assertion_failure.json` | Companion `TestDetails` payload for the same test, with `Failure Message` nodes nested two levels deep (testRuns → Test Case → Failure Message). | same |
| `raw_tf_xcode26_dyld.json` | Xcode 26 + Flutter `_Testing_Foundation.framework` dyld crash signal. No `testIdentifierString` deep tree — typical legacy / no-details scenario. | `test_xcode26_dyld_failure_fixture` |

These are **synthetic** but match the schema observed across multiple real
xcresult bundles during skill development. They are NOT real bug reports —
do not infer customer behavior from them.

## Adding a new fixture

When extending `SIGNAL_PATTERNS` in `parse_failure.py` with a new failure
class, add a corresponding `raw_tf_<signal>.json` here and a test method in
`TestParseOneFailureFromFixture`. The `failureText` field should contain the
canonical signal substring (or whatever variant you observed in the wild).
