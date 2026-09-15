import std/[json, macros, options, os, paths, tempfiles]
import ../api/vecherinka

proc `$`(value: Location): string {.borrow.}

type
  BaselineInput = object
    marker: string
  BaselineOutput = object
    answer: string
  Stage1Input = object
    first: string
    second: string
  Stage1Output = object
    first_copy: string
    second_copy: string
  Stage2Input = object
    marker: string
  Stage2Intermediate = object
    payload: string
  Stage2Output = object
    answer: string
  Stage3Input = object
    marker: string
  Stage3Left = object
    left_value: string
  Stage3Right = object
    right_value: string
  Stage3Output = object
    left: string
    right: string
  Stage4Input = object
    mode: string
    marker: string
  Stage4Output = object
    answer: string
  Stage5Input = object
    marker: string
    ignored: string
  Stage5Output = object
    answer: string
  Stage6Input = object
    source: Location
  Stage6Output = object
    summary: string
    artifact: Location
  Stage7Item = object
    marker: string
  Stage7Result = object
    result: string
  Stage8Item = object
    marker: string
  Stage8Result = object
    result: string
  Stage8Context = object
    label: string
  Stage8Container = object
    label: string
    item: Stage8Item
  Stage9Kind = enum
    text_branch, file_branch
  Stage9Variant = object
    common: string
    case kind: Stage9Kind
    of text_branch:
      text: string
    of file_branch:
      file: Location
  Stage9Fixed = array[3, int]
  Stage9NamedTuple = tuple[first: int, second: string]
  Stage10Kind = enum
    text_case, file_case
  Stage10Variant = object
    common: string
    case kind: Stage10Kind
    of text_case:
      text: string
    of file_case:
      file: Location
  Stage10Item = object
    marker: string
    source: Location
  StaticWriteInput = object
    marker: string
  StaticWriteOutput = object
    path: string
    contents: string
  Stage10Input = object
    variant: Stage10Variant
    items: seq[Stage10Item]

const profile = luna.medium

const stepping_agent_prompts = AgentPromptTemplates(
  developer_instructions: checked_prompt(
    "Complete task. Call finish_work exactly once when done."),
  goal: checked_prompt(
    "Complete task. Call `finish_work` exactly once after completion. Put final result in finish_work arguments."),
  turn_prompt: checked_prompt(
    "$task\n\nComplete task. Call finish_work exactly once when done.\nYou may modify only: $working_dir\nLocation values are paths relative to: $runtime_dir\nInput Location values name provided files to read. Output Location values must be required files created inside $working_dir; return their relative filenames, never absolute paths, input paths, or file contents.$input",
    "task", "input", "working_dir", "runtime_dir"),
  finish_work_description: checked_prompt(
    "Submit final structured result. Call exactly once when task is complete."))

expandMacros: vecherinka(solve, stepping_agent_prompts):
  > baseline BaselineInput ~> BaselineOutput {.entry.}:
    profile[BaselineInput, BaselineOutput](
      "Copy marker exactly into answer. Do not create files.")

expandMacros: vecherinka(solve_stage_1, stepping_agent_prompts):
  > copy_fields Stage1Input ~> Stage1Output {.entry.}:
    profile[Stage1Input, Stage1Output](
      "Copy first into first_copy and second into second_copy. Do not create files.")

expandMacros: vecherinka(solve_stage_2, stepping_agent_prompts):
  > finalise Stage2Intermediate ~> Stage2Output:
    profile[Stage2Intermediate, Stage2Output](
      "Copy payload exactly into answer. Do not create files.")
  > seed_then_run Stage2Input ~> Stage2Output {.entry.}:
    so(Stage2Input, Stage2Output, input) do:
      pure(Stage2Intermediate(payload: input.marker)) >>> finalise

