# Admission

`operations/admission/` contains the Stage 1 universal admission scaffold.

It performs dry-run validation for:

- `source_capture.v1`
- `knowledge_asset.v1`

Admission validates generic package admissibility only.
It does not run Phase2, Phase3, Phase4, OpenClaw, canonical writes, KB writes, or type-specific semantic validation.

## CLI

```bash
bash operations/admission/bin/run_admission.sh \
  --package <package-directory> \
  --dry-run
```

stdout contains only the JSON result.
Diagnostics and dependency errors are written to stderr.

## Dependencies

The CLI uses Python and the standard `jsonschema` package with Draft 2020-12.
The repo-owned dependency declaration is `operations/harness-phase2/requirements.txt`.
No custom or fallback JSON Schema validator exists in this scaffold.
