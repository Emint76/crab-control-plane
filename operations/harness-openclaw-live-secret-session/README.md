# Live Secret-Session Bundle

This surface creates a bounded repo-local secret-session bundle for future wrapper use.

It consumes:

- a green repo-local live material-resolution run directory

It loads only the already-resolved outside-Git material source paths from that run, in-process only, and emits repo-local metadata plus redacted observations under:

```text
operations/harness-openclaw-live-secret-session/runs/<RUN_ID>/
```

Run:

```bash
bash operations/harness-openclaw-live-secret-session/bin/run_live_secret_session.sh \
  --material-resolution-run-dir operations/harness-openclaw-live-material-resolution/runs/<RUN_ID> \
  --run-id <RUN_ID>
```

This is secret-session only. It writes refs, metadata, and redacted observations only.

It does not:

- perform live runtime apply
- mutate targets
- grant approval
- execute rollback
- read broader local overlay material beyond declared resolved sources
- write raw secret material into repo-local artifacts
- create the live wrapper
- approve Crab invocation