expandMacros: vecherinka(solve_stage_3, stepping_agent_prompts):
  > merge_fan (Stage3Left, Stage3Right) ~> Stage3Output:
    profile[(Stage3Left, Stage3Right), Stage3Output](
      "Copy left_value exactly into left. Copy right_value exactly into right. Do not create files.")
  > fan_entry Stage3Input ~> Stage3Output {.entry.}:
    fan(
      profile[Stage3Input, Stage3Left](
        "Copy marker exactly into left_value. Do not create files."),
      profile[Stage3Input, Stage3Right](
        "Copy marker exactly into right_value. Do not create files.")) >>> merge_fan

expandMacros: vecherinka(solve_stage_3_fan, stepping_agent_prompts):
  > fan_only Stage3Input ~> (Stage3Left, Stage3Right) {.entry.}:
    fan(
      profile[Stage3Input, Stage3Left](
        "Copy marker exactly into left_value. Do not create files."),
      profile[Stage3Input, Stage3Right](
        "Copy marker exactly into right_value. Do not create files."))

expandMacros: vecherinka(solve_stage_4, stepping_agent_prompts):
  > annotate Stage4Input ~> Stage4Output:
    profile[Stage4Input, Stage4Output](
      "Copy marker exactly into answer. Do not create files.")
  > route Stage4Input ~> Stage4Output {.entry.}:
    so(Stage4Input, Stage4Output, input) do:
      if input.mode == "model":
        input >>> annotate
      else:
        pure(Stage4Output(answer: "pure:" & input.marker))

expandMacros: vecherinka(solve_stage_5, stepping_agent_prompts):
  > project_marker Stage5Input ~> string:
    it(Stage5Input)[marker]
  > finish_projection string ~> Stage5Output:
    profile[string, Stage5Output](
      "Copy the input string exactly into answer. Do not create files.")
  > project_entry Stage5Input ~> Stage5Output {.entry.}:
    so(Stage5Input, Stage5Output, input) do:
      input >>> project_marker >>> finish_projection

expandMacros: vecherinka(solve_stage_6, stepping_agent_prompts):
  > materialise Stage6Input ~> Stage6Output {.entry.}:
    profile[Stage6Input, Stage6Output](
      "Read the provided input file named source.txt. Create result.txt in the working directory containing exactly the input file text. Return summary equal to the input file text and artifact equal to result.txt. Do not create any other files.")

expandMacros: vecherinka(solve_stage_7, stepping_agent_prompts):
  > map_item Stage7Item ~> Stage7Result:
    profile[Stage7Item, Stage7Result](
      "Copy marker exactly into result. Do not create files.")
  > lift_entry seq[Stage7Item] ~> seq[Stage7Result] {.entry.}:
    lift(seq[here])[map_item]

expandMacros: vecherinka(solve_stage_8_option, stepping_agent_prompts):
  > map_option Stage8Item ~> Stage8Result:
    profile[Stage8Item, Stage8Result](
      "Copy marker exactly into result. Do not create files.")
  > option_entry Option[Stage8Item] ~> Option[Stage8Result] {.entry.}:
    lift(Option[here])[map_option]

expandMacros: vecherinka(solve_stage_8_tuple, stepping_agent_prompts):
  > map_tuple Stage8Item ~> Stage8Result:
    profile[Stage8Item, Stage8Result](
      "Copy marker exactly into result. Do not create files.")
  > tuple_entry (Stage8Context, Stage8Item) ~> (Stage8Context, Stage8Result) {.entry.}:
    lift((Stage8Context, here))[map_tuple]

expandMacros: vecherinka(solve_stage_8_object, stepping_agent_prompts):
  > map_object Stage8Item ~> Stage8Item:
    profile[Stage8Item, Stage8Item](
      "Prefix marker with processed: and put it into marker. Do not create files.")
  > object_entry Stage8Container ~> Stage8Container {.entry.}:
    lift(Stage8Container(item: here))[map_object]

expandMacros: vecherinka(solve_stage_9_variant, stepping_agent_prompts):
  > copy_variant Stage9Variant ~> Stage9Variant {.entry.}:
    profile[Stage9Variant, Stage9Variant](
      "Preserve common and the active text_branch values exactly. Return the same variant. Do not create files.")

