import std/[algorithm, json, os, osproc, paths, strutils, times]
import benchmark/rigidbody_benchmark
import benchmark/benchmark_runner
import api/vecherinka_provenance

type
  BVariant = object
    architecture: string
    intelligence: string
    profile: string

  CandidateRecord = object
    index: int
    variant: BVariant
    b_status: string
    solver_status: string
    valid: bool
    stability: float64
    median_ms: float64
    reflection: string

const
  project_root = currentSourcePath().splitFile.dir / ".."
  template_path = project_root / "src/metaoptimizer/b_candidate_template.nim.in"
  inspector_source = project_root / "src/metaoptimizer/inspector.nim"
  benchmark_source = project_root / "src/benchmark/rigidbody_benchmark.nim"
  runner_source = project_root / "src/benchmark/benchmark_runner.nim"
  baseline_source = project_root / "src/benchmark/baseline_solver.nim"
  api_source = project_root / "src/api"
  max_meta_budget = 500.0
  per_candidate_budget = 50.0
  max_candidates = 8

proc fail(message: string) {.noreturn.} =
  raise newException(IOError, message)

proc quote_path(path: string): string = quoteShell(path)

proc run_timed(command: string; seconds: int): tuple[output: string, code: int] =
  let gtimeout = findExe("gtimeout")
  if gtimeout.len == 0:
    fail("gtimeout required; install Homebrew coreutils")
  let wrapped = quoteShell(gtimeout) & " --signal=TERM --kill-after=5s " &
    $seconds & "s sh -c " & quoteShell(command)
  let (output, code) = execCmdEx(wrapped)
  (output: output, code: code)

proc emergency_abort(run_root: string) {.noreturn.} =
  discard run_timed("pkill -f 'codex app-server' >/dev/null 2>&1 || true", 15)
  discard run_timed("git reset --hard", 60)
  quit("runaway safety trigger; reset repository and killed Codex app-servers", 1)

proc safety_check(run_root: string) =
  let runs_root = splitFile(run_root).dir
  let count = run_timed("find " & quote_path(runs_root) &
    " -type f -print | wc -l", 15)
  let size = run_timed("du -sk " & quote_path(runs_root) & " | awk '{print $1}'", 15)
  if count.code != 0 or size.code != 0:
    fail("runaway safety check failed")
  let file_count = parseInt(count.output.strip)
  let kib = parseInt(size.output.strip.splitWhitespace[0])
  let processes = run_timed("ps -axo command | grep '[c]odex app-server' | wc -l", 15)
  if processes.code != 0:
    fail("process safety check failed")
  let process_count = parseInt(processes.output.strip)
  let children = run_timed("ps -axo command | grep -E '[n]im c|[o]rchestrator|[i]nspector' | wc -l", 15)
  if children.code != 0:
    fail("child process safety check failed")
  let child_count = parseInt(children.output.strip)
  if file_count > 100000 or kib > 1024 * 1024 or process_count > 8 or
      child_count > 32:
    raise newException(ValueError, "runaway candidate tree")

proc provenance_summary(candidate: string): string =
  for path in walkDirRec(candidate):
    if path.endsWith("vecherinka_provenance.sqlite3"):
      let reader = openProvenance(Path(path))
      try:
        let info = reader.runInfo()
        return "status=" & info.status & " commits=" & $info.last_commit_seq &
          " artifacts=" & $reader.artifacts().len
      finally:
        reader.close()
  "no nested provenance database"

proc source_mentions_friction(path: string): bool =
  if not fileExists(path):
    return false
  let source = readFile(path).toLowerAscii
  "friction" in source and "mu" in source

proc ensure_dir(path: string) =
  if not dirExists(path):
    createDir(path)

proc copy_tree(source, destination: string) =
  if dirExists(destination):
    removeDir(destination)
  copyDir(source, destination)

