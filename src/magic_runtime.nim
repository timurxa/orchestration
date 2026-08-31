import std/[strutils, os, posix, sugar, tables]
import json
import codex_runtime
import magic_api

type RuntimeArgs[P, R] = object
  problem: P
  solver: P -> Contextual[Start, R]
  outcome: ptr Outcome[R]

proc read_codex(
  context: ptr Context;
  fd: cint;
  event_kind: static AppEventKind;
  stop_prefix: string
) {.gcsafe.} =
  static: doAssert event_kind == codex_output or event_kind == codex_error
  
  var watched = [
    TPollfd(fd: fd, events: POLLIN, revents: 0),
    TPollfd(fd: context.reader_state.stop_fd, events: POLLIN, revents: 0)
  ]
  var pending = ""

  while true:
    if poll(addr watched[0], Tnfds(2), -1) < 0:
      break

    if watched[1].revents != 0:
      break

    if watched[0].revents != 0:
      var buffer: array[4096, char]
      let count = read(fd, addr buffer[0], buffer.len)
      if count <= 0:
        break
      let s = newString(count)
      copyMem(addr s[0], addr buffer[0], count)
      pending.add(s)
      while true:
        let newline = pending.find('\n')
        if newline < 0:
          break
        let message = pending[0 ..< newline]
        pending.delete(0 .. newline)
        context.global[].send(AppEvent(
          kind: event_kind,
          message: message
        ))

proc read_codex_output(context: ptr Context) {.thread, gcsafe.} =
  read_codex(context, context.reader_state.output_fd, codex_output, "reader")

proc read_codex_error(context: ptr Context) {.thread, gcsafe.} =
  read_codex(context, context.reader_state.error_fd, codex_error, "error reader")

proc runtime[P, R](
  args: RuntimeArgs[P, R]
) {.thread.} =
  let problem = args.problem
  let solver = args.solver
  let outcome = args.outcome

  var context = Context()
  doAssert pipe(context.stop_pipe) == 0
  context.runtime = init_codex_runtime(getCurrentDir())
  context.reader_state = ReaderState(
    output_fd: context.runtime.output_handle(),
    error_fd: context.runtime.error_handle(),
    stop_fd: context.stop_pipe[0]
  )
  var global: Channel[AppEvent]
  global.open()
  context.global = addr global
  var reader_thread: Thread[ptr Context]
  reader_thread.createThread(read_codex_output, addr context)
  var error_thread: Thread[ptr Context]
  error_thread.createThread(read_codex_error, addr context)

  context.global[].send(AppEvent(
    kind: runtime_work,
    work: proc () {.gcsafe.} =
      {.cast(gcsafe).}:
        solver(problem)(addr context)(Start(), proc (local_outcome: Outcome[R]) =
          outcome[] = local_outcome
          context.global[].send(AppEvent(kind: terminate)))))

  while true:
    let msg = context.global[].recv()
    case msg.kind:
    of runtime_work: msg.work()
    of on_agent_creation: context.pending_on_agent_creation_triggers.add(msg.trigger)
    of codex_output:
      discard context.runtime.accept_json(parseJson(msg.message))
      for i in countdown(context.pending_on_agent_creation_triggers.len - 1, 0):
        let agent_id = context.pending_on_agent_creation_triggers[i].agent_id
        if context.runtime.agents[agent_id].thread_id.has_value:
          context.pending_on_agent_creation_triggers[i].then()
          context.pending_on_agent_creation_triggers.del(i)
    of codex_error:
      echo msg.message
    of terminate:
      var signal = 'x'
      discard write(context.stop_pipe[1], addr signal, 1)

      break

  reader_thread.joinThread()
  error_thread.joinThread()

  context.global[].close()

  discard close(context.stop_pipe[0])
  discard close(context.stop_pipe[1])

  context.runtime.deinit_codex_runtime()

proc start*[P, R](
  problem: P;
  solver: P -> Contextual[Start, R];
  consumer: Consumer[R]
) =
  var runtime_thread: Thread[RuntimeArgs[P, R]]
  var outcome: Outcome[R]

  runtime_thread.createThread(runtime, RuntimeArgs[P, R](
    problem: problem,
    solver: solver,
    outcome: addr outcome
  ))
  runtime_thread.joinThread()

  consumer(outcome)
