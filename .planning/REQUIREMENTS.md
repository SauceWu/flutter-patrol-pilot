# Requirements: flutter-ios-agent-test

**Defined:** 2026-04-24
**Core Value:** The agent can take any Flutter test intent, run it on a real iOS simulator, and fix failures without human intervention — stopping cleanly when it genuinely cannot make progress.

## v1 Requirements

### Reference Docs

- [ ] **REF-01**: Failure triage table covers all known failure categories (5-A through 5-E) with signal patterns, actions, and forbidden actions — accurate enough for agent triage without ambiguity
- [ ] **REF-02**: Patrol patterns cheatsheet covers finders, interactions, assertions, and pump strategies for Patrol 4.x — usable as a code generation reference
- [ ] **REF-03**: Troubleshooting doc covers the top iOS simulator / CocoaPods / signing / xcresulttool failure modes with specific resolution steps

### Scripts

- [ ] **SCRIPT-01**: `scripts/boot_sim.sh <device>` boots the named simulator idempotently, emits JSON with UDID and state, exits 0 if already booted
- [ ] **SCRIPT-02**: `scripts/build.sh --sim <UDID>` runs `patrol build ios --simulator`, installs the .app, emits JSON summary; failure output includes first 5 build error lines only (not raw log)
- [ ] **SCRIPT-03**: `scripts/run_test.sh --sim <UDID> --target <file>` runs patrol test, parses xcresult, writes `.test-results/latest.json` and emits it to stdout
- [ ] **SCRIPT-04**: `scripts/parse_failure.py <xcresult>` parses xcresult into structured failure signals JSON with fields: test_name, signal, file, line, message, raw_stack, finder_context
- [ ] **SCRIPT-05**: `scripts/sim_snapshot.sh --sim <UDID> [--tree|--screenshot]` captures a11y tree (default) or screenshot; emits JSON with path and truncated tree_summary; falls back to screenshot if axe not installed

### Templates

- [ ] **TMPL-01**: `templates/patrol_test_template.dart` is a complete, runnable Patrol 4.x test starter with proper initialization, imports, patrolTest() wrapper, and inline guidance comments
- [ ] **TMPL-02**: `templates/CLAUDE_md_snippet.md` gives users a copy-paste block for their project CLAUDE.md that activates this skill automatically for Flutter iOS test requests

## v2 Requirements

### Multi-Simulator Support

- **MSIM-01**: Support parallel test execution across multiple iOS simulators
- **MSIM-02**: Script flag to target a specific simulator device model (not just iPhone 16)

### CI/CD Integration

- **CI-01**: Scripts work in headless CI mode (GitHub Actions, Bitrise) without Simulator.app opening
- **CI-02**: Output format compatible with CI test reporting (JUnit XML or GitHub Actions annotations)

### Coverage & Reporting

- **COV-01**: `patrol test --coverage` integration in run_test.sh
- **COV-02**: Token budget validation: typical 6-iteration run stays ≤ 30k tokens

## Out of Scope

| Feature | Reason |
|---------|--------|
| Android testing | Different toolchain entirely; ios-simulator-skill handles iOS |
| Flutter web / desktop | iOS simulator only for this skill |
| MCP server packaging | Deferred — validate skill format first |
| Auto-committing generated tests | User decides whether to commit test files |
| Xcode Cloud integration | Too platform-specific; CI scope is v2+ |
| Auto-install of globally missing tools | Must not auto-install without asking (per SKILL.md hard rule) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| REF-01 | Phase 1: Reference Documentation | Pending |
| REF-02 | Phase 1: Reference Documentation | Pending |
| REF-03 | Phase 1: Reference Documentation | Pending |
| SCRIPT-01 | Phase 2: Scripts | Pending |
| SCRIPT-02 | Phase 2: Scripts | Pending |
| SCRIPT-03 | Phase 2: Scripts | Pending |
| SCRIPT-04 | Phase 2: Scripts | Pending |
| SCRIPT-05 | Phase 2: Scripts | Pending |
| TMPL-01 | Phase 3: Templates & Completion | Pending |
| TMPL-02 | Phase 3: Templates & Completion | Pending |

**Coverage:**
- v1 requirements: 10 total
- Mapped to phases: 10
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-24*
*Last updated: 2026-04-24 after roadmap creation*
