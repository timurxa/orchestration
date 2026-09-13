# Slice 4 — output schema, decoder, and record publication

## Purpose

Decode model output into typed A, then publish one ArtifactRecord in the
RuntimeContext registry.

## Status

Partial. Compile-time schema generation exists; typed decoding and registry
publication do not.

## Work

1. Generate output_schema(B) from actual output type.
2. Use discriminator-aware schema for tagged output variants.
3. Parse LlmOutput.arguments with output_contract.tryParse.
4. Preserve current path-policy decision: Location instructions are
   prompt-owned; do not add a runtime Location verifier in this slice.
5. Pack parsed B into the generated Artifact branch A.
6. Register the resulting A with the pending model's reserved ArtifactMeta.
7. Return or enqueue only the new ArtifactID.
8. Reject unexpected output kind or wrong tool name.

Decoder must never use default(A) for failure. Invalid candidates publish no
record and leave pending model retry state intact.

## Test gate

- valid scalar, variant, sequence, option, and location outputs decode;
- wrong values, fields, discriminators, and tool names reject;
- successful decode creates exactly one table record;
- record key equals metadata ID;
- malformed output never reaches continuation;
- continuation receives the registered output ID and resolves expected A.
