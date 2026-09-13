import std/[os, posix, times, tables]
import vecherinka

let context = new_runtime_context[string]()
open_global_events(context)

proc wait_for_events(expected: int): seq[GlobalEvent] =
  let deadline = epochTime() + 5.0
  while result.len < expected and epochTime() < deadline:
    let received = try_recv_global_event(context)
    if received.data_available:
      result.add(received.event)
    else:
      sleep(1)
  doAssert result.len == expected

var output_pipe: array[0..1, cint]
var error_pipe: array[0..1, cint]
doAssert pipe(output_pipe) == 0
doAssert pipe(error_pipe) == 0

var readers: CodexReaders
start_codex_readers(readers, context, output_pipe[0], error_pipe[0])

var output_first = "{\"id\":1}\n{\"id\":2"
discard write(output_pipe[1], addr output_first[0], output_first.len)
var output_second = "}\r\nfinal partial"
discard write(output_pipe[1], addr output_second[0], output_second.len)
var error_data = "diagnostic one\ndiagnostic two\n"
discard write(error_pipe[1], addr error_data[0], error_data.len)
discard close(output_pipe[1])
discard close(error_pipe[1])
var events = wait_for_events(7)
stop_codex_readers(readers)
var messages = initTable[GlobalEventKind, seq[string]]()
for event in events:
  messages.mgetOrPut(event.kind, @[]).add(event.message)

doAssert messages[gek_stdout_line] == @["{\"id\":1}", "{\"id\":2}", "final partial"]
doAssert messages[gek_stderr_line] == @["diagnostic one", "diagnostic two"]
doAssert messages[gek_stdout_closed].len == 1
doAssert messages[gek_stderr_closed].len == 1

var messenger = new_global_event_messenger()
send_global_event(context, GlobalEvent(kind: gek_stdout_closed))
send_global_event(context, GlobalEvent(kind: gek_stderr_closed))
messenger.handle_global_event(nil, recv_global_event(context))
messenger.handle_global_event(nil, recv_global_event(context))
doAssert messenger.stdout_closed
doAssert messenger.stderr_closed
send_global_event(context, GlobalEvent(kind: gek_process_exit))
messenger.handle_global_event(nil, recv_global_event(context))
doAssert messenger.process_exited

var blocked_output_pipe: array[0..1, cint]
var blocked_error_pipe: array[0..1, cint]
doAssert pipe(blocked_output_pipe) == 0
doAssert pipe(blocked_error_pipe) == 0
var blocked_readers: CodexReaders
start_codex_readers(
  blocked_readers,
  context,
  blocked_output_pipe[0],
  blocked_error_pipe[0])
sleep(10)
stop_codex_readers(blocked_readers)
discard close(blocked_output_pipe[0])
discard close(blocked_output_pipe[1])
discard close(blocked_error_pipe[0])
discard close(blocked_error_pipe[1])
doAssert not try_recv_global_event(context).data_available

close_global_events(context)

echo "vecherinka runtime IPC: PASS"
