# DECISION_MODEL

## Core rule

If an artifact looks both like a task object and a knowledge object:

- store workflow state in Notion
- store semantic content in Obsidian
- store sanctioned approved version in KB
- store logs and traces in observability

## Quick routing

| Artifact type | Default destination |
|---|---|
| intake item | Notion |
| task object | Notion |
| review object | Notion |
| semantic note | Obsidian |
| sanctioned knowledge asset | KB |
| source capture package | KB after review |
| run log / eval output | Observability |