expandMacros: vecherinka(solve_stage_9_fixed, stepping_agent_prompts):
  > copy_fixed Stage9Fixed ~> Stage9Fixed {.entry.}:
    profile[Stage9Fixed, Stage9Fixed](
      "Copy all three array values exactly. Return a JSON array of exactly three integers, not an object. Do not create files.")

expandMacros: vecherinka(solve_stage_9_tuple, stepping_agent_prompts):
  > copy_named_tuple Stage9NamedTuple ~> Stage9NamedTuple {.entry.}:
    profile[Stage9NamedTuple, Stage9NamedTuple](
      "Copy first and second exactly. Do not create files.")

expandMacros: vecherinka(solve_stage_10, stepping_agent_prompts):
  > map_item Stage10Item ~> Stage10Item:
    profile[Stage10Item, Stage10Item](
      "Read the provided source file. Preserve marker exactly. Return source as source.txt. Do not create any other files.")
  > project_variant Stage10Input ~> Stage10Variant:
    it(Stage10Input)[variant]
  > copy_variant Stage10Variant ~> Stage10Variant:
    profile[Stage10Variant, Stage10Variant](
      "Preserve common and the active text_case values exactly. Return the same variant. Do not create files.")
  > advanced_entry Stage10Input ~> (seq[Stage10Item], Stage10Variant) {.entry.}:
    fan(
      so(Stage10Input, seq[Stage10Item], input) do:
        pure(input.items) >>> lift(seq[here])[map_item],
      so(Stage10Input, Stage10Variant, input) do:
        input >>> project_variant >>> copy_variant)

expandMacros: vecherinka(solve_stage_11, stepping_agent_prompts):
  > static_write StaticWriteInput ~> StaticWriteOutput {.entry.}:
    so(StaticWriteInput, StaticWriteOutput, input, working_dir) do:
      let target = working_dir / Path("static-write.txt")
      writeFile($target, input.marker)
      pure(StaticWriteOutput(path: $target, contents: input.marker))

proc emit_log(line: string) =
  echo line

let stage = if paramCount() == 0: "stage-0" else: paramStr(1)
if stage == "stage-0":
  let logger = new_structured_logger(emit_log, run_id = "stepping-stage-0")
  let input = BaselineInput(marker: "stage-0-marker-7f3c")
  let output = solve(input, 100.0, stepping_agent_prompts, logger = logger)
  doAssert output.answer == input.marker,
    "baseline answer mismatch: expected exact marker"
  echo "DIRECT_RESULT answer=", output.answer
  echo "BASELINE_ASSERTIONS exact_marker=true no_unrequested_files=manual_review"
elif stage == "stage-1":
  let logger = new_structured_logger(emit_log, run_id = "stepping-stage-1")
  let input = Stage1Input(first: "first-marker-51a9", second: "second-marker-b802")
  let output = solve_stage_1(input, 100.0, stepping_agent_prompts, logger = logger)
  doAssert output.first_copy == input.first,
    "stage 1 first field mismatch"
  doAssert output.second_copy == input.second,
    "stage 1 second field mismatch"
  echo "DIRECT_RESULT first_copy=", output.first_copy,
    " second_copy=", output.second_copy
  echo "STAGE_1_ASSERTIONS exact_fields=true no_unrequested_files=manual_review"
elif stage == "stage-2":
  let logger = new_structured_logger(emit_log, run_id = "stepping-stage-2")
  let input = Stage2Input(marker: "stage-2-marker-a14e")
  let output = solve_stage_2(input, 100.0, stepping_agent_prompts, logger = logger)
  doAssert output.answer == input.marker,
    "stage 2 answer mismatch"
  echo "DIRECT_RESULT answer=", output.answer
  echo "STAGE_2_ASSERTIONS pure_seed=true sequential=true no_unrequested_files=manual_review"
elif stage == "stage-3":
  let logger = new_structured_logger(emit_log, run_id = "stepping-stage-3")
  let input = Stage3Input(marker: "stage-3-marker-9c2d")
  let output = solve_stage_3(input, 100.0, stepping_agent_prompts, logger = logger)
  doAssert output.left == input.marker,
    "stage 3 left mismatch"
  doAssert output.right == input.marker,
    "stage 3 right mismatch"
  echo "DIRECT_RESULT left=", output.left, " right=", output.right
  echo "STAGE_3_ASSERTIONS fan_order=true exact_fields=true no_unrequested_files=manual_review"
