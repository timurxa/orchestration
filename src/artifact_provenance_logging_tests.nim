import std/[json, paths, tables, tempfiles, unittest]
import vecherinka

proc committed_lineage(lines: seq[string]): Table[ArtifactID, seq[ArtifactID]] =
  result = initTable[ArtifactID, seq[ArtifactID]]()
  for line in lines:
    let event = parseJson(line)
    if event["event"].getStr != "artifact.commit":
      continue
    let fields = event["fields"]
    let artifact_id = ArtifactID(fields["artifact_id"].getInt)
    result[artifact_id] = @[]
    for predecessor in fields["predecessor_ids"]:
      result[artifact_id].add(ArtifactID(predecessor.getInt))

suite "artifact provenance logging":
  test "artifact text output uses a unique non-destructive filename":
    let root = Path(createTempDir("artifact-text-output-", ""))
    let first = write_artifact_text_file(
      root, model_input_materialization_filename, "first")
    let second = write_artifact_text_file(
      root, model_input_materialization_filename, "second")
    check first != second
    check readFile($first) == "first"
    check readFile($second) == "second"

  test "commit events reconstruct direct edges":
    let root = Path(createTempDir("artifact-provenance-log-", ""))
    var lines: seq[string] = @[]
    let logger = new_structured_logger(
      proc(line: string) = lines.add(line),
      "provenance-test")
    let context = new_runtime_context[int](run_dir = root, logger = logger)
    let root_id = register_artifact(context, 1, ArtifactMeta(
      id: 0, artifact_dir: root, predecessor_ids: @[]))
    let child_meta = reserve_artifact_meta(
      context,
      @[root_id, root_id],
      operation = "test-child",
      flow_kind = "fk_test",
      request_id = "i:7")
    let child_id = register_artifact(context, 2, child_meta)

    let lineage = committed_lineage(lines)
    check lineage[root_id] == (newSeq[ArtifactID]())
    check lineage[child_id] == @[root_id, root_id]
    for line in lines:
      let event = parseJson(line)
      if event["event"].getStr == "artifact.commit" and
          ArtifactID(event["fields"]["artifact_id"].getInt) == child_id:
        check event["fields"]["operation"].getStr == "test-child"
        check event["fields"]["flow_kind"].getStr == "fk_test"
        check event["fields"]["request_id"].getStr == "i:7"
