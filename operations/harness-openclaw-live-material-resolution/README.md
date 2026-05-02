# Live Material-Resolution Bundle

This surface creates a bounded repo-local material-resolution bundle for future wrapper use.

It consumes:

- a green repo-local live wrapper preflight run directory
- a reviewed outside-Git secret/material source declaration

It emits refs-only material-resolution evidence under:

```text
operations/harness-openclaw-live-material-resolution/runs/<RUN_ID>/
```

Run:

```bash
bash operations/harness-openclaw-live-material-resolution/bin/run_live_material_resolution.sh \
  --wrapper-preflight-run-dir operations/harness-openclaw-live-wrapper/runs/<RUN_ID> \
  --source-declaration-file <ABSOLUTE_PATH_OUTSIDE_GIT> \
  --run-id <RUN_ID>
```

This is material-resolution only. It validates declared material paths and emits repo-local references and metadata only.

It does not:

- perform live runtime apply
- mutate targets
- grant approval
- execute rollback
- load raw secrets into repo-local artifacts
- read broader local overlay material
- create the live wrapper
- approve Crab invocation
