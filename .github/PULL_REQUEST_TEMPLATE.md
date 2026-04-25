## What does this PR change?

<!-- One-paragraph description. If this PR is a fix, link the issue. -->

## Scope

- [ ] `scripts/init_project.sh` — one-shot setup (must stay idempotent; stdout single-line JSON summary)
- [ ] `scripts/` (other) — shell / Python (contract: always emit a single JSON object on stdout, even on failure)
- [ ] `reference/` — agent-facing triage / protocol / patterns docs
- [ ] `templates/` — CLAUDE.md / AGENTS.md / Cursor rule snippets, or `patrol_test_template.dart`
- [ ] `SKILL.md` — skill metadata / workflow
- [ ] `README.md` / `CHANGELOG.md` / `LICENSE` / `.github/`
- [ ] Other

## Hard rules checklist (MUST be green before merging)

- [ ] No script swallows errors silently — all non-zero exits emit a JSON object describing the failure on stdout
- [ ] No change makes the iteration loop bypass triage (`reference/iteration-protocol.md` step 4 is sacred)
- [ ] No new script hardcodes a simulator UDID, device name, or bundle ID — all are parameters
- [ ] `description:` in `SKILL.md` stays under ~320 chars and keeps at least 3 Chinese + 2 English trigger phrases
- [ ] If you added a new failure mode to `run_test.sh` / `build.sh`, `reference/failure-triage.md` has a matching row
- [ ] If you changed `init_project.sh`, it stays idempotent (re-running produces no extra changes) and you ran it at least once with `--dry-run` against a clean Flutter project
- [ ] If you touched `scripts/*.sh`, you ran `bash -n scripts/*.sh` locally and it passed
- [ ] If you added a runtime dep, it's documented in `README.md` → Prerequisites, not hidden inside a script
- [ ] If this change is user-visible, `CHANGELOG.md` has a new Unreleased entry

## Test plan

<!-- How did you verify this? Ideally: ran an end-to-end iteration against a real Flutter project with an intentional bug, or at minimum ran the affected script manually and pasted the JSON output here. -->

```json
<!-- paste the relevant script output -->
```

## Risk / impact

<!-- Does this change the contract between skill and agent? If yes, call it out explicitly — the contract is what makes this skill work reliably. -->