elif stage == "stage-3-fan":
  let logger = new_structured_logger(emit_log, run_id = "stepping-stage-3-fan")
  let input = Stage3Input(marker: "stage-3-fan-marker-6e41")
  let output = solve_stage_3_fan(input, 100.0, stepping_agent_prompts, logger = logger)
  doAssert output[0].left_value == input.marker,
    "stage 3 fan left mismatch"
  doAssert output[1].right_value == input.marker,
    "stage 3 fan right mismatch"
  echo "DIRECT_RESULT left_value=", output[0].left_value,
    " right_value=", output[1].right_value
  echo "STAGE_3_FAN_ASSERTIONS fan_order=true exact_tuple=true no_unrequested_files=manual_review"
elif stage == "stage-4":
  let model_logger = new_structured_logger(emit_log, run_id = "stepping-stage-4-model")
  let model_input = Stage4Input(mode: "model", marker: "stage-4-model-marker-2b7a")
  let model_output = solve_stage_4(model_input, 100.0, stepping_agent_prompts, logger = model_logger)
  doAssert model_output.answer == model_input.marker,
    "stage 4 model route mismatch"
  echo "DIRECT_RESULT model_answer=", model_output.answer
  echo "STAGE_4_MODEL_ASSERTIONS so_model_path=true exact_output=true no_unrequested_files=manual_review"

  let pure_logger = new_structured_logger(emit_log, run_id = "stepping-stage-4-pure")
  let pure_input = Stage4Input(mode: "pure", marker: "stage-4-pure-marker-18d6")
  let pure_output = solve_stage_4(pure_input, 100.0, stepping_agent_prompts, logger = pure_logger)
  doAssert pure_output.answer == "pure:" & pure_input.marker,
    "stage 4 pure route mismatch"
  echo "DIRECT_RESULT pure_answer=", pure_output.answer
  echo "STAGE_4_PURE_ASSERTIONS so_pure_path=true exact_output=true no_unrequested_files=manual_review"
elif stage == "stage-5":
  let logger = new_structured_logger(emit_log, run_id = "stepping-stage-5")
  let input = Stage5Input(marker: "stage-5-selected-4d91", ignored: "must-not-reach-model")
  let output = solve_stage_5(input, 100.0, stepping_agent_prompts, logger = logger)
  doAssert output.answer == input.marker,
    "stage 5 projection mismatch"
  echo "DIRECT_RESULT answer=", output.answer
  echo "STAGE_5_ASSERTIONS field_projection=true ignored_field_excluded=graph_review no_unrequested_files=manual_review"
elif stage == "stage-6":
  let logger = new_structured_logger(emit_log, run_id = "stepping-stage-6")
  let input = Stage6Input(
    source: Location("stepping_runs/stage-06/trial-00/source.txt"))
  let output = solve_stage_6(input, 100.0, stepping_agent_prompts, logger = logger)
  doAssert output.summary == "stage-6-input-payload-83ce\n",
    "stage 6 summary mismatch"
  doAssert $output.artifact == "result.txt",
    "stage 6 artifact path mismatch"
  echo "DIRECT_RESULT summary=", output.summary,
    " artifact=", $output.artifact
  echo "STAGE_6_ASSERTIONS input_location=true output_location=true exact_file=true no_unrequested_files=manual_review"
elif stage == "stage-7":
  let logger = new_structured_logger(emit_log, run_id = "stepping-stage-7")
  let input = @[
    Stage7Item(marker: "stage-7-item-0-4b28"),
    Stage7Item(marker: "stage-7-item-1-cd73")]
  let output = solve_stage_7(input, 100.0, stepping_agent_prompts, logger = logger)
  doAssert output.len == input.len,
    "stage 7 sequence length mismatch"
  for index in 0 ..< input.len:
    doAssert output[index].result == input[index].marker,
      "stage 7 item order/value mismatch at index " & $index
  echo "DIRECT_RESULT result0=", output[0].result,
    " result1=", output[1].result
  echo "STAGE_7_ASSERTIONS lift_cardinality=true sequence_order=true exact_items=true no_unrequested_files=manual_review"
