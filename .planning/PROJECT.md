# flutter-ios-agent-test

## What This Is

A Claude Code / Claude Desktop skill that lets an agent autonomously validate Flutter functionality on an iOS simulator. The agent accepts test intent (natural language, Patrol `.dart` file, or Markdown spec), compiles the Flutter app, installs it on a simulator, runs Patrol tests, triages failures, fixes code, and iterates until tests pass — stopping cleanly when it hits iteration limits or divergence.

## Core Value

The agent can take any Flutter test intent, run it on a real iOS simulator, and fix failures without human intervention — stopping cleanly and asking for help only when it genuinely cannot make progress.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Reference docs (failure-triage, patrol-patterns, troubleshooting) authored and accurate
- [ ] Scripts (boot_sim, build, run_test, parse_failure, sim_snapshot) executable and tested
- [ ] Templates (patrol_test_template.dart, CLAUDE_md_snippet.md) usable for test generation
- [ ] Skill can be invoked from SKILL.md and drives the full iteration loop

### Out of Scope

- Android-only testing — use platform-native tooling instead
- Flutter web / desktop — iOS simulator only
- Non-Flutter iOS apps — use `ios-simulator-skill` instead
- MCP server packaging — deferred to Phase 4+
- Multi-simulator parallel testing — deferred (single iPhone 16 sim for MVP)
- Auto-committing generated tests — user decides

## Context

- Session 1 (2026-04-24): Design discussion completed, SKILL.md and reference/iteration-protocol.md written
- Key decisions locked: Patrol (over integration_test), xcrun simctl + patrol_cli (no extra MCP), xcresulttool for structured output, 6-iteration default max
- Skill format: standard Claude Code skill (SKILL.md frontmatter + reference docs + scripts + templates)
- Token discipline is critical: scripts emit JSON summaries, full logs stay on disk, screenshots only as last resort

## Constraints

- **Platform**: macOS only — scripts use `xcrun simctl` and Xcode toolchain
- **Flutter version**: ≥ 3.22 required (Patrol 3.x compatibility)
- **Patrol CLI**: Must be installed via `dart pub global activate patrol_cli`
- **Token budget**: Full 6-iteration run must stay ≤ 30k tokens
- **Hard rules**: Never change assertions to pass tests; never delete failing tests; never skip triage step

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Patrol over integration_test | Native iOS capabilities, Hot Restart, LeanCode-maintained | — Pending |
| xcresulttool for output parsing | Log text parsing is unreliable; structured JSON is stable | — Pending |
| 6-iteration default max | Prevents infinite loops without being too restrictive | — Pending |
| a11y tree before screenshot | Screenshots expensive in tokens; a11y tree usually sufficient | — Pending |
| Hard-coded stop conditions | Don't let model "decide" whether to continue — will be overly optimistic | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-24 after initialization*
