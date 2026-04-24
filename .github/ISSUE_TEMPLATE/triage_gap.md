---
name: Triage gap
about: A real-world failure mode that isn't classified in failure-triage.md, or is misclassified
title: "[triage] "
labels: triage-gap, documentation
assignees: ''
---

## Symptom

<!-- What does the agent see? Paste the relevant chunk of run_test.sh / build.sh JSON output, especially the `failure_text` and `error.log_grep` fields. -->

```json
```

## Current classification (if any)

<!-- Which 5-A / 5-B / 5-C / 5-D bucket did failure-triage.md route this to? Or was there no match at all, so the agent got stuck? -->

## Proposed classification

- Bucket: `5-?`
- Meaning: `testing_infra` / `flutter_env` / `genuine_flutter_bug` / `test_design`
- Fix action: `human` / `agent-fixes-dart` / `agent-fixes-native-config` / `agent-reruns-with-different-inputs`

## Root cause (if known)

<!-- What's actually going wrong under the hood? This is what the agent needs to read to decide. -->

## Suggested reference/failure-triage.md entry

<!-- Optional: draft the entry you think should be added. Follow the existing table format. -->

| Symptom regex / phrase | Bucket | Meaning | Fix action |
|---|---|---|---|
| `...` | `5-?` | `...` | `...` |

## Reproduction (if the gap caused an iteration loop to fail)

1.
2.
3.
