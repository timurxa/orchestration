{.experimental: "callOperator".}

import std/[json, options, os, paths, strutils, tempfiles]
import vecherinka
import codex_json

type
  Codebase = distinct Location

  NestedInput = object
    note*: string

  InputVariantKind = enum
    iv_text
    iv_file

  InputVariant = object
    case kind*: InputVariantKind
    of iv_text:
      text*: string
    of iv_file:
      file*: Location

  MaterializationInput = object
    goal*: string
    nested*: NestedInput
    branch*: InputVariant
    directory*: Location
    codebase*: Codebase
    files*: seq[Location]
    present*: Option[Location]
    absent*: Option[Location]
    literal_path*: string

proc `$`(value: MaterializationInput): string = value.goal

var observed_spec = false
var observed_materialized_input = ""
var observed_working_dir = Path("")

proc inspect_materialization[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  observed_spec = true
  observed_materialized_input = spec.materialized_input
  observed_working_dir = spec.working_dir
  doAssert dirExists($spec.working_dir)
  doAssert spec.materialized_input.contains("input.goal: string = fix parser")
  doAssert spec.materialized_input.contains("input.nested.note: string = nested")
  doAssert spec.materialized_input.contains("input.branch.file: location = ")
  doAssert not spec.materialized_input.contains("input.branch.text")
  doAssert spec.materialized_input.contains("input.files[1]: location = ")
  doAssert spec.materialized_input.contains("input.files[2]: location = ")
  doAssert spec.materialized_input.contains("input.absent: Option:none")
  doAssert spec.materialized_input.contains(
    "input.literal_path: string = repo/file.txt")

  doAssert fileExists($spec.working_dir / "payload.txt")
  doAssert dirExists($spec.working_dir / "tree")
  doAssert fileExists($spec.working_dir / "tree" / "child.txt")
  doAssert fileExists($spec.working_dir / "shared.txt")
  doAssert fileExists($spec.working_dir / "shared-1.txt")
  doAssert fileExists($spec.working_dir / "shared-2.txt")
  doAssert fileExists($spec.working_dir / "shared-3.txt")
  doAssert readFile($spec.working_dir / "shared.txt") == "one"
  doAssert readFile($spec.working_dir / "shared-1.txt") == "one"
  doAssert readFile($spec.working_dir / "shared-2.txt") == "two"

  let event = RuntimeEvent[A](
    kind: rev_model_artifact,
    request_id: request_id,
    output_kind: spec.output_kind,
    output: LlmOutput(
      tool_name: "finish_work",
      arguments: %*"generated"),
    materialize: spec.materialize,
    tool_request_id: none(RequestId),
    output_meta: none(ArtifactMeta))
  enqueue_runtime_event(context, event)

vecherinka(generated_materialize):
  > entry MaterializationInput ~> string {.entry.}:
    "materialize-model".minimal[MaterializationInput, string]("prompt")

proc expect_io_error(action: proc()) =
  var raised = false
  try:
    action()
  except IOError:
    raised = true
  doAssert raised

proc main() =
  let source_root = Path(expandFilename(os.getCurrentDir()))
  let fixture = Path(createTempDir("materialization-fixture-", "", $source_root))
  defer:
    removeDir($fixture)

  let fixture_name = splitFile(fixture).name
  let fixture_prefix = $fixture_name
  createDir($fixture / "one")
  createDir($fixture / "two")
  createDir($fixture / "tree")
  writeFile($fixture / "one" / "shared.txt", "one")
  writeFile($fixture / "two" / "shared.txt", "two")
  writeFile($fixture / "tree" / "child.txt", "tree")
  writeFile($fixture / "payload.txt", "payload")

  let input = MaterializationInput(
    goal: "fix parser",
    nested: NestedInput(note: "nested"),
    branch: InputVariant(
      kind: iv_file,
      file: Location(fixture_prefix / "payload.txt")),
    directory: Location(fixture_prefix / "tree"),
    codebase: Codebase(Location(fixture_prefix / "one" / "shared.txt")),
    files: @[
      Location(fixture_prefix / "one" / "shared.txt"),
      Location(fixture_prefix / "two" / "shared.txt")],
    present: some(Location(fixture_prefix / "one" / "shared.txt")),
    absent: none(Location),
    literal_path: "repo/file.txt")

  let generated_value = generated_materialize(input, inspect_materialization)
  doAssert generated_value == "generated"
  doAssert observed_spec
  doAssert observed_materialized_input.len > 0
  doAssert observed_working_dir != Path("")

  let destination_a = Path(createTempDir("materialization-destination-", ""))
  let destination_b = Path(createTempDir("materialization-destination-", ""))
  defer:
    removeDir($destination_a)
    removeDir($destination_b)
  var names_a: seq[string] = @[]
  var names_b: seq[string] = @[]
  let relative_file = fixture_prefix / "one" / "shared.txt"
  doAssert copy_location_payload(
    source_root, destination_a, relative_file, names_a) == "shared.txt"
  doAssert copy_location_payload(
    source_root, destination_b, relative_file, names_b) == "shared.txt"
  doAssert fileExists($destination_a / "shared.txt")
  doAssert fileExists($destination_b / "shared.txt")

  let outside_temp = createTempFile("materialization-outside-", ".txt")
  outside_temp.cfile.close()
  defer:
    removeFile(outside_temp.path)
  let outside_relative = relativePath(Path(outside_temp.path), source_root)
  expect_io_error(proc() =
    discard copy_location_payload(
      source_root, destination_a, $outside_relative, names_a))
  expect_io_error(proc() =
    discard copy_location_payload(
      source_root, fixture / Path("nested-destination"), $fixture_name, names_a))

  expect_io_error(proc() =
    discard copy_location_payload(
      source_root, destination_a, "../outside", names_a))
  expect_io_error(proc() =
    discard copy_location_payload(
      source_root, destination_a, "missing.txt", names_a))
  expect_io_error(proc() =
    discard copy_location_payload(
      source_root, destination_a, "", names_a))

  var missing_input = input
  missing_input.branch = InputVariant(
    kind: iv_file,
    file: Location(fixture_prefix / "missing.txt"))
  observed_spec = false
  var raised = false
  try:
    discard generated_materialize(missing_input, inspect_materialization)
  except ValueError:
    raised = true
  doAssert raised
  doAssert not observed_spec

main()
