{.experimental: "callOperator".}

import std/[json, options, paths, strutils]
import vecherinka
import codex_json

type
  VerificationOutput = object
    file*: Location
    files*: seq[Location]
    present*: Option[Location]
    absent*: Option[Location]

var observed = false

proc inspect_verification[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  let work = spec.working_dir
  writeFile($work / "result.txt", "result")
  createDir($work / "tree")

  let valid_arguments = %*{
    "file": "result.txt",
    "files": ["result.txt", "tree"],
    "present": "result.txt",
    "absent": nil
  }
  let valid = spec.materialize(spec.output_kind, LlmOutput(
    tool_name: "finish_work",
    arguments: valid_arguments,
    working_dir: work))
  doAssert valid.ok

  let missing_arguments = %*{
    "file": "missing.txt",
    "files": ["result.txt"],
    "present": nil,
    "absent": nil
  }
  let missing = spec.materialize(spec.output_kind, LlmOutput(
    tool_name: "finish_work",
    arguments: missing_arguments,
    working_dir: work))
  doAssert not missing.ok
  doAssert missing.error.contains("output.file")
  doAssert missing.error.contains("does not exist")

  let traversal_arguments = %*{
    "file": "../outside.txt",
    "files": [],
    "present": nil,
    "absent": nil
  }
  let traversal = spec.materialize(spec.output_kind, LlmOutput(
    tool_name: "finish_work",
    arguments: traversal_arguments,
    working_dir: work))
  doAssert not traversal.ok
  doAssert traversal.error.contains("outside working directory")

  observed = true
  enqueue_runtime_event(context, RuntimeEvent[A](
    kind: rev_model_artifact,
    request_id: request_id,
    output_kind: spec.output_kind,
    output: LlmOutput(
      tool_name: "finish_work",
      arguments: valid_arguments),
    materialize: spec.materialize,
    tool_request_id: none(RequestId),
    output_meta: none(ArtifactMeta)))

vecherinka(verify_generated_locations):
  > entry string ~> VerificationOutput {.entry.}:
    "verification-model".minimal[string, VerificationOutput]("prompt")

proc main() =
  verify_generated_locations("input", inspect_verification)
  doAssert observed

main()
