# Slice 6 — `finish_work` event protocol

## Purpose

Connect dynamic tool calls to central validation and scheduler completion.

## Files

- `src/vecherinka_runtime.nim`
- `src/codex_runtime.nim`
- `src/codex_json.nim` only if response helper needs extension
- event/protocol tests

## Work

Generated callback captures only immutable per-call state and queues candidate event:

- model request ID;
- Codex tool request ID;
- tool name;
- call ID/thread ID/turn ID if required for diagnostics;
- copied JSON arguments;
- output kind;
- output metadata;
- generated materializer pointer.

Add event kind for candidate completion, or extend model artifact event with explicit candidate state.

Central handler pipeline:

1. Find pending model using scheduler ID.
2. Confirm tool name is `finish_work`.
3. Keep pending entry until validation succeeds.
4. Run generated schema parser.
5. Run generated location verifier.
6. On failure, call `accept_tool_response` with `success = false` and useful text. Keep model alive for retry.
7. On success, acknowledge server request.
8. Remove pending model.
9. Store typed output and output metadata in work node.
10. Deliver continuation.

Track per-call completion state. Second valid completion receives rejection or is ignored after safe acknowledgement policy; continuation runs once.

Add direct response helper accepting server request ID if current `ToolCallContext` cannot survive event copy.

## Test gate

- callback queues copied event;
- callback does not mutate `WorkPlan`;
- invalid schema receives negative response;
- invalid location receives negative response;
- rejected call remains retryable;
- valid call receives positive response;
- valid call reaches continuation once;
- duplicate completion cannot resume twice;
- scheduler ID and Codex request ID remain distinct;
- malformed event fails model cleanly;
- callback closure remains alive after generated submit returns.

## Done when

Fake dynamic tool call can complete a model node through the same event path as real Codex.

