{.experimental: "callOperator".}

import std/[macros, os, paths, strutils]
import vecherinka

type
  InspectInput = object
    evidence: Location
    target: string

  InspectOutput = object
    report: Location
    summary: string

  Prepared = object
    report_path: string
    summary: string

const prompts = AgentPromptTemplates(
  developer_instructions: checked_prompt(
    "Inspect only supplied evidence. Call finish_work exactly once. Never narrate."),
  goal: checked_prompt(
    "Write reflection.md in working directory. Return reflection.md."),
  turn_prompt: checked_prompt(
    "$task\nRead evidence directory and identify concrete inefficiencies in generated orchestration or simulator. Write reflection.md with categories, evidence filenames, wasted budget, and one targeted mutation. Return report=reflection.md and summary. Target and evidence are in input.$input\nWorking directory: $working_dir\nRuntime directory: $runtime_dir",
    "task", "input", "working_dir", "runtime_dir"),
  finish_work_description: checked_prompt(
    "Submit reflection Location and summary. Call exactly once."))
const pool_weights = [
  (name: "default", weight: 0.25),
  (name: "audit", weight: 0.75)]

expandMacros: vecherinka(inspect, pools = pool_weights):
  > inspect_files InspectInput ~> InspectOutput:
    luna.medium[InspectInput, InspectOutput](
      "Inspect evidence directory. Write reflection.md with one mutation.")
  > prepare InspectOutput ~> Prepared:
    so(InspectOutput, Prepared, input, working_dir) do:
      let path = working_dir / Path(cast[string](input.report))
      if not fileExists($path):
        raise newException(IOError, "inspector did not create reflection.md")
      pure(Prepared(report_path: $path, summary: input.summary))
  > entry InspectInput ~> Prepared {.entry.}:
    inspect_files >>> prepare

let args = commandLineParams()
if args.len < 2:
  quit("usage: inspector evidence-dir target")
let output = inspect(InspectInput(evidence: Location(args[0]), target: args[1]),
  10.0, prompts)
writeFile("inspector-output.txt", output.report_path & "\n" & output.summary & "\n")
echo "report-path: ", output.report_path
