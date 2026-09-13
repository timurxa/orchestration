# Slice 9 — failure lifecycle and cleanup

## Purpose

Prevent hangs, duplicate completion, leaked pending work, or unsafe partial artifacts.

## Status

Partial. Reader shutdown, runtime cleanup, stale completion checks, and join
duplicate checks exist. Artifact, turn, `finish_work`, and pending-work
failure coverage remains.

## Files

- `src/vecherinka_runtime.nim`
- `src/codex_runtime.nim`
- lifecycle tests

## Work

Handle distinctly:

- input materialization failure;
- agent creation failure;
- thread-start failure;
- turn-start failure;
- invalid schema output;
- input materialization/copy failure;
- duplicate `finish_work`;
- turn failure;
- interrupted turn;
- process exit before completion;
- missing completion after normal turn end;
- reader failure;
- shutdown while model pending.

Rules:

- mark model node failed exactly once;
- remove pending records on terminal failure;
- preserve retry opportunity for rejected tool call;
- never deliver malformed artifact;
- stop/join readers before closing channels/descriptors;
- clean fresh destination root on pre-agent materialization failure where safe;
- retain successful roots for inspection;
- make cleanup idempotent.

## Test gate

- each failure maps to expected node state;
- no pending model remains after terminal failure;
- invalid tool call does not terminate model prematurely;
- duplicate completion does not duplicate continuation;
- process shutdown does not deadlock readers;
- repeated runtime deinitialization safe;
- partial materialization cleanup safe;
- successful artifacts remain inspectable.
