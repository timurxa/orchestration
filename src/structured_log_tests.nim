import std/[json, os, strutils, unittest]
import structured_log

suite "structured logger":
  test "emits ordered JSONL records":
    var lines: seq[string] = @[]
    let logger = new_structured_logger(
      proc(line: string) = lines.add(line),
      "run-1",
      ring_capacity = 2)

    check logger.emit("run.start", "vecherinka") == 1
    check logger.emit(
      "model.submit",
      "vecherinka",
      log_fields(("request_id", %"i:0"))) == 2
    check lines.len == 2
    check parseJson(lines[0])["seq"].getInt == 1
    check parseJson(lines[1])["fields"]["request_id"].getStr == "i:0"

  test "ring keeps newest records in order":
    let logger = new_structured_logger(ring_capacity = 2)
    discard logger.emit("one", "test")
    discard logger.emit("two", "test")
    discard logger.emit("three", "test")
    let records = logger.recent_events()
    check records.len == 2
    check parseJson(records[0])["event"].getStr == "two"
    check parseJson(records[1])["event"].getStr == "three"

  test "large fields produce bounded valid JSON":
    var lines: seq[string] = @[]
    let logger = new_structured_logger(
      proc(line: string) = lines.add(line),
      max_event_bytes = 256)
    discard logger.emit("large", "test", log_fields(("text", %("x".repeat(1000)))) )
    check lines.len == 1
    check parseJson(lines[0])["truncated"].getBool
    check lines[0].len <= 256

  test "long envelope identities remain bounded":
    var lines: seq[string] = @[]
    let logger = new_structured_logger(
      proc(line: string) = lines.add(line),
      "r".repeat(1000),
      max_event_bytes = 256)
    discard logger.emit("e".repeat(1000), "c".repeat(1000))
    check lines[0].len <= 256
    check parseJson(lines[0])["truncated"].getBool

  test "sink failure does not raise":
    var calls = 0
    let logger = new_structured_logger(
      proc(line: string) =
        inc calls
        raise newException(IOError, "closed"),
      ring_capacity = 2)
    discard logger.emit("one", "test")
    discard logger.emit("two", "test")
    check calls == 1
    check logger.recent_events().len == 2

  test "file sink writes and closes":
    let path = getTempDir() / "structured-log-test.jsonl"
    let file_sink = new_log_file_sink(path)
    let logger = new_structured_logger(file_sink.sink, "run-file")
    discard logger.emit("run.start", "test")
    file_sink.close()
    check readFile(path).contains("run.start")
    removeFile(path)
