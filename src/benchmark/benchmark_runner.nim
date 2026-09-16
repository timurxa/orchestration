import std/[algorithm, os, osproc, paths, strutils, times]
import ./rigidbody_benchmark

type
  BenchmarkReport* = object
    seed*: uint64
    valid*: bool
    stability*: float64
    median_ms*: float64
    p95_ms*: float64
    message*: string
    checksums*: seq[string]

proc require_gtimeout(): string =
  result = findExe("gtimeout")
  if result.len == 0:
    raise newException(IOError,
      "gtimeout required; install Homebrew coreutils before running generated executables")

proc timed_command(executable, work_dir, output: string; seed: uint64): string =
  let gtimeout = require_gtimeout()
  "cd " & quoteShell(work_dir) & " && " & quoteShell(gtimeout) &
    " --signal=TERM --kill-after=5s 60s " & quoteShell(executable) &
    " --seed " & $seed & " --output " & quoteShell(output)

proc probe_command(executable, work_dir, output: string; velocity: float64): string =
  let gtimeout = require_gtimeout()
  "cd " & quoteShell(work_dir) & " && " & quoteShell(gtimeout) &
    " --signal=TERM --kill-after=5s 60s " & quoteShell(executable) &
    " --seed 1 --probe-velocity " & $velocity & " --output " & quoteShell(output)

proc run_once(executable, work_dir, output: string; seed: uint64):
    tuple[elapsed_ms: float64, result: SimulationResult] =
  let started = epochTime()
  let (output_text, exit_code) = execCmdEx(timed_command(
    executable, work_dir, output, seed))
  result.elapsed_ms = (epochTime() - started) * 1000.0
  if exit_code != 0:
    raise newException(IOError,
      "candidate failed (" & $exit_code & "): " & output_text)
  result.result = read_result(output)

proc median(values: seq[float64]): float64 =
  var ordered = values
  ordered.sort()
  if ordered.len == 0:
    return 0.0
  if ordered.len mod 2 == 1:
    ordered[ordered.len div 2]
  else:
    (ordered[ordered.len div 2 - 1] + ordered[ordered.len div 2]) / 2.0

proc benchmark_candidate*(executable: string; seed: uint64;
    work_dir: string): BenchmarkReport =
  let scene = make_scene(seed)
  createDir(work_dir)
  var timings: seq[float64] = @[]
  var checksums: seq[string] = @[]
  var first: SimulationResult
  try:
    let warm = run_once(executable, work_dir, work_dir / "warmup.json", seed)
    first = warm.result
    let warm_report = validate_result(scene, first)
    if not warm_report.valid:
      result.message = "warmup rejected: " & warm_report.message
      return
    let probe_velocities = [
      0.55 + float64(seed mod 37'u64) / 100.0,
      1.05 + float64(seed mod 43'u64) / 100.0]
    for velocity in probe_velocities:
      let probe_path = work_dir / ("friction-" & $velocity & ".json")
      let (probe_output, probe_code) = execCmdEx(probe_command(
        executable, work_dir, probe_path, velocity))
      if probe_code != 0:
        result.message = "friction probe failed: " & probe_output
        return
      let probe = read_result(probe_path)
      let expected = friction_distance_for_velocity(velocity)
      if abs(probe.friction_distance - expected) / expected > 0.05:
        result.message = "friction calibration failed"
        return
    for repetition in 0 ..< 3:
      let measured = run_once(executable, work_dir,
        work_dir / ("result-" & $repetition & ".json"), seed)
      let report = validate_result(scene, measured.result)
      if not report.valid:
        result.message = "timed run rejected: " & report.message
        return
      timings.add(measured.elapsed_ms)
      checksums.add(measured.result.checksum)
    result.seed = seed
    result.valid = checksums.len == 3 and checksums[0] == checksums[1] and
      checksums[1] == checksums[2]
    result.stability = validate_result(scene, first).stability
    result.median_ms = median(timings)
    result.p95_ms = timings.max
    result.checksums = checksums
    result.message = if result.valid: "ok" else: "deterministic replay mismatch"
  except CatchableError as error:
    result.seed = seed
    result.message = error.msg

proc report_json*(report: BenchmarkReport): string =
  "{\"seed\":" & $report.seed & ",\"valid\":" & $report.valid &
    ",\"stability\":" & $report.stability & ",\"median_ms\":" &
    $report.median_ms & ",\"p95_ms\":" & $report.p95_ms &
    ",\"message\":\"" & report.message.replace("\"", "'") & "\"}"
