## Small, opt-in JSONL logger for runtime diagnostics.
##
## Logger failures are deliberately non-fatal. Runtime code must not depend on
## logging being configured or healthy.

import std/[json, monotimes, os]

type
  LogSink* = proc(line: string)

  LogFileSink* = ref object
    file: File
    closed: bool

  StructuredLogger* = ref object
    sink*: LogSink
    run_id*: string
    enabled*: bool
    max_event_bytes*: int
    ring_capacity*: int
    next_seq: uint64
    ring_next: int
    ring: seq[string]

proc log_fields*(pairs: varargs[(string, JsonNode)]): JsonNode =
  ## Build nested event fields without exposing the logger's envelope keys.
  result = newJObject()
  for pair in pairs:
    result[pair[0]] = if pair[1].isNil: newJNull() else: pair[1]

proc new_log_file_sink*(path: string; append: bool = false): LogFileSink =
  ## One log file normally belongs to one run. Use append=true only when
  ## deliberately building a multi-run stream and filter it by run_id.
  new result
  result.file = open(path, if append: fmAppend else: fmWrite)
  result.closed = false

proc sink*(file_sink: LogFileSink): LogSink =
  proc write_log_line(line: string) =
    if file_sink.isNil or file_sink.closed:
      raise newException(IOError, "log file sink is closed")
    file_sink.file.writeLine(line)
    file_sink.file.flushFile()
  write_log_line

proc close*(file_sink: LogFileSink) =
  if file_sink.isNil or file_sink.closed:
    return
  file_sink.file.close()
  file_sink.closed = true

proc new_structured_logger*(sink: LogSink = nil; run_id: string = "";
    max_event_bytes: int = 4096; ring_capacity: int = 64): StructuredLogger =
  if max_event_bytes < 256:
    raise newException(ValueError, "max_event_bytes must be at least 256")
  if ring_capacity < 0:
    raise newException(ValueError, "ring_capacity cannot be negative")
  new result
  result.sink = sink
  result.run_id = if run_id.len == 0:
    "run-" & $getMonoTime().ticks
  else:
    run_id
  result.enabled = true
  result.max_event_bytes = max_event_bytes
  result.ring_capacity = ring_capacity
  result.next_seq = 0
  result.ring_next = 0
  result.ring = @[]

proc disable*(logger: StructuredLogger) =
  if not logger.isNil:
    logger.enabled = false

proc enable*(logger: StructuredLogger) =
  if not logger.isNil:
    logger.enabled = true

proc clipped(value: string; limit: int): string =
  if value.len <= limit:
    return value
  value[0 ..< limit - 3] & "..."

proc remember(logger: StructuredLogger; line: string) =
  if logger.ring_capacity == 0:
    return
  if logger.ring.len < logger.ring_capacity:
    logger.ring.add(line)
  else:
    logger.ring[logger.ring_next] = line
    logger.ring_next = (logger.ring_next + 1) mod logger.ring_capacity

proc bounded_line(logger: StructuredLogger; event, component: string;
    sequence: uint64; timestamp_ns: int64; fields: JsonNode): string =
  var envelope = newJObject()
  envelope["schema"] = %"vecherinka.log.v1"
  envelope["seq"] = %sequence
  envelope["timestamp_ns"] = %timestamp_ns
  envelope["run_id"] = %clipped(logger.run_id, 256)
  envelope["component"] = %clipped(component, 256)
  envelope["event"] = %clipped(event, 256)
  envelope["fields"] = if fields.isNil: newJObject() else: fields

  let full_line = $envelope
  if full_line.len <= logger.max_event_bytes:
    return full_line

  ## Keep valid JSON when payload exceeds the configured bound. Preserve
  ## correlation fields; omit payload instead of cutting serialized JSON.
  envelope["fields"] = newJObject()
  envelope["truncated"] = %true
  envelope["original_bytes"] = %full_line.len.int64
  let bounded = $envelope
  if bounded.len <= logger.max_event_bytes:
    return bounded

  ## Extremely small limits cannot retain every identity field. Keep a valid,
  ## compact correlation record rather than violating the byte bound.
  var compact = newJObject()
  compact["schema"] = %"vecherinka.log.v1"
  compact["seq"] = %sequence
  compact["timestamp_ns"] = %timestamp_ns
  compact["event"] = %clipped(event, 32)
  compact["truncated"] = %true
  compact["original_bytes"] = %full_line.len.int64
  $compact

proc emit*(logger: StructuredLogger; event, component: string;
    fields: JsonNode = nil): uint64 =
  if logger.isNil or not logger.enabled:
    return 0

  if logger.next_seq == high(uint64):
    logger.enabled = false
    return 0
  inc logger.next_seq
  result = logger.next_seq

  try:
    let line = bounded_line(
      logger,
      event,
      component,
      result,
      getMonoTime().ticks,
      fields)
    logger.remember(line)
    if not logger.sink.isNil:
      try:
        logger.sink(line)
      except CatchableError:
        ## Sink failure must never change runtime behavior. Keep ring logging.
        logger.sink = nil
  except CatchableError:
    ## Malformed optional fields must not turn diagnostics into a runtime fault.
    discard

proc recent_events*(logger: StructuredLogger): seq[string] =
  if logger.isNil or logger.ring.len == 0:
    return @[]
  if logger.ring.len < logger.ring_capacity:
    for line in logger.ring:
      result.add(line)
    return
  for offset in 0 ..< logger.ring.len:
    result.add(logger.ring[(logger.ring_next + offset) mod logger.ring.len])
