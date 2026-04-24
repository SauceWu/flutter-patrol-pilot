---
name: Bug report
about: A script misbehaves, emits invalid JSON, or crashes the iteration loop
title: "[bug] "
labels: bug
assignees: ''
---

## What happened

<!-- One-paragraph description. Paste the failing JSON / stderr verbatim if useful. -->

## Which script / doc

- [ ] `scripts/boot_sim.sh`
- [ ] `scripts/build.sh`
- [ ] `scripts/run_test.sh`
- [ ] `scripts/sim_snapshot.sh`
- [ ] `scripts/parse_failure.py`
- [ ] `reference/failure-triage.md`
- [ ] `reference/iteration-protocol.md`
- [ ] `reference/patrol-patterns.md`
- [ ] `reference/troubleshooting.md`
- [ ] `SKILL.md` / `templates/*`
- [ ] Other: ______

## Environment

- macOS version:
- Xcode version (`xcodebuild -version`):
- Flutter version (`flutter --version`):
- Patrol CLI version (`patrol --version`):
- Simulator device + iOS runtime:

## Reproduction

1.
2.
3.

## Expected

<!-- What should the script/skill have done? Remember: scripts must ALWAYS emit a single valid JSON object on stdout, even on failure. -->

## Actual

```json
<!-- paste the stdout JSON (or the non-JSON output that violated the contract) -->
```

```
<!-- paste relevant stderr -->
```

## Anything else?
