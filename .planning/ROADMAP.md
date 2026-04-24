# Roadmap: flutter-ios-agent-test

**Milestone:** v1
**Granularity:** Coarse (3 phases)
**Coverage:** 10/10 v1 requirements mapped

---

## Phases

- [ ] **Phase 1: Reference Documentation** - Failure triage, patrol patterns cheatsheet, and troubleshooting guide authored and accurate to Patrol 4.x / Xcode 16+
- [ ] **Phase 2: Scripts** - All five agent-callable scripts executable, emitting correct JSON, and covering the full build-test-triage-snapshot pipeline
- [ ] **Phase 3: Templates & Completion** - Dart test template and CLAUDE.md snippet usable, skill iteration loop verified end-to-end

---

## Phase Details

### Phase 1: Reference Documentation
**Goal**: The agent has accurate, unambiguous reference docs it can consult during any step of the iteration loop — triage, code generation, and troubleshooting — without hallucinating APIs or guessing at failure categories
**Depends on**: Nothing (first phase)
**Requirements**: REF-01, REF-02, REF-03
**Success Criteria** (what must be TRUE):
  1. Agent can classify any failure from the signal → category → action table in failure-triage.md without ambiguity — all 5 categories (5-A through 5-E) have signal patterns, permitted actions, and forbidden actions
  2. Agent can generate or repair Patrol test code using only patrol-patterns.md as a reference — all finder types, chained finders, interaction methods, assertions, and pump/settle strategies are present with correct Patrol 4.x syntax
  3. Agent can resolve the top iOS / CocoaPods / signing / xcresulttool failure modes by following troubleshooting.md step-by-step, without needing to search external docs
  4. All three docs reflect Patrol 4.x APIs (test_directory: patrol_test/, $.platform.mobile naming, no bindingType param) and Xcode 16+ xcresulttool subcommand syntax (not the deprecated --legacy form)
**Plans**: TBD

### Phase 2: Scripts
**Goal**: The agent can drive the full build-test-triage-snapshot pipeline using shell scripts that emit clean JSON summaries, keeping the iteration loop within the 30k token budget
**Depends on**: Phase 1
**Requirements**: SCRIPT-01, SCRIPT-02, SCRIPT-03, SCRIPT-04, SCRIPT-05
**Success Criteria** (what must be TRUE):
  1. `boot_sim.sh <device>` exits 0 whether or not the simulator was already booted, and stdout is valid JSON containing the UDID and state — no raw simctl output leaks to stdout
  2. `build.sh --sim <UDID>` runs patrol build ios --simulator, installs the app, and emits a JSON summary with success/failure status; on failure the error field contains at most the first 5 build error lines (not the full log)
  3. `run_test.sh --sim <UDID> --target <file>` runs patrol test, parses xcresult using the Xcode-version-adaptive strategy (new subcommand API for Xcode 16+, --legacy for Xcode 15), writes `.test-results/latest.json`, and emits identical JSON to stdout
  4. `parse_failure.py <xcresult>` returns a structured JSON array of failure objects with test_name, signal, file, line, message, raw_stack (SDK frames stripped), and finder_context populated from xcresulttool output
  5. `sim_snapshot.sh --sim <UDID>` defaults to a11y tree mode, falls back to screenshot with a warning if axe is absent, and stdout JSON includes a truncated tree_summary (not the full tree) to protect the token budget
**Plans**: TBD

### Phase 3: Templates & Completion
**Goal**: Any user can copy the patrol_test_template.dart into their project and start writing tests immediately, and any project CLAUDE.md that includes the snippet activates the full skill automatically
**Depends on**: Phase 2
**Requirements**: TMPL-01, TMPL-02
**Success Criteria** (what must be TRUE):
  1. `templates/patrol_test_template.dart` compiles and runs as-is against a default Flutter project with Patrol 4.x installed — it contains correct imports, patrolSetUp/patrolTearDown (not setUp/tearDown), patrolTest() wrapper, PatrolTesterConfig with trySettle default, and inline guidance comments
  2. A developer can paste `templates/CLAUDE_md_snippet.md` into their project CLAUDE.md and Claude Code will correctly invoke the skill — the snippet covers: activation triggers, mandatory pre-flight checks, test directory convention, skill location, the three hard rules, and an iteration limit reminder
  3. The SKILL.md iteration loop (boot → build → run → triage → fix → repeat) works end-to-end using only the reference docs, scripts, and templates produced in phases 1–3, with no missing file references or undefined variables in any script
**Plans**: TBD

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Reference Documentation | 0/0 | Not started | - |
| 2. Scripts | 0/0 | Not started | - |
| 3. Templates & Completion | 0/0 | Not started | - |

---

*Roadmap created: 2026-04-24*
*Last updated: 2026-04-24 after initial creation*
