# codex-subtask-template

Use this only together with a task packet contract.

## Goal

Execute the delegated subtask exactly as defined by the `TASK_PACKET`. Restate the requested outcome in your own words, but do not broaden scope, invent missing requirements, or change the task type. If a required input or boundary is missing, report the gap in the result instead of filling it with assumptions.

## Constraints

- Treat the `TASK_PACKET` as the controlling contract for scope, constraints, expected outputs, acceptance criteria, and priority.
- Use only the inputs and references listed in the packet unless the packet explicitly authorizes additional source discovery.
- Preserve provenance for every substantive claim so the `RESULT_PACKET.evidence` field can be completed with concrete references.
- Do not change architecture, storage boundaries, policy meaning, or placement decisions unless the packet explicitly requests that work.
- Keep output format aligned with the packet's `expected_outputs` types.
- If blocked, uncertain, or incomplete, record that explicitly in `unresolved_issues` or `warnings` rather than hiding it.

## Expected outputs

Return a `RESULT_PACKET` aligned to the originating task, with at least:

- `task_id` matching the source `TASK_PACKET.id`
- `result_summary` describing what was completed
- `produced_artifacts` listing every artifact, draft, or proposed file/reference created
- `unresolved_issues` listing blockers, open questions, or an explicit empty list if none remain
- `confidence` set to the level supported by the available evidence
- `evidence` capturing the sources, files, notes, or logs used during execution
- `suggested_placement` as an advisory destination for the primary artifact
- `suggested_followups` and `warnings` when they materially help review

If the packet requested a draft document, note, schema adjustment, or review bundle, include that artifact in `produced_artifacts` and make sure its contents satisfy the packet's `acceptance_criteria`.
