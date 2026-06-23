# Admission

`operations/admission/` contains the Admission Stage 1 universal package scaffold and the Admission Stage 2 universal handoff contract.

It performs dry-run validation for:

- `source_capture.v1`
- `knowledge_asset.v1`

Admission validates generic package admissibility only.
It does not run Phase2, Phase3, Phase4, OpenClaw, canonical writes, KB writes, or type-specific semantic validation.

Admission Stage 2 adds `admission_handoff.json` as a contract bridge into existing Phase inputs. It is not a runner or admission engine. Phase2 owns policy/readiness, Phase4 is the normal operator-facing wrapper, and Phase3 is the sole canonical execution and evidence owner.

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
For Stage 1 validation and CI setup, the repository currently reuses the existing requirements surface at `operations/harness-phase2/requirements.txt`.
Long-term admission dependency ownership is not defined by this PR.
No custom or fallback JSON Schema validator exists in this scaffold.

## Stage 2

Schema:

```text
operations/admission/schemas/admission_handoff.v1.schema.json
```

Examples:

```text
operations/admission/examples/stage2/
```

Placement policies:

```text
operations/admission/placement-policies/registry.v1.json
```
