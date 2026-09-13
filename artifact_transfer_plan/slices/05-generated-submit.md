# Slice 5 — generated submit integration

## Purpose

Make generated model nodes prepare real artifact-aware `LlmCallSpec`.

## Files

- `src/vecherinka_comptime.nim`
- `src/vecherinka_runtime.nim`
- generated-submit tests

## Work

Modify `lower_model_call` around current `src/vecherinka_comptime.nim:586`:

1. Unpack expected input branch.
2. Receive input `ArtifactMeta`.
3. Allocate fresh output metadata/root.
4. Invoke input materializer.
5. Build output schema and location contract.
6. Build typed output decoder.
7. Build `finish_work` tool descriptor.
8. Build complete prompt payload.
9. Call `submit_llm` through existing transport seam.

Extend `LlmCallSpec` with typed metadata and textual protocol fields:

- `materialized_input`;
- `artifact_id`;
- `artifact_dir`;
- `location_contract`;
- `output_schema`;
- existing `typed_context` retained temporarily for test compatibility.

Prompt must state:

- task;
- working directory;
- modify only that directory;
- input field values;
- `Location` relative-path rules;
- location contract;
- `finish_work` exact-once rule;
- output schema.

Keep `debug_tool_registry` only as explicit compatibility/test helper. Normal generated path uses `finish_work` descriptor.

## Test gate

Fake transport asserts:

- input instructions present;
- destination directory exists;
- copied input payload exists;
- output schema matches output type;
- location contract lists correct fields;
- tool name is `finish_work`;
- tool schema equals output schema;
- output metadata is fresh;
- prompt contains directory restriction;
- existing generated flows still lower.

## Done when

Generated submit prepares all data without opening Codex or resuming flow inline.