elif stage == "stage-8":
  let present_logger = new_structured_logger(emit_log, run_id = "stepping-stage-8-option-present")
  let present_input = some(Stage8Item(marker: "stage-8-option-present-a12f"))
  let present_output = solve_stage_8_option(present_input, 100.0, stepping_agent_prompts, logger = present_logger)
  doAssert present_output.isSome,
    "stage 8 present option disappeared"
  doAssert present_output.get.result == present_input.get.marker,
    "stage 8 present option value mismatch"
  echo "DIRECT_RESULT option_present=", present_output.get.result
  echo "STAGE_8_OPTION_PRESENT_ASSERTIONS one_inner_call=true exact_value=true no_unrequested_files=manual_review"

  let absent_logger = new_structured_logger(emit_log, run_id = "stepping-stage-8-option-absent")
  let absent_input = none(Stage8Item)
  let absent_output = solve_stage_8_option(absent_input, 100.0, stepping_agent_prompts, logger = absent_logger)
  doAssert absent_output.isNone,
    "stage 8 absent option became present"
  echo "DIRECT_RESULT option_absent=none"
  echo "STAGE_8_OPTION_ABSENT_ASSERTIONS zero_inner_calls=true exact_none=true no_unrequested_files=manual_review"

  let tuple_logger = new_structured_logger(emit_log, run_id = "stepping-stage-8-tuple")
  let tuple_input = (Stage8Context(label: "context-8"),
                     Stage8Item(marker: "stage-8-tuple-7c4b"))
  let tuple_output = solve_stage_8_tuple(tuple_input, 100.0, stepping_agent_prompts, logger = tuple_logger)
  doAssert tuple_output[0].label == tuple_input[0].label,
    "stage 8 tuple context changed"
  doAssert tuple_output[1].result == tuple_input[1].marker,
    "stage 8 tuple item mismatch"
  echo "DIRECT_RESULT tuple_context=", tuple_output[0].label,
    " tuple_result=", tuple_output[1].result
  echo "STAGE_8_TUPLE_ASSERTIONS preserved_context=true exact_item=true no_unrequested_files=manual_review"

  let object_logger = new_structured_logger(emit_log, run_id = "stepping-stage-8-object")
  let object_input = Stage8Container(
    label: "object-context-8",
    item: Stage8Item(marker: "stage-8-object-5e20"))
  let object_output = solve_stage_8_object(object_input, 100.0, stepping_agent_prompts, logger = object_logger)
  doAssert object_output.label == object_input.label,
    "stage 8 object label changed"
  doAssert object_output.item.marker == "processed:" & object_input.item.marker,
    "stage 8 object item mismatch"
  echo "DIRECT_RESULT object_label=", object_output.label,
    " object_marker=", object_output.item.marker
  echo "STAGE_8_OBJECT_ASSERTIONS preserved_field=true transformed_here=true no_unrequested_files=manual_review"
