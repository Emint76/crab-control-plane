# OPENCLAW_DRY_RUN_ADAPTER_CONTRACT

## Purpose

This contract defines the future OpenClaw dry-run adapter boundary.
The adapter may inspect repo-native harness evidence and produce a proposed OpenClaw placement plan.
It must not mutate OpenClaw runtime, workspace, state, KB, memory, secrets, or live configuration.

## Status

This is a contract-only document.
No adapter implementation is included in this PR.

## Scope

Allowed future scope:

```text
repo-native Phase 2/3 evidence -> proposed OpenClaw placement plan -> dry-run evidence only
```

Forbidden scope:

```text
repo-native evidence -> live OpenClaw writes
```

## Approved future entrypoint

Reserved future entrypoint:

```bash
bash operations/harness-openclaw-dryrun/bin/run_openclaw_dry_run.sh --phase3-run-dir <PHASE3_RUN_DIR> --run-id <RUN_ID>
```

This command is reserved for future implementation and is not available yet.

## Inputs

Future adapter inputs may include:

```text
--phase3-run-dir operations/harness-phase3/runs/<RUN_ID>
--run-id <SAFE_RUN_ID>
```

Optional future input:

```text
--phase2-run-dir operations/harness-phase2/runs/<RUN_ID>
```

Validation requirements:

- run ids must match `^[A-Za-z0-9._-]+$`
- no absolute paths
- no `../` traversal
- no path separators in run id
- Phase 3 run dir must be repo-relative
- Phase 3 run dir must be under `operations/harness-phase3/runs/`

## Allowed reads

The future adapter may read these repo-local inputs only if they exist:

- `operations/harness-phase3/runs/<RUN_ID>/run_meta.json`
- `operations/harness-phase3/runs/<RUN_ID>/report.json`
- `operations/harness-phase3/runs/<RUN_ID>/report.md`
- `operations/harness-phase3/runs/<RUN_ID>/staging/runtime-ready-applied/`
- `operations/harness-phase3/runs/<RUN_ID>/checks/`
- `operations/harness-phase3/runs/<RUN_ID>/input/`
- `operations/harness-phase2/runs/<RUN_ID>/handoff_ready.json`
- `operations/harness-phase2/runs/<RUN_ID>/apply_plan.json`
- `operations/harness-phase2/runs/<RUN_ID>/output/runtime-ready/`

## Forbidden reads

The future adapter must not read:

- `.env`
- secrets files
- tokens
- local overlay with credentials
- real OpenClaw state
- real OpenClaw workspace
- real KB data
- real memory
- runtime logs from real agent
- browser/profile credentials
- SSH keys
- cloud credentials

## Allowed outputs

The future adapter may write only under:

```text
operations/harness-openclaw-dryrun/runs/<RUN_ID>/
```

Future output files:

- `adapter_meta.json`
- `input_refs.json`
- `proposed_openclaw_placement_plan.json`
- `dry_run_report.md`
- `dry_run_report.json`
- `exit_code`
- `checks/run_dir_invariants.json`
- `checks/input_refs_validation.json`
- `checks/no_live_write_validation.json`

## Forbidden outputs

The future adapter must not write:

- OpenClaw state
- OpenClaw workspace
- real KB
- real memory
- local overlay
- secrets files
- `.env`
- runtime config
- deployment files outside its dry-run run dir

## Write surface

The only approved write surface for the future dry-run adapter is:

```text
operations/harness-openclaw-dryrun/runs/<RUN_ID>/
```

Generated artifacts under this path must be gitignored except `.gitkeep`.

This PR does not create an adapter implementation, implementation directories, run directories, or generated artifacts.

## Proposed placement plan

Future proposed placement evidence should be machine-readable and conceptually follow this shape:

```json
{
  "status": "dry-run",
  "target_runtime": "openclaw",
  "source_phase3_run_dir": "operations/harness-phase3/runs/<RUN_ID>",
  "proposed_writes": [
    {
      "source": "operations/harness-phase3/runs/<RUN_ID>/staging/runtime-ready-applied/<path>",
      "target": "<repo-relative-or-declared-openclaw-target>",
      "write_mode": "proposed-only",
      "reason": "<why this placement is proposed>"
    }
  ],
  "live_writes_performed": false
}
```

The actual schema may be introduced in a future PR.

## Evidence requirements

Future adapter evidence must prove:

- no live writes were performed
- no secrets were read
- input refs are repo-relative
- output refs are under dry-run run dir
- proposed placements are proposed-only
- exit status is explicit

## Run directory invariants

The future adapter must include Phase 2/3-style invariant evidence:

```text
checks/run_dir_invariants.json
```

Required semantics:

- `status == pass`
- `run_id == <RUN_ID>`
- `canonical_run_dir == operations/harness-openclaw-dryrun/runs/<RUN_ID>`
- `run_dir_identity_verified == true`
- `write_surface_verified == true`
- `violations == []`

## Relationship to Phase 2

Phase 2 prepares and validates package/handoff evidence.
The dry-run adapter must not redefine Phase 2, Phase 3, or Phase 4.

## Relationship to Phase 3

Phase 3 remains canonical repo-native execution owner.
The dry-run adapter must not redefine Phase 2, Phase 3, or Phase 4.

## Relationship to Phase 4

Phase 4 remains a thin wrapper over Phase 3.
The dry-run adapter must not redefine Phase 2, Phase 3, or Phase 4.

## Relationship to Crab-safe orchestration

Crab must not call future OpenClaw dry-run commands until an explicit approved wrapper, tests, and CI exist.
This contract alone does not approve Crab invocation.

## Secrets and identity boundary

The dry-run adapter must not require secrets, tokens, model credentials, bot identity, channel IDs, endpoint credentials, or instance-specific local config.

## Local-only assumptions

Future disposable OpenClaw workspace/state and local overlay remain outside Git.
This contract does not define disposable apply yet.

## Failure behavior

Future adapter implementation must fail non-zero if:

- invalid run id
- Phase 3 input missing
- Phase 3 report not pass
- input refs outside allowed surfaces
- attempted live write detected
- secret-like file requested
- output path escapes dry-run run dir

## Non-goals

- no adapter implementation in this PR
- no OpenClaw runtime mutation
- no deploy
- no migration
- no disposable workspace apply
- no live runtime apply
- no real source ingestion
- no real KB write-back
- no secrets/config management
- no Phase 2/3/4 behavior changes
- no Crab invocation approval yet

## Acceptance criteria for future implementation

- adapter implementation exists
- dry-run run-dir invariants exist
- no-live-write validation exists
- input refs validation exists
- proposed placement plan is machine-readable
- tests cover positive and negative cases
- CI validates dry-run behavior
- docs confirm no live writes
