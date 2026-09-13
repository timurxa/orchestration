# Slice 4 — output schema and decoder

## Purpose

Turn model output JSON into typed domain values, then generated artifact payloads.

## Status

Partial. Compile-time schema generation exists for debug output, but parsing
and typed decoding do not.

## Files

- `src/vecherinka_comptime.nim`
- `src/vecherinka_runtime.nim` for decoder result types
- output decoder tests

## Work

1. Generate `output_schema(B)` from actual output type.
2. Use discriminator-aware schema for tagged output variants.
3. Replace debug/default output materializer with generated decoder.
4. Parse `LlmOutput.arguments` using `output_contract.tryParse`.
5. Pack parsed value into expected generated artifact branch.
6. Return explicit success/error result.
7. Reject unexpected output kind or wrong tool name.

Decoder must never use `default(A)` for failure. `Option[A]` represents absent decoded value.

## Test gate

- valid scalar parses;
- wrong scalar rejects;
- missing required field rejects;
- wrong discriminator rejects;
- valid variant selects correct branch;
- sequence and option output locations decode as typed values;
- ordinary string path-like text remains literal;
- valid value packs into expected artifact kind;
- malformed output never reaches continuation.

## Done when

Decoder can be tested without Codex process or scheduler.
