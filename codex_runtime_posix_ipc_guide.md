# POSIX IPC with the Codex runtime

This guide records the working shape of the old Codex app-server transport and
the rules to preserve when it is rebuilt.

## Where the implementation was

The relevant code was split across two files and was later removed by
`3b19b3a` (`remove unnecessary stuff`):

- `6a0b75c` (`init`) — `src/codex_runtime.nim` imported Nim's `posix` module,
  exposed `Process.outputHandle()` and `Process.errorHandle()`, and had an
  idempotent `close_process_streams` procedure.
- `f2ad7bc` (`feat: artifact management`) — `src/bezkonza_impl.nim` added the
  actual readers. `read_codex` used POSIX `poll`, `read`, and a stop pipe;
  `read_codex_output` and `read_codex_error` ran it concurrently for stdout and
  stderr.
- `d7c4acf` was the last version before deletion. It added an EOF event and
  startup-failure handling around the same reader design.

To inspect the historical sources:

```text
git show 6a0b75c:src/codex_runtime.nim
git show d7c4acf:src/bezkonza_impl.nim
```

`codex_runtime` owns the child process and protocol state. The surrounding
runtime owns transport scheduling: it reads descriptors and sends complete
lines to the protocol/state-machine owner.

## The IPC model

`codex app-server` has three relevant streams:

```text
parent                         child
------                         -----
stdin       ---------------->  JSON-RPC requests
stdout      <----------------  JSON-RPC responses/notifications (JSONL)
stderr      <----------------  diagnostics and startup errors
```

Keep stdout and stderr separate. Stdout is a machine-readable protocol; stderr
is not. Never parse stderr as JSON and never merge it into stdout.

The parent must drain both output pipes concurrently. Reading stdout first and
stderr afterward can deadlock: the child can block when the stderr pipe fills
while the parent is waiting for more stdout.

## Reader design

Use one reader thread per child output descriptor. A reader thread should do
only transport work:

1. Wait in `poll` on its child descriptor and a private shutdown descriptor.
2. Call POSIX `read` into a fixed-size byte buffer.
3. Append the bytes to a per-reader pending string.
4. Emit every complete newline-delimited frame to the central event channel.
5. Keep any final partial line for the next read.

The historical shape was:

```nim
var watched = [
  TPollfd(fd: childFd, events: POLLIN, revents: 0),
  TPollfd(fd: stopFd,  events: POLLIN, revents: 0)
]
var pending = ""

while true:
  let result = poll(addr watched[0], Tnfds(2), -1)
  # Retry EINTR; handle other poll errors.
  if stop_fd_is_ready(watched[1]):
    break

  if child_fd_is_readable(watched[0]):
    let count = read(childFd, addr buffer[0], buffer.len)
    if count == 0:
      # EOF: finish according to the framing policy, then exit.
      break
    if count > 0:
      pending.add(bytes_as_string(buffer, count))
      while pending contains '\n':
        let line = remove_through_newline(pending)
        events.send(AppEvent(kind: output_kind, message: line))
```

Important details:

- `read` returns bytes, not messages. A JSON object can be split across reads,
  and one read can contain several objects.
- Keep a separate `pending` buffer for stdout and stderr. A newline in one
  stream must never frame data from the other stream.
- Strip the newline before sending the event. Decide explicitly whether to
  accept `\r\n` and whether a non-empty unterminated final line is valid.
- Retry `poll`/`read` when interrupted by `EINTR`. If descriptors are made
  nonblocking, also handle `EAGAIN`/`EWOULDBLOCK`.
- Inspect `revents` rather than treating every nonzero value as ordinary data.
  `POLLIN` means data may be read; `POLLHUP` means drain remaining bytes and
  then expect EOF; `POLLERR` and `POLLNVAL` are transport failures.
- A single stream reaching EOF does not necessarily mean the whole child has
  exited. Track stdout and stderr closure separately and confirm process exit
  before publishing one `codex_stopped` event.

The old reader copied each positive `read` result into a Nim string and split
on `\n`. That is the essential framing technique to retain.

## Stop and shutdown

A blocking `poll(..., -1)` cannot be stopped by setting a Boolean in another
thread. Use a POSIX pipe (or another pollable wakeup descriptor):

```text
stop_pipe[0]  -- both reader threads poll this read end
stop_pipe[1]  -- coordinator writes one byte to wake them
```

The coordinator should shut down in this order:

1. Publish the stop request or write a byte to the stop pipe.
2. Join the stdout and stderr reader threads.
3. If the child is still running, terminate it, then `waitForExit` with a
   bounded timeout.
4. Close the child descriptors exactly once.
5. Call `Process.close` and release the runtime state.
6. Close both ends of the stop pipe after no reader can use them.

The historical `codex_runtime` guarded raw descriptor closure with
`handles_closed`, compared the two handles before closing them, and performed
the raw POSIX close before `Process.close`. Preserve the ownership rule, but
verify it against the Nim version in use: two owners closing the same OS fd can
cause double-close or, worse, close a newly reused descriptor. Pick one clear
owner for each descriptor and make cleanup idempotent.

Do not join a reader while its stop descriptor is still inaccessible, and do
not close a descriptor while a reader thread may still be inside `poll` or
`read`.

## Separation of responsibilities

The event/channel coordinator should be the only place that:

- parses stdout JSON;
- calls `accept_json` and mutates `CodexRuntime` protocol state;
- converts stderr into diagnostics;
- decides whether startup failed, the child exited unexpectedly, or work
  completed normally.

Reader threads should not parse JSON or mutate agent/request tables. This keeps
the non-thread-safe protocol state in one owner and makes ordering observable:
transport events arrive in the same channel, while stdout/stderr identity is
preserved in the event kind.

## Failure cases to test

- One JSON message split at every possible byte boundary.
- Several JSON messages in one `read`.
- Large continuous stderr while stdout is active.
- Child writes stderr and exits before producing stdout.
- Child closes stdout while stderr remains open.
- `poll` or `read` interrupted by `EINTR`.
- Stop requested while both readers are blocked in `poll`.
- EOF with a partial final line.
- Repeated shutdown/deinitialization.
- Raw descriptor numbers that happen to be equal or are already closed.

The central invariant is: drain both pipes without blocking the other, frame
each stream independently, serialize protocol handling through one owner, and
make wakeup, join, process wait, and descriptor cleanup explicit.
