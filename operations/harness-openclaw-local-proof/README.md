# Full local disposable cycle proof

This harness is a proof wrapper for the current local-only disposable OpenClaw contour.
It runs the already-approved local surfaces in a fixed order and writes proof-level evidence under its own run directory.

Entrypoint:

```bash
bash operations/harness-openclaw-local-proof/bin/run_full_local_disposable_cycle.sh --run-id <RUN_ID>
```

Proof evidence is written only under:

```text
operations/harness-openclaw-local-proof/runs/<RUN_ID>/
```

The wrapper runs:

```text
make orchestration-ci
make openclaw-dryrun-ci
make disposable-target-validation-ci
make no-secret-leakage-ci
make controlled-disposable-apply-ci
make local-target-selector-ci
```

Proof-level artifacts include:

```text
proof_meta.json
proof_report.json
proof_report.md
checks/run_dir_invariants.json
checks/step_results.json
exit_code
```

Boundary:

- proves the current bounded local disposable contour only
- does not own or rewrite inner canonical evidence
- does not implement live runtime apply
- does not create a live-runtime wrapper
- does not approve Crab invocation
- does not add OpenClaw integration power
