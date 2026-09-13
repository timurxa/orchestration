# Slice 5 — generated submit integration

## Purpose

Make generated model nodes prepare real artifact-aware `LlmCallSpec`.

## Status

Partial. Generated submit passes input metadata, runtime directory, working
directory, output kind, and materializer to the injected transport. It still
uses the debug tool, debug materializer, typed-context stringification, and
schema echo.

## Files

- `src/vecherinka_comptime.nim`
- `src/vecherinka_runtime.nim`
- generated-submit tests

## Work

Modify `lower_model_call` around current `src/vecherinka_comptime.nim:586`:

1. Unpack expected input branch.
2. Receive input `ArtifactMeta` and the pre-created working directory.
3. Invoke input materializer.
4. Build output schema.
5. Build typed output decoder.
6. Build `finish_work` tool descriptor.
7. Build complete prompt payload.
8. Call `submit_llm` through existing transport seam.

Extend `LlmCallSpec` with typed metadata and textual protocol fields:

- `materialized_input`;
- `input_meta`;
- `runtime_dir`;
- `working_dir`;
- `output_schema`;
- existing `typed_context` retained temporarily for test compatibility.

Prompt must state:

- task;
- working directory;
- modify only that directory;
- input field values;
- `Location` paths relative to the runtime directory;
- never emit absolute or `..` paths in `Location` values;
- use only the assigned working directory for file changes;
- `finish_work` exact-once rule;
- output schema.

Keep `debug_tool_registry` only as explicit compatibility/test helper. Normal generated path uses `finish_work` descriptor.

## Test gate

Fake transport asserts:

- input instructions present;
- destination directory exists;
- copied input payload exists;
- output schema matches output type;
- tool name is `finish_work`;
- tool schema equals output schema;
- output metadata is fresh;
- prompt contains directory restriction;
- existing generated flows still lower.

## Done when

Generated submit prepares all data without opening Codex or resuming flow inline.
