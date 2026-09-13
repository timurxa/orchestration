# Slice 4 — output schema, location contract, decoder

## Purpose

Turn model output JSON into validated typed domain values, then generated artifact payloads.

## Files

- `src/vecherinka_comptime.nim`
- `src/vecherinka_runtime.nim` for decoder result types
- output decoder tests

## Work

1. Generate `output_schema(B)` from actual output type.
2. Use discriminator-aware schema for tagged output variants.
3. Generate `location_contract(B)` listing nested paths and conditions.
4. Generate `verify_locations(value, artifact_dir)` using safe path helpers.
5. Replace debug/default output materializer with generated decoder.
6. Parse `LlmOutput.arguments` using `output_contract.tryParse`.
7. Verify every active `Location`.
8. Pack parsed value into expected generated artifact branch.
9. Return explicit success/error result.
10. Reject unexpected output kind or wrong tool name.

Decoder must never use `default(A)` for failure. `Option[A]` represents absent decoded value.

## Test gate

- valid scalar parses;
- wrong scalar rejects;
- missing required field rejects;
- wrong discriminator rejects;
- valid variant selects correct branch;
- sequence and option output locations verified;
- missing output file rejects;
- output directory accepted;
- output traversal rejects;
- output absolute path rejects;
- output symlink escape rejects;
- ordinary string path-like text remains literal;
- valid value packs into expected artifact kind;
- malformed output never reaches continuation.

## Done when

Decoder can be tested without Codex process or scheduler.

