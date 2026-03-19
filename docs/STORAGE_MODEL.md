# STORAGE_MODEL

## Storage layers

| Layer | Purpose | Source of truth | Format | Readers | Writers |
|---|---|---|---|---|---|
| Runtime templates | Configure how the orchestrator and integrations should behave | Git repo | JSON / YAML | Orchestrator maintainers, runtime setup processes | Control-plane maintainers |
| Policy | Define normative governance and storage boundaries | Git repo | Markdown | Reviewers, orchestrator designers, prompt authors | Control-plane maintainers |
| Contracts | Define packet and artifact structures | Git repo | Markdown + JSON Schema | Orchestrator, validators, reviewers, template authors | Control-plane maintainers |
| Operations | Track intake, queue state, assignees, and review movement | Notion | Database properties, views, templates | Operators, reviewers, orchestrator adapters | Operators, orchestrator adapters |
| Semantic notes | Preserve human-readable understanding and synthesis | Obsidian vault | Markdown with frontmatter | Researchers, synthesis authors, reviewers | Researchers, synthesis authors |
| Sanctioned KB assets | Preserve approved source-bearing and knowledge assets | KB | Files, metadata, collections | Retrieval workflows, downstream knowledge consumers, reviewers | Curators after admission / approval |
| Observability | Preserve evidence of execution quality and runtime behavior | Observability stores and repo templates | JSONL, Markdown, structured reports | Evaluators, maintainers, incident reviewers | Runtime capture, evaluators, maintainers |

## Layer-specific discipline

### Runtime templates
- **Purpose:** machine-readable defaults for orchestrator behavior and integration configuration.
- **Source of truth:** Git.
- **Format:** YAML and JSON templates only; no live credentials.
- **Who reads it:** runtime maintainers and setup tooling.
- **Who writes it:** control-plane maintainers through reviewed commits.

### Policy
- **Purpose:** define what the system is allowed to do and where artifacts belong.
- **Source of truth:** Git.
- **Format:** markdown-first normative documents.
- **Who reads it:** operators, reviewers, prompt authors, and orchestrator implementers.
- **Who writes it:** control-plane maintainers.

### Contracts
- **Purpose:** define stable packet shapes and artifact validation rules.
- **Source of truth:** Git.
- **Format:** markdown semantics plus JSON Schema for machine validation.
- **Who reads it:** orchestrator, validators, reviewers, and integration authors.
- **Who writes it:** control-plane maintainers.

### Operations / Notion
- **Purpose:** hold active workflow state, queue routing, and review status.
- **Source of truth:** Notion databases.
- **Format:** database rows, statuses, relations, formulas, and templates.
- **Who reads it:** operators, reviewers, runtime adapters.
- **Who writes it:** operators and automation acting on workflow events.

### Semantic plane / Obsidian
- **Purpose:** hold semantic notes that help reasoning, comparison, and durable understanding.
- **Source of truth:** Obsidian vault files.
- **Format:** markdown with constrained frontmatter.
- **Who reads it:** researchers, authors, reviewers.
- **Who writes it:** humans or controlled note-generation workflows producing semantic notes.

### KB
- **Purpose:** hold sanctioned reusable assets, split between source-bearing assets and knowledge assets.
- **Source of truth:** KB storage and metadata.
- **Format:** curated assets plus metadata sufficient for retrieval and provenance.
- **Who reads it:** downstream knowledge consumers, retrieval workflows, reviewers.
- **Who writes it:** curators or approved ingestion workflows after review.

### Observability
- **Purpose:** preserve execution traces, evals, reports, and run diagnostics.
- **Source of truth:** observability systems and versioned report templates.
- **Format:** logs, reports, scorecards, and structured telemetry artifacts.
- **Who reads it:** maintainers, evaluators, reviewers.
- **Who writes it:** runtime capture systems, evaluators, and maintainers.

## What lives where

### Git
- policy documents
- contract markdown and JSON Schemas
- runtime templates
- documentation describing architecture, storage, naming, and boundaries
- examples used to validate packet contracts

### Notion
- intake items
- active task queue rows
- project-level workflow tracking
- review queue state
- assignees, operational priorities, next actions, and handoff status

### Obsidian
- source notes
- concept notes
- permanent notes
- comparison notes
- semantic links and frontmatter metadata for those notes

### KB
- approved source capture packages
- approved curated source-bearing assets
- approved knowledge assets fit for retrieval and reuse
- collections that organize sanctioned assets without becoming workflow state

### Observability
- run logs
- eval outputs
- review metrics
- reports on routing, approval, and failure patterns
- execution traces tied to task and result identifiers

## What must never be stored in markdown
- secrets, tokens, passwords, API keys, private URLs, or environment values
- raw operational queues or mutable task board state
- live runtime telemetry dumps that belong in observability systems
- private user data copied from production systems
- unsanctioned knowledge assets presented as approved KB content

## Boundary rule
A mirror may summarize another layer, but it must not replace that layer's source of truth. For example, a policy document may describe how Notion statuses work, but the active operational state still lives in Notion; an Obsidian note may mention a source, but the sanctioned source-bearing asset belongs in the KB after admission.
