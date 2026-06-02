# KB_ROLE_CONTRACT

## Purpose
Define the KB as the store for sanctioned source-bearing assets, sanctioned knowledge assets, and curated collections over those assets.

## Scope
Applies to all assets admitted into the KB and to the minimum provenance and review discipline for those assets.

## Storage root boundary
The live KB corpus lives outside this repository under the OpenClaw workspace KB root.
The expected live KB root is configured at runtime, for example through `OPENCLAW_WORKSPACE_KB_ROOT` as described by `control-plane/runtime/integrations/kb.template.yaml` and `control-plane/contracts/schemas/kb_runtime_integration.schema.json`.

`knowledge/kb/` in this repository describes KB layout, admission discipline, and curated examples only. It is not the storage location for the full live KB corpus.

## Allowed behavior
- Store source-bearing assets with stable representations and provenance metadata.
- Store knowledge assets that passed review and are fit for downstream retrieval.
- Store collections that organize sanctioned assets for retrieval or navigation.
- Preserve identifiers linking sanctioned assets back to review and source context.

## Forbidden behavior
- Storing raw task packets, result packets, queue exports, or mutable workflow state.
- Storing the full live KB corpus in this repository unless an asset is explicitly curated as an example.
- Admitting assets without provenance minimums.
- Treating collection structure as a hidden workflow board.
- Using KB storage as a scratchpad for draft semantic notes.

## Required checkpoints
1. Classify every asset as source-bearing, knowledge, or collection support.
2. Confirm approval and admission state before ingestion.
3. Confirm provenance and stable representation.
4. Confirm the asset is intelligible without requiring hidden operational context.
5. Confirm the intended storage target is the workspace KB root unless the asset is explicitly curated as a repository example.

## Interaction with adjacent layers
- **Admission policy:** determines entry threshold.
- **Review decision:** authorizes or blocks KB placement.
- **Obsidian:** may provide draft precursors to knowledge assets.
- **Retrieval:** KB is the preferred source for sanctioned reusable material.
- **Runtime integration template:** identifies the workspace KB root configuration surface without storing the live corpus in Git.

## Examples
- A curated HTML snapshot with provenance metadata as a source-bearing asset.
- An approved architecture brief as a knowledge asset.
- A collection grouping all approved architecture assets.

## Failure modes / common mistakes
- Ingesting source packages that only contain a link and no stable representation.
- Copying Notion workflow exports into KB because they seem informative.
- Treating `knowledge/kb/` in Git as the live KB corpus root.
- Storing draft working notes without clear approval.
- Losing linkage between knowledge assets and the source-bearing assets that support them.
