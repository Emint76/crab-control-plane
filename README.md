# crab-control-plane

Versioned control plane for the “Краб” agent harness.

This repository is **not** the live runtime instance of Гоша and is **not** a dump of the existing OpenClaw installation.
It is the governing layer above the system: architecture docs, policies, contracts, schemas, templates, and storage discipline.

## Purpose

This repo defines how the system should be structured across six layers:

1. **runtime** — machine-readable configuration templates
2. **policy** — normative markdown documents
3. **contracts** — structured packet specs and schemas
4. **operations** — Notion workflow model
5. **knowledge** — Obsidian semantic plane and KB layout
6. **observability** — logs, evals, reports, future evolution baseline

## Source of truth by data class

| Data class | Source of truth |
|---|---|
| Runtime templates | `control-plane/runtime/` |
| Policy docs | `control-plane/policy/` |
| Contracts and schemas | `control-plane/contracts/` |
| Operational workflow model | `operations/notion/` |
| Semantic note conventions | `knowledge/obsidian/` |
| KB layout and admission discipline | `knowledge/kb/` + policy docs |
| Observability model | `observability/` |

## Current executable surfaces

| Surface | Entrypoint | Status |
|---|---|---|
| Phase 2 strict check layer | `operations/harness-phase2/bin/run_phase2_check_layer.sh` | external check layer; no render, no runtime-ready, no handoff |
| Phase 2 repo-native scaffold | `operations/harness-phase2/bin/run_phase2_bundle.sh` | validates, renders scaffold decisions, runtime-ready package, conformance, report, handoff readiness |
| Phase 3 execution surface | `operations/harness-phase3/bin/run_phase3_bundle.sh` | canonical execution owner surface; hardened with run-dir invariants, fail-closed behavior, execution target validation, canonical reporting, and CI |
| Phase 4 wrapper | `operations/harness-phase4/bin/run_phase4_wrapper.sh` | thin wrapper over Phase 3; does not own canonical execution outputs; contract: `operations/harness-phase4/PHASE4_WRAPPER_CONTRACT.md` |

Phase 2 has two profiles, not two separate phases:
- `check-layer-strict` is the audit-only profile.
- `repo-native-scaffold` is the package/handoff profile for Phase 3 intake.

`handoff_ready.json` means ready for Phase 3 intake only, not live-runtime-ready, deploy-ready, or launch-ready.

Phase 2 is upstream check/render/handoff preparation. It does not perform live runtime execution.

Phase 3 is the repo-native canonical execution owner surface. It owns canonical run evidence, fail-closed execution behavior, canonical reports, final exit status, and dedicated CI within the repo-native harness boundary.

The detailed Phase 3 target contract is defined in `operations/harness-phase3/PHASE3_EXECUTION_CONTRACT.md`.

Phase 4 must not own canonical execution outputs. It remains a thin wrapper over Phase 3.

The detailed Phase 4 wrapper contract is defined in `operations/harness-phase4/PHASE4_WRAPPER_CONTRACT.md`.

## One-command repo-native smoke

Run:

```bash
make smoke-e2e
```

This proves the repo-native path:

```text
Phase 2 repo-native-scaffold -> Phase 3 canonical execution owner -> Phase 4 thin wrapper
```

It does not perform live OpenClaw runtime mutation, deploy, migration, or production install.

The same smoke path is covered in CI by the `smoke-e2e` workflow.

Direct fallback command for environments where `make` is unavailable:

```bash
bash operations/harness-e2e/tests/test_smoke_e2e.sh
```

For setup and current runnable status, see `INSTALLABILITY.md`.

## Crab-safe invocation

Crab should not call Phase 2, Phase 3, or Phase 4 runners directly.

The approved agent-safe entrypoint is:

```bash
bash operations/harness-orchestration/bin/run_repo_native_smoke.sh
```

This wrapper runs the existing repo-native smoke path and does not perform live OpenClaw runtime mutation, deploy, migration, runtime adapter behavior, real source ingestion, or real KB write-back.

## OpenClaw integration boundary

Future OpenClaw integration is governed by `docs/OPENCLAW_INTEGRATION_BOUNDARY.md`.

The future dry-run adapter contract is defined in `operations/harness-openclaw-dryrun/OPENCLAW_DRY_RUN_ADAPTER_CONTRACT.md`.

The OpenClaw dry-run adapter skeleton is available at:

```bash
bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh \
  --phase3-run-dir operations/harness-phase3/runs/<RUN_ID> \
  --run-id <DRY_RUN_ID>
```

The dry-run proposed placement plan is validated against:

`operations/harness-openclaw-dryrun/schemas/proposed_openclaw_placement_plan.schema.json`

Local-only secrets, identity, credentials, endpoint config, and instance-specific runtime config are governed by `docs/LOCAL_OVERLAY_CONTRACT.md`.

The local overlay must stay outside Git.

Disposable local OpenClaw workspace/state rules are governed by `docs/DISPOSABLE_OPENCLAW_WORKSPACE_CONTRACT.md`.

Disposable workspace/state remains contract-only. The repository still does not implement controlled apply, live runtime apply, deploy, migration, or OpenClaw workspace/state writes.

Controlled disposable apply rules are governed by `docs/CONTROLLED_DISPOSABLE_APPLY_CONTRACT.md`.

Controlled disposable apply remains contract-only. The repository still does not implement controlled apply or OpenClaw workspace/state writes.

Disposable target path validation is available at:

```bash
bash operations/harness-openclaw-target-validation/bin/validate_disposable_target_path.sh \
  --target-type workspace \
  --target-path <ABSOLUTE_PATH> \
  --approved-root <ABSOLUTE_PATH>
```

This is validation only. It does not implement apply or OpenClaw writes.

No-secret-leakage validation is available at:

```bash
bash operations/harness-openclaw-safety-validation/bin/validate_no_secret_leakage.sh \
  --evidence-dir operations/harness-openclaw-dryrun/runs/<RUN_ID>
```

This is validation only. It does not implement apply or OpenClaw writes.

The current repository remains dry-run only for OpenClaw integration. It does not perform live OpenClaw mutation, deploy, migration, disposable workspace apply, live runtime adapter behavior, real source ingestion, or real KB write-back.

It is not approved for Crab invocation yet.

The current repo supports dry-run evidence generation and safety validation only.
Disposable apply and live runtime apply remain unimplemented.

## What belongs elsewhere

- Live runtime state does **not** belong here
- Secrets and tokens do **not** belong here
- Notion board contents do **not** belong here
- Full knowledge corpus does **not** belong here unless explicitly curated as examples

## Recommended next steps

1. Keep Phase 2, Phase 3, and Phase 4 CI green.
2. Continue to keep live runtime state, secrets, and instance-specific config out of this repo.