proc prepare_candidate(run_root: string; index: int; variant: BVariant;
    seed: uint64): string =
  result = run_root / "candidates" / ("b-" & align($index, 3, '0'))
  ensure_dir(run_root / "candidates")
  ensure_dir(result)
  copy_tree($api_source, result / "api")
  ensure_dir(result / "benchmark")
  copyFile($benchmark_source, result / "benchmark/rigidbody_benchmark.nim")
  copyFile($runner_source, result / "benchmark/benchmark_runner.nim")
  copyFile($baseline_source, result / "benchmark/baseline_solver.nim")
  let scene = make_scene(seed)
  write_scene(result / "task.json", scene)
  writeFile(result / "manifest.json", $ %*{
    "seed": seed,
    "scene_digest": scene_digest(scene),
    "architecture": variant.architecture,
    "intelligence": variant.intelligence,
    "profile": variant.profile,
    "b_budget": per_candidate_budget})
  var source = readFile($template_path)
  source = source.replace("__ARCHITECTURE__", variant.architecture)
  source = source.replace("__INTELLIGENCE__", variant.intelligence)
  source = source.replace("__PROFILE__", variant.profile)
  source = source.replace("__SEED__", $seed)
  writeFile(result / "orchestrator.nim", source)

proc compile_b(candidate: string): tuple[status: string, executable: string] =
  ensure_dir(candidate / "build")
  ensure_dir(candidate / "evidence")
  let command = "cd " & quote_path(candidate) & " && nim c --panics:on " &
    "--threads:on --hints:off --warnings:off --path:api --path:benchmark " &
    "-o:build/orchestrator orchestrator.nim"
  let compiled = run_timed(command, 90)
  if compiled.code != 0:
    writeFile(candidate / "evidence/b-compile.txt", compiled.output)
    return (status: "compile-failed", executable: "")
  (status: "compiled", executable: candidate / "build/orchestrator")

proc run_b(candidate, executable, state_dir: string): string =
  ensure_dir(candidate / "evidence")
  let command = "cd " & quote_path(candidate) & " && CODEX_HOME=" &
    quote_path(state_dir) & " CODEX_SQLITE_HOME=" & quote_path(state_dir) &
    " " & quote_path(executable)
  let ran = run_timed(command, 240)
  writeFile(candidate / "evidence/b-run.txt", ran.output)
  if ran.code != 0 or not fileExists(candidate / "b-output.txt") or
      not fileExists(candidate / "b-evaluation.json"):
    return "run-failed"
  let lines = readFile(candidate / "b-output.txt").splitLines
  if lines.len == 0 or lines[0].strip.len == 0:
    return "missing-solver"
  lines[0].strip

proc compile_a(candidate, source_path: string): tuple[status: string, executable: string] =
  let command = "cd " & quote_path(candidate) & " && nim c --panics:on " &
    "--threads:off --opt:speed --hints:off --warnings:off --path:benchmark " &
    "-o:build/simulator " & quote_path(source_path)
  let compiled = run_timed(command, 90)
  writeFile(candidate / "evidence/a-compile.txt", compiled.output)
  if compiled.code != 0:
    return (status: "compile-failed", executable: "")
  (status: "compiled", executable: candidate / "build/simulator")

proc write_fallback(candidate: string): string =
  result = candidate / "build/fallback_solver.nim"
  writeFile(result, readFile($baseline_source))

proc write_record(path: string; record: CandidateRecord) =
  let value = %*{
    "index": record.index,
    "architecture": record.variant.architecture,
    "intelligence": record.variant.intelligence,
    "profile": record.variant.profile,
    "b_status": record.b_status,
    "solver_status": record.solver_status,
    "valid": record.valid,
    "stability": record.stability,
    "median_ms": record.median_ms,
    "reflection": record.reflection}
  var file = open(path, fmAppend)
  defer: file.close()
  file.writeLine($value)

proc inspect_with_agent(run_root, candidate, inspector, state_dir: string): string =
  if inspector.len == 0:
    return "deterministic inspector fallback"
  let relative_evidence = relativePath(candidate / "evidence", run_root)
  let command = "cd " & quote_path(run_root) & " && CODEX_HOME=" &
    quote_path(state_dir) & " CODEX_SQLITE_HOME=" & quote_path(state_dir) &
    " " & quote_path(inspector) & " " & quote_path(relative_evidence) &
    " candidate-" & lastPathPart(candidate)
  let ran = run_timed(command, 180)
  writeFile(candidate / "evidence/inspector-run.txt", ran.output)
  let output_file = run_root / "inspector-output.txt"
  if ran.code != 0 or not fileExists(output_file):
    return "agent inspector unavailable; inspect compile, runtime, and score artifacts"
  let lines = readFile(output_file).splitLines
  if lines.len == 0:
    return "empty agent inspection"
  let report_path = lines[0].strip
  if fileExists(report_path):
    copyFile(report_path, candidate / "evidence/reflection.md")
  if lines.len > 1: lines[1] else: "agent reflection recorded"

