# Phase 1: Reference Documentation - Context

**Gathered:** 2026-04-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Create three reference documents used by the agent during iteration loop execution:
- `reference/failure-triage.md` — failure classification table (5-A through 5-E)
- `reference/patrol-patterns.md` — Patrol 4.x syntax cheatsheet
- `reference/troubleshooting.md` — top iOS/CocoaPods/Xcode failure modes with fixes

These are READ-ONLY reference docs. No scripts, no templates, no code changes.

</domain>

<decisions>
## Implementation Decisions

### Failure Triage Table Design
- Signal-first quick-reference table at the top for fast lookup during iteration
- Per-category detail blocks below with: signal patterns, permitted actions, forbidden actions, example fixes
- Category 5-E (unknown) must include mandatory a11y tree step before any action
- Include the specific xcresulttool Xcode 16+ subcommand syntax in 5-A examples
- Add "Total: 0 tests" detection rule as a 5-A subcategory (silent failure mode)
- Split xcodebuild code-65 into sub-categories in the 5-A detail block

### Patrol Patterns Cheatsheet Organization
- Organized by concept: Finders → Interactions → Assertions → Pump/Settle strategies
- Patrol 4.x syntax throughout; show both `$.native` and `$.platform.mobile` aliases
- Include chained finders (`containing()`) and Symbol shorthand (`$(#key)`)
- List all finder argument types: String, RegExp, Type, Symbol, Key, IconData
- Include all SettlePolicy enum values with when-to-use guidance
- Note `SettlePolicy.trySettle` as the recommended template default

### Troubleshooting Doc Structure
- Symptom → Cause → Fix numbered steps per issue
- Ordered by frequency (most common first)
- Each fix maps to which iteration-protocol phase handles it (5-A, 5-D, etc.)
- Cover: simulator boot failures, CocoaPods conflicts, xcresulttool deprecation, signing/provisioning errors, PatrolIntegrationTestBinding errors
- Note the `patrol doctor` command for first-run diagnosis

### Claude's Discretion
- Exact markdown formatting within sections (headers, code blocks, tables)
- Level of code examples in patrol-patterns.md (inline vs separate blocks)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- SKILL.md already defines the 5 failure categories (5-A through 5-E) with a draft triage table — use as source of truth for category names
- PLAN.md has the draft failure table (signal → category → action → forbidden) — expand rather than replace

### Established Patterns
- iteration-protocol.md uses numbered phases [0]–[7] — all references in triage/troubleshooting must use these phase numbers
- Docs should be self-contained — no external links required for the agent to act

### Integration Points
- failure-triage.md is read at iteration loop step [5] (Triage)
- patrol-patterns.md is read when generating or fixing test code (steps [0] and [6])
- troubleshooting.md is read for category 5-D (environment) and 5-A (build) fixes at step [6]

</code_context>

<specifics>
## Specific Ideas

- Research from FEATURES.md (agent acf6be7a9494f29d3): the triage table must distinguish 5-B (timeout) from 5-C (assertion) via exception class name — `TestFailure` = 5-C, `TimeoutException` = 5-B
- Research from PITFALLS.md (agent a5dd66d99e358c0f7): add pre-triage check for xcresulttool output validity (empty/null = 5-D, not 5-E)
- Research from STACK.md: xcresulttool Xcode 16+ uses `get test-results summary --compact`, not `--legacy`

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>