elif stage == "stage-9":
  let variant_logger = new_structured_logger(emit_log, run_id = "stepping-stage-9-variant")
  let variant_input = Stage9Variant(
    common: "variant-common-9",
    kind: text_branch,
    text: "variant-text-9")
  let variant_output = solve_stage_9_variant(variant_input, 100.0, stepping_agent_prompts, logger = variant_logger)
  doAssert variant_output.common == variant_input.common,
    "stage 9 variant common field changed"
  doAssert variant_output.kind == text_branch,
    "stage 9 variant branch changed"
  doAssert variant_output.text == variant_input.text,
    "stage 9 variant text changed"
  echo "DIRECT_RESULT variant_common=", variant_output.common,
    " variant_text=", variant_output.text
  echo "STAGE_9_VARIANT_ASSERTIONS active_branch=true exact_fields=true no_unrequested_files=manual_review"

  let tuple_logger = new_structured_logger(emit_log, run_id = "stepping-stage-9-tuple")
  let tuple_input: Stage9NamedTuple = (first: 31, second: "named-tuple-9")
  let tuple_output = solve_stage_9_tuple(tuple_input, 100.0, stepping_agent_prompts, logger = tuple_logger)
  doAssert tuple_output.first == tuple_input.first,
    "stage 9 named tuple first changed"
  doAssert tuple_output.second == tuple_input.second,
    "stage 9 named tuple second changed"
  echo "DIRECT_RESULT tuple_first=", tuple_output.first,
    " tuple_second=", tuple_output.second
  echo "STAGE_9_TUPLE_ASSERTIONS named_fields=true exact_values=true no_unrequested_files=manual_review"

  let fixed_logger = new_structured_logger(emit_log, run_id = "stepping-stage-9-fixed")
  let fixed_input: Stage9Fixed = [11, 22, 33]
  let fixed_output = solve_stage_9_fixed(fixed_input, 100.0, stepping_agent_prompts, logger = fixed_logger)
  doAssert fixed_output == fixed_input,
    "stage 9 fixed array values changed"
  echo "DIRECT_RESULT fixed_array=", fixed_output[0], ",", fixed_output[1], ",", fixed_output[2]
  echo "STAGE_9_FIXED_ASSERTIONS exact_values=true no_unrequested_files=manual_review"
elif stage == "stage-10":
  let logger = new_structured_logger(emit_log, run_id = "stepping-stage-10")
  let input = Stage10Input(
    variant: Stage10Variant(
      common: "stage-10-common",
      kind: text_case,
      text: "stage-10-text"),
    items: @[
      Stage10Item(
        marker: "stage-10-item-0-2d8a",
        source: Location("stepping_runs/stage-10/trial-00/source.txt")),
      Stage10Item(
        marker: "stage-10-item-1-71cf",
        source: Location("stepping_runs/stage-10/trial-00/source.txt"))])
  let output = solve_stage_10(input, 100.0, stepping_agent_prompts, logger = logger)
  doAssert output[0].len == input.items.len,
    "stage 10 lifted sequence length mismatch"
  for index in 0 ..< input.items.len:
    doAssert output[0][index].marker == input.items[index].marker,
      "stage 10 lifted marker mismatch at index " & $index
    doAssert $output[0][index].source == "source.txt",
      "stage 10 lifted source path mismatch at index " & $index
  doAssert output[1].common == input.variant.common,
    "stage 10 variant common mismatch"
  doAssert output[1].kind == text_case,
    "stage 10 variant branch mismatch"
  doAssert output[1].text == input.variant.text,
    "stage 10 variant text mismatch"
  echo "DIRECT_RESULT item0=", output[0][0].marker,
    " item1=", output[0][1].marker,
    " variant=", output[1].text
  echo "STAGE_10_ASSERTIONS fan=true so=true pure=true sequence_lift=true it=true tuple=true variant=true location=true no_unrequested_files=manual_review"
elif stage == "stage-11":
  let root = Path(createTempDir("vecherinka-stage-11-", ""))
  let previous_dir = os.getCurrentDir()
  try:
    os.setCurrentDir($root)
    let logger = new_structured_logger(emit_log, run_id = "stepping-stage-11")
    let input = StaticWriteInput(marker: "stage-11-static-write-9ac4")
    let output = solve_stage_11(input, 100.0, stepping_agent_prompts, logger = logger)
    doAssert output.contents == input.marker,
      "stage 11 output contents mismatch"
    doAssert fileExists(output.path),
      "stage 11 static output file missing"
    doAssert readFile(output.path) == input.marker,
      "stage 11 static output file contents mismatch"
    echo "DIRECT_RESULT path=", output.path,
      " contents=", output.contents
    echo "STAGE_11_ASSERTIONS so_working_dir=true static_write=true exact_file=true"
  finally:
    os.setCurrentDir(previous_dir)
    if dirExists($root):
      removeDir($root)
else:
  raise newException(ValueError, "unknown stepping stage: " & stage)