proc build_inspector(run_root, state_dir: string): string =
  let workspace = run_root / "inspector"
  ensure_dir(workspace)
  copy_tree($api_source, workspace / "api")
  copyFile($inspector_source, workspace / "inspector.nim")
  let command = "cd " & quote_path(workspace) & " && nim c --panics:on " &
    "--threads:on --hints:off --warnings:off --path:api " &
    "-o:inspector inspector.nim"
  let built = run_timed(command, 90)
  writeFile(workspace / "compile.txt", built.output)
  if built.code == 0: workspace / "inspector" else: ""

proc benchmark_a(candidate, executable: string; seed: uint64): BenchmarkReport =
  benchmark_candidate(executable, seed, candidate / "evidence/benchmark")

proc better(record, incumbent: CandidateRecord): bool =
  if record.valid != incumbent.valid:
    return record.valid
  if not record.valid:
    return false
  if record.stability != incumbent.stability:
    return record.stability > incumbent.stability
  record.median_ms < incumbent.median_ms

proc variants(): seq[BVariant] =
  @[
    BVariant(architecture: "spatial_hash", intelligence: "breadth_first", profile: "luna.medium"),
    BVariant(architecture: "height_sweep", intelligence: "math_first", profile: "terra.medium"),
    BVariant(architecture: "constraint_batches", intelligence: "audit_first", profile: "sol.high"),
    BVariant(architecture: "event_driven", intelligence: "novel_algorithm", profile: "astra.high"),
    BVariant(architecture: "soa_warm_start", intelligence: "profiler_first", profile: "luna.high"),
    BVariant(architecture: "spatial_hash", intelligence: "reference_first", profile: "terra.high"),
    BVariant(architecture: "height_sweep", intelligence: "counterexample_first", profile: "sol.medium"),
    BVariant(architecture: "constraint_batches", intelligence: "minimal_prompt", profile: "luna.low"),
    BVariant(architecture: "event_driven", intelligence: "stagnation_escape", profile: "astra.medium"),
    BVariant(architecture: "soa_warm_start", intelligence: "final_audit", profile: "terra.high")]

proc mutate_variant(base: BVariant; previous: CandidateRecord;
    index: int): BVariant =
  result = base
  if previous.index >= 0:
    ## Reflection is a bounded learning signal. It changes both the solver
    ## architecture request and the model policy, so M searches more than
    ## prompt-only variants.
    let feedback = previous.reflection.toLowerAscii
    if not previous.valid or "repair" in feedback or "failed" in feedback:
      result.architecture = if index mod 2 == 0:
        "spatial_hash"
      else:
        "height_sweep"
      result.intelligence = "repair_first"
      result.profile = "terra.medium"
    elif "slow" in feedback or "runtime" in feedback or "profiler" in feedback:
      result.architecture = "soa_warm_start"
      result.intelligence = "profiler_first"
      result.profile = "luna.high"
    elif "algorithm" in feedback or "scaling" in feedback:
      result.architecture = "event_driven"
      result.intelligence = "scaling_counterexample"
      result.profile = "astra.high"
    else:
      result.architecture = if index mod 2 == 0:
        "constraint_batches"
      else:
        "height_sweep"
      result.intelligence = "audit_first"
      result.profile = "sol.high"

