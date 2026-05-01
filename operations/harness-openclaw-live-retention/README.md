# OpenClaw Live Secret Retention Surface

This harness is a bounded live-adjacent surface for:

- validating a reviewed outside-Git secret/material source declaration
- validating an outside-Git candidate evidence directory
- retaining redacted copies under a repo-local run directory

It writes retained evidence only under `operations/harness-openclaw-live-retention/runs/<RUN_ID>/`.

This surface does not load real secrets, read local overlay material, mutate runtime targets, grant approval, perform rollback, implement live runtime apply, create a live-runtime adapter/wrapper, or approve Crab invocation.

## Usage

```bash
bash operations/harness-openclaw-live-retention/bin/run_secret_retention_surface.sh \
  --source-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --candidate-evidence-dir <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

The source declaration file and candidate evidence directory must both be outside Git.
Candidate evidence may contain only `.json`, `.md`, `.log`, or `.txt` files.

## Evidence

Each run writes:

- `retention_meta.json`
- `retention_report.json`
- `checks/source_declaration_validation.json`
- `checks/candidate_evidence_validation.json`
- `checks/redaction_validation.json`
- `retained/`
- `exit_code`

Retained files are redacted copies only.

## CI

```bash
make live-secret-retention-ci
```
