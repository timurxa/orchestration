# Slice 5 — generated submit integration

## Purpose

Prepare artifact-aware LlmCallSpec with minimal compile-time change.

## Status

Partial. Materialization plumbing exists; output protocol remains debug-only.

## Work

Keep lower_model_call and generated Flow[A] data-only:

1. Runtime resolves input ArtifactID to ArtifactRecord[A].
2. Runtime invokes generated submit with input A and its metadata.
3. Generated code unpacks expected input branch.
4. Generated code invokes existing input materializer.
5. Generated code builds output schema and typed materializer.
6. Runtime reserves fresh output root/identity before submit.
7. Transport receives materialized input, output schema, working directory, and
   output materializer.
8. Successful output publication occurs later in central runtime handling.

LlmCallSpec may retain input_meta, runtime_dir, working_dir, and materialized
input as processing fields. It must not own or persist an ArtifactRecord.

Normal generated path uses finish_work descriptor. debug_tool_registry remains
an explicit compatibility/test helper only.

## Test gate

Fake transport asserts:

- resolved input A reaches materialization;
- destination exists and receives copied payloads;
- output schema matches output type;
- finish_work tool schema is correct;
- no table record appears before valid completion;
- valid completion publishes one output record;
- generated lowering remains record-free.
