# Slice 9 — failure lifecycle and registry cleanup

## Purpose

Prevent hangs, duplicate completion, dangling IDs, leaked records, and unsafe
partial artifact roots.

## Status

Partial. Reader shutdown and some stale-completion checks exist; registry
failure coverage does not.

## Work

Handle distinctly:

- missing artifact ID;
- table key/metadata mismatch;
- input materialization failure;
- agent, thread, or turn failure;
- invalid schema or Location output;
- duplicate finish_work;
- interrupted turn;
- process exit before completion;
- missing completion;
- reader failure;
- shutdown while model pending.

Rules:

- mark model node failed exactly once;
- remove pending records on terminal failure;
- never enqueue an ID without a table record;
- invalid candidates never enter the table;
- rejected tool calls retain retry state;
- successful records and roots remain inspectable;
- reserved but unpublished output roots clean up safely on terminal failure;
- table and context cleanup are idempotent;
- readers stop and join before channels/descriptors close.

## Test gate

- each failure maps to expected node state;
- no dangling pending model or invalid artifact ID remains;
- invalid tool call does not terminate model prematurely;
- duplicate completion does not duplicate record or continuation;
- process shutdown does not deadlock readers;
- repeated runtime deinitialization is safe;
- partial materialization cleanup is safe;
- successful records remain available through RuntimeContext.artifacts.
