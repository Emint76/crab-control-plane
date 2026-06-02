# KB_LAYOUT

## Purpose
Define the high-level layout and discipline for sanctioned assets in the KB.

## Storage boundary
The live KB corpus lives under the OpenClaw workspace KB root configured at runtime.
The repository path `knowledge/kb/` documents layout, admission discipline, and curated examples only. It must not be treated as the storage location for the full live KB corpus.

## Layout
The workspace KB root uses these top-level layout entries:

- `sources/` for sanctioned source-bearing assets and source capture packages
- `knowledge/` for sanctioned knowledge assets
- `collections/` for curated groupings over sanctioned assets

## Asset classes

### Source-bearing assets
Primary purpose: preserve external source material and provenance in stable form.

Minimum required provenance:
- canonical pointer
- retrieval status
- retrieval timestamp
- content type
- stable representation
- human identifier
- linkage to related note, task, or review identifiers where relevant

### Knowledge assets
Primary purpose: express reusable understanding, synthesis, or structured knowledge for retrieval.

Minimum expectations:
- clear knowledge role or type
- intelligible content without hidden workflow context
- source linkage where claims depend on external evidence
- review outcome suitable for KB placement
- stable identifier for retrieval and maintenance

## Collections
Collections organize sanctioned assets for retrieval or navigation. They do not represent tasks, queues, approvals, or mutable operational ownership.

## Discipline
- KB stores sanctioned assets only.
- Raw workflow and task objects do not belong in the KB because they encode transient operational state, not reusable sanctioned knowledge.
- Draft semantic notes stay in Obsidian until reviewed and admitted.
- Source-bearing and knowledge assets must stay distinguishable; a synthesis note is not a source package, and a captured page is not a final knowledge asset simply because it is useful.
- Full live corpus payloads belong in the runtime-configured workspace KB root, not in this repository, unless explicitly curated as examples.
