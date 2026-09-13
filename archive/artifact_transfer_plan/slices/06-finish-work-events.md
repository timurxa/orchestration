# Slice 6 — finish_work event protocol

## Purpose

Connect dynamic tool calls to central decoding, registry publication, and ID
based scheduler completion.

## Status

Not started.

## Work

Generated callback captures only per-call transport state and queues:

- model request ID;
- Codex tool request ID;
- tool name and diagnostic IDs;
- copied JSON arguments;
- output kind;
- pending output reservation identity;
- generated materializer pointer.

Callback does not capture or mutate WorkPlan, RuntimeContext table, or records.

Central handler:

1. Find pending model by scheduler request ID.
2. Confirm tool name finish_work.
3. Parse and semantically validate candidate.
4. On failure, negatively acknowledge and retain pending model for retry.
5. On success, acknowledge server request.
6. Materialize typed A.
7. Create and insert ArtifactRecord using reserved metadata.
8. Store output ArtifactID on WorkNode.
9. Remove pending model and deliver continuation ID.

Track per-call completion state. Duplicate completion cannot publish twice or
resume twice. Scheduler ID and Codex request ID remain distinct.

## Test gate

- callback queues copied event;
- no table or scheduler mutation occurs in callback;
- invalid candidate receives useful negative response;
- valid candidate creates one record and one continuation;
- duplicate completion is safely rejected or ignored;
- malformed event fails model cleanly;
- callback closure remains alive after generated submit returns.
