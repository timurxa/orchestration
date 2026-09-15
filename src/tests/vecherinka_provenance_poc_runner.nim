{.experimental: "callOperator".}

import std/[options, os, osproc, paths, strutils, tempfiles]
import ../api/vecherinka
import ../api/vecherinka_provenance

type
  ChildRun = object
    database_path: string

  ProvenanceFacts = object
    database_path: string
    run_dir: string
    status: string
    last_commit_seq: int
    artifact_paths: seq[string]
    root_paths: seq[string]
    leaf_paths: seq[string]

  ProvenanceReport = object
    database_path: string
    run_dir: string
    status: string
    last_commit_seq: int
    artifact_count: int
    root_count: int
    leaf_count: int
    leaf_path: string
    leaf_predecessors: seq[string]
    valid: bool

proc fail(message: string) {.noreturn.} =
  raise newException(IOError, message)

proc source_paths(): tuple[source_root, child_source: Path] =
  let source_dir = Path(absolutePath(splitFile(currentSourcePath()).dir))
  result.source_root = Path(splitFile(splitFile($source_dir).dir).dir)
  result.child_source = source_dir / Path("vecherinka_provenance_poc_test.nim")

proc compile_child(source_root, child_source, child_workspace: Path): Path =
  let nim_executable = findExe("nim")
  if nim_executable.len == 0:
    fail("cannot find nim executable")

  let child_executable = child_workspace / Path("provenance-poc-child")
  let command = quoteShell(nim_executable) &
    " c --panics:on --threads:on --hints:off --warnings:off --path:" &
    quoteShell($source_root / "src" / "api") &
    " -o:" & quoteShell($child_executable) &
    " " & quoteShell($child_source)
  let (output, exit_code) = execCmdEx(command)
  if exit_code != 0:
    fail("child compile failed (" & $exit_code & "):\n" & output)
  child_executable

proc run_child(child_executable, child_workspace: Path) =
  let command = "cd " & quoteShell($child_workspace) & " && " &
    quoteShell($child_executable)
  let (output, exit_code) = execCmdEx(command)
  if exit_code != 0:
    fail("child execution failed (" & $exit_code & "):\n" & output)
  stdout.write(output)

proc find_child_database(child_workspace: Path): Path =
  var matches: seq[Path] = @[]
  for (kind, path) in walkDir($child_workspace):
    if kind != pcDir:
      continue
    let directory = splitFile(path)
    if not directory.name.startsWith("run-"):
      continue
    let database = Path(path) / Path("vecherinka_provenance.sqlite3")
    if fileExists($database):
      matches.add(database)

  if matches.len != 1:
    fail("expected exactly one child provenance database, found " &
      $matches.len)
  matches[0]

vecherinka(inspect):
  > load_provenance ChildRun ~> ProvenanceFacts:
    so(ChildRun, ProvenanceFacts, input) do:
      let reader = openProvenance(Path(input.database_path))
      try:
        let info = reader.runInfo()
        let artifacts = reader.artifacts()
        let roots = reader.roots()
        let leaves = reader.leaves()
        var artifact_paths: seq[string] = @[]
        var root_paths: seq[string] = @[]
        var leaf_paths: seq[string] = @[]
        for artifact in artifacts:
          artifact_paths.add($artifact.path)
        for root in roots:
          root_paths.add($root)
        for leaf in leaves:
          leaf_paths.add($leaf)
        pure(ProvenanceFacts(
          database_path: input.database_path,
          run_dir: $info.run_dir,
          status: info.status,
          last_commit_seq: int(info.last_commit_seq),
          artifact_paths: artifact_paths,
          root_paths: root_paths,
          leaf_paths: leaf_paths))
      finally:
        reader.close()

  > verify_provenance ProvenanceFacts ~> ProvenanceReport:
    so(ProvenanceFacts, ProvenanceReport, input) do:
      if input.leaf_paths.len != 1:
        raise newException(ValueError,
          "expected one child leaf, found " & $input.leaf_paths.len)
      let reader = openProvenance(Path(input.database_path))
      try:
        let leaf = reader.artifact(Path(input.leaf_paths[0]))
        if leaf.isNone:
          raise newException(ValueError,
            "child leaf missing from provenance database")
        var predecessors: seq[string] = @[]
        for predecessor in leaf.get.predecessors:
          predecessors.add($predecessor)
        let predecessor_is_root = input.root_paths.len == 1 and
          predecessors.len == 1 and predecessors[0] == input.root_paths[0]
        let valid = input.status == "finished" and
          input.last_commit_seq == 2 and
          input.artifact_paths.len == 2 and
          input.root_paths.len == 1 and
          input.leaf_paths.len == 1 and
          leaf.get.children.len == 0 and predecessor_is_root
        pure(ProvenanceReport(
          database_path: input.database_path,
          run_dir: input.run_dir,
          status: input.status,
          last_commit_seq: input.last_commit_seq,
          artifact_count: input.artifact_paths.len,
          root_count: input.root_paths.len,
          leaf_count: input.leaf_paths.len,
          leaf_path: input.leaf_paths[0],
          leaf_predecessors: predecessors,
          valid: valid))
      finally:
        reader.close()

  > entry ChildRun ~> ProvenanceReport {.entry.}:
    load_provenance >>> verify_provenance

let project_paths = source_paths()
let child_workspace = Path(createTempDir("vecherinka-provenance-poc-", ""))
let child_executable = compile_child(
  project_paths.source_root, project_paths.child_source, child_workspace)
run_child(child_executable, child_workspace)
let database_path = find_child_database(child_workspace)
let report = inspect(ChildRun(database_path: $database_path))

echo "child-workspace: ", child_workspace
echo "provenance-database: ", report.database_path
echo "run-dir: ", report.run_dir
echo "status: ", report.status
echo "last-commit-seq: ", report.last_commit_seq
echo "artifact-count: ", report.artifact_count
echo "root-count: ", report.root_count
echo "leaf-count: ", report.leaf_count
echo "leaf-path: ", report.leaf_path
echo "leaf-predecessors: ", report.leaf_predecessors
echo "valid: ", report.valid

if not report.valid:
  quit("provenance report failed validation", QuitFailure)
