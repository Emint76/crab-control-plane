# STORAGE_MODEL

## Storage layers

| Layer | Purpose | Source of truth | Format |
|---|---|---|---|
| Runtime | Machine-readable configuration templates | Git repo | JSON / YAML |
| Policy | Normative rules and governance | Git repo | Markdown |
| Contracts | Structured exchange models | Git repo | Markdown + JSON Schema |
| Operations | Workflow state | Notion | Database properties / views |
| Knowledge | Semantic notes and sanctioned assets | Obsidian / KB | Markdown + structured metadata |
| Observability | Runs, logs, evals, reports | Repo + run artifacts | JSONL / Markdown / structured files |

## What stays out of markdown

- secrets
- tokens
- passwords
- private environment values
- raw live state dumps