proc main() =
  let args = commandLineParams()
  var seed = 42'u64
  let dry_run = "--dry-run" in args
  if args.len >= 2 and args[0] == "--seed":
    seed = uint64(parseUInt(args[1]))
  let run_root = os.getCurrentDir() / "runs" / ("meta-" & $int(epochTime()))
  ensure_dir(os.getCurrentDir() / "runs")
  ensure_dir(run_root)
  ensure_dir(run_root / "final")
  let state_dir = os.getCurrentDir() / ".codex-task-state"
  if not dirExists(state_dir):
    fail("missing .codex-task-state")
  writeFile(run_root / "archive.jsonl", "")
  writeFile(run_root / "reflections.jsonl", "")
  let scene = make_scene(seed)
  write_scene(run_root / "scene.json", scene)
  writeFile(run_root / "contract.txt",
    "seed=" & $seed & "\ndigest=" & scene_digest(scene) &
    "\nsteps=" & $step_count & "\nbudget=" & $max_meta_budget &
    "\nper_candidate=" & $per_candidate_budget & "\n")

  let inspector = build_inspector(run_root, state_dir)
  var incumbent = CandidateRecord(index: -1, valid: false, median_ms: 1.0e300)
  let all_variants = variants()
  var previous = CandidateRecord(index: -1)
  var spent = 0.0
  var completed_candidates = 0
  const inspector_budget = 10.0
  for index in 0 ..< min(max_candidates, all_variants.len):
    if spent + per_candidate_budget + inspector_budget > max_meta_budget:
      break
    safety_check(run_root)
    let variant = mutate_variant(all_variants[index], previous, index)
    let candidate = prepare_candidate(run_root, index, variant, seed)
    if dry_run:
      echo "dry-run-candidate: ", candidate
      return
    let b_compile = compile_b(candidate)
    var record = CandidateRecord(index: index, variant: variant,
      b_status: b_compile.status, solver_status: "not-run",
      median_ms: 1.0e300, stability: 0.0, valid: false)
    var solver_source = ""
    var generated_valid = false
    if b_compile.status == "compiled":
      solver_source = run_b(candidate, b_compile.executable, state_dir)
    if solver_source.len == 0 or not fileExists(solver_source):
      solver_source = write_fallback(candidate)
      record.b_status = record.b_status & "+fallback"
    let a_compile = compile_a(candidate, solver_source)
    record.solver_status = a_compile.status
    if a_compile.status == "compiled":
      var report = benchmark_a(candidate, a_compile.executable, seed)
      generated_valid = report.valid
      if not report.valid:
        ## Keep recursive generation observable, but never promote invalid code.
        ## Baseline fallback preserves a usable run when model code misses contract.
        let fallback = write_fallback(candidate)
        let fallback_compile = compile_a(candidate, fallback)
        if fallback_compile.status == "compiled":
          let fallback_report = benchmark_a(candidate,
            fallback_compile.executable, seed)
          if fallback_report.valid:
            ## Fallback is diagnostic evidence only. It cannot turn a failed
            ## generated A into a promotable result.
            report = fallback_report
            solver_source = fallback
            record.solver_status = "compiled+fallback"
      record.valid = generated_valid and report.valid
      record.stability = report.stability
      record.median_ms = report.median_ms
      writeFile(candidate / "evidence/benchmark.json", report_json(report))
    record.reflection = inspect_with_agent(run_root, candidate, inspector, state_dir)
    if not fileExists(candidate / "evidence/reflection.md"):
      record.valid = false
      record.solver_status = record.solver_status & "+inspector-reject"
    let provenance = provenance_summary(candidate)
    record.reflection = record.reflection & "; provenance=" & provenance
    if provenance == "no nested provenance database":
      record.valid = false
      record.b_status = record.b_status & "+provenance-reject"
    if not source_mentions_friction(solver_source):
      record.valid = false
      record.solver_status = record.solver_status & "+friction-source-reject"
    ## Final promotion conjunction: no reflection artifact means no winner.
    if not fileExists(candidate / "evidence/reflection.md"):
      record.valid = false
      record.solver_status = record.solver_status & "+inspector-evidence-required"
    spent += per_candidate_budget + inspector_budget
    inc completed_candidates
    previous = record
    write_record(run_root / "archive.jsonl", record)
    var reflection_file = open(run_root / "reflections.jsonl", fmAppend)
    reflection_file.writeLine($ %*{
      "index": index, "reflection": record.reflection})
    reflection_file.close()
    if better(record, incumbent) and solver_source.len > 0:
      incumbent = record
      copyFile(solver_source, run_root / "final/best_solver.nim")
      writeFile(run_root / "final/best.json", $ %*{
        "index": index, "architecture": variant.architecture,
        "intelligence": variant.intelligence, "profile": variant.profile,
        "valid": record.valid, "stability": record.stability,
        "median_ms": record.median_ms})
    safety_check(run_root)

  writeFile(run_root / "final/status.txt",
    "meta_budget=" & $max_meta_budget & "\ncandidate_runs=" &
    $completed_candidates & "\nspent=" & $spent & "\nseed=" & $seed & "\n")
  if incumbent.index < 0:
    fail("no valid generated solver")
  echo "meta-run: ", run_root
  echo "best-valid: ", incumbent.valid
  echo "best-stability: ", incumbent.stability
  echo "best-median-ms: ", incumbent.median_ms

try:
  main()
except CatchableError as error:
  if error.msg == "runaway candidate tree":
    emergency_abort(os.getCurrentDir() / "runs")
  quit(error.msg, 1)
