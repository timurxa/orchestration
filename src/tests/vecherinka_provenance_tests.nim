import std/[options, os, paths, tempfiles, unittest]
import ../api/vecherinka

suite "SQLite provenance store":
  test "stores direct predecessors and derives children":
    let root = Path(createTempDir("vecherinka-provenance-", ""))
    let database_path = root / Path("vecherinka_provenance.sqlite3")
    let artifact_one = root / Path("artifact-1")
    let artifact_two = root / Path("artifact-2")
    let artifact_three = root / Path("artifact-3")
    createDir($artifact_one)
    createDir($artifact_two)
    createDir($artifact_three)

    let store = open_provenance_store(database_path, root)
    store.record_artifact(artifact_one, @[])
    store.record_artifact(artifact_two, @[artifact_one])
    store.record_artifact(artifact_three, @[artifact_one, artifact_one, artifact_two])
    store.set_status("finished")
    store.close()

    let reader = openProvenance(database_path)
    let info = reader.runInfo()
    check info.status == "finished"
    check info.last_commit_seq == 3

    let second = reader.artifact(Path("artifact-2"))
    check isSome(second)
    check second.get.predecessors == @[artifact_one]
    check second.get.children == @[artifact_three]

    let third = reader.artifact(artifact_three)
    check isSome(third)
    check third.get.predecessors == @[artifact_one, artifact_one, artifact_two]
    check reader.roots() == @[artifact_one]
    check reader.leaves() == @[artifact_three]

    let new_artifacts = reader.artifactsAfter(2)
    check new_artifacts.len == 1
    check new_artifacts[0].path == artifact_three
    reader.close()

  test "preserves an input artifact outside the run directory":
    let root = Path(createTempDir("vecherinka-provenance-input-", ""))
    let run_dir = root / Path("run")
    let input_dir = root / Path("input")
    createDir($run_dir)
    createDir($input_dir)
    let database_path = run_dir / Path("vecherinka_provenance.sqlite3")
    let input_artifact = input_dir / Path("source")
    let output_artifact = run_dir / Path("artifact-1")
    createDir($input_artifact)
    createDir($output_artifact)

    let store = open_provenance_store(database_path, run_dir)
    store.record_artifact(input_artifact, @[])
    store.record_artifact(output_artifact, @[input_artifact])
    store.close()

    let reader = openProvenance(database_path)
    let output = reader.artifact(output_artifact)
    check isSome(output)
    check output.get.predecessors == @[input_artifact]
    reader.close()
