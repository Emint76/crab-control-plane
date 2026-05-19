# Hermes Knowledge Pipeline Harness

Repo-local, live-safe harness for a bounded information-processing run.

First supported run:

```text
control-plane/policy/ADMISSION_POLICY.md
→ source capture / evidence
→ normalized note
→ result packet
→ placement/admission candidate
→ canonical knowledge candidate
→ wiki-derived draft
→ validation/report/exit_code
```

Safety boundary:

- no OpenClaw
- no Docker
- no Hermes config/skills/memory/SOUL changes
- no secrets
- no outside-Git paths
- no live/apply/rollout
- no network
- no automatic canonical writes

All first-run writes are confined to:

```text
operations/harness-knowledge-pipeline/runs/knowledge-admission-policy-001/
```

Smoke example:

```bash
operations/harness-knowledge-pipeline/bin/run_local_source_smoke.sh \
  knowledge-admission-policy-001 \
  control-plane/policy/ADMISSION_POLICY.md
```

Core rule:

```text
LLM transforms meaning.
Scripts own evidence, validation, placement boundaries, admission gates, and reports.
```
