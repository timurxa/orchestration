import std/[options, os, paths, strutils, tempfiles, unittest]
import db_connector/db_sqlite
import ../api/vecherinka_store

proc test_metadata(): StoreMetadata =
  StoreMetadata(
    run_id: "run-test",
    workflow_id: "test-workflow",
    workflow_fingerprint: "sha256:test",
    workflow_manifest_json: "{}",
    codec_version: 1,
    checkpoint_version: checkpoint_format_version)

proc stored(id: uint64; payload: string;
    predecessors: seq[uint64] = @[]; files: seq[StoreFile] = @[]): StoredArtifact =
  StoredArtifact(id: id, codec_id: "test", codec_version: 1,
    payload_text: payload, predecessor_ids: predecessors, files: files)

proc checkpoint(sequence: int64; payload: string): StoreCheckpoint =
  StoreCheckpoint(sequence: sequence,
    format_version: checkpoint_format_version, status: "running",
    payload_text: payload)

suite "Vecherinka SQLite value store":
  test "reopens payload, raw bytes, ordered predecessors, and checkpoint":
    let root = Path(createTempDir("vecherinka-store-", ""))
    let database = root / Path("run.sqlite3")
    let metadata = test_metadata()
    let store = create_vecherinka_store(database, metadata)
    store.commit_transition(
      -1,
      [
        stored(2, "second root"),
        stored(3, "third root"),
        stored(7, "payload α\n" & repeat("detail", 1000),
          @[3'u64, 2'u64, 3'u64], @[
            StoreFile(name: "binary.dat", bytes: @[0'u8, 1, 127, 128, 255]),
            StoreFile(name: "empty.bin", bytes: @[])])],
      checkpoint(0, "{\"ready\":[7]}"),
      attempts = [StoreAttempt(request_id: "request-1", state: sasPrepared,
        payload_text: "{\"input_artifact\":7}")])
    store.close()

    let reopened = open_vecherinka_store(database, metadata)
    check reopened.metadata() == metadata
    let artifact = reopened.artifact(7)
    check artifact.isSome
    check artifact.get.codec_id == "test"
    check artifact.get.codec_version == 1
    check artifact.get.payload_text == "payload α\n" & repeat("detail", 1000)
    check artifact.get.predecessor_ids == @[3'u64, 2'u64, 3'u64]
    check artifact.get.files.len == 2
    check artifact.get.files[0].name == "binary.dat"
    check artifact.get.files[0].bytes == @[0'u8, 1, 127, 128, 255]
    check artifact.get.files[1].name == "empty.bin"
    check artifact.get.files[1].bytes.len == 0
    let saved = reopened.checkpoint()
    check saved.isSome
    check saved.get.sequence == 0
    check saved.get.format_version == checkpoint_format_version
    check saved.get.status == "running"
    check saved.get.payload_text == "{\"ready\":[7]}"
    let attempt = reopened.attempt("request-1")
    check attempt.isSome
    check attempt.get.state == sasPrepared
    check attempt.get.payload_text == "{\"input_artifact\":7}"
    reopened.commit_transition(0, [], checkpoint(1, "submitted"),
      attempts = [StoreAttempt(request_id: "request-1", state: sasSubmitted,
        payload_text: "{\"input_artifact\":7}")])
    check reopened.attempt("request-1").get.state == sasSubmitted
    check reopened.checkpoint().get.sequence == 1
    reopened.set_status("running")
    check reopened.status() == "running"
    reopened.set_status("interrupted")
    check reopened.status() == "interrupted"
    check reopened.checkpoint().get.status == "interrupted"
    reopened.close()

  test "failed transition rolls back artifacts and checkpoint together":
    let root = Path(createTempDir("vecherinka-store-rollback-", ""))
    let database = root / Path("run.sqlite3")
    let store = create_vecherinka_store(database, test_metadata())
    store.commit_transition(-1, [stored(1, "committed")], checkpoint(0, "first"))

    expect(DbError):
      store.commit_transition(0,
        [stored(2, "must roll back"), stored(1, "duplicate ID")],
        checkpoint(1, "must roll back"))

    check store.artifact(2).isNone
    check store.checkpoint().get.sequence == 0
    check store.checkpoint().get.payload_text == "first"
    store.close()

  test "stale writer and incompatible run metadata are rejected":
    let root = Path(createTempDir("vecherinka-store-sequence-", ""))
    let database = root / Path("run.sqlite3")
    let metadata = test_metadata()
    let store = create_vecherinka_store(database, metadata)
    store.commit_transition(-1, [], checkpoint(0, "saved"))

    expect ValueError:
      store.commit_transition(-1, [stored(9, "not saved")], checkpoint(0, "stale"))
    check store.artifact(9).isNone

    var mismatched = metadata
    mismatched.workflow_fingerprint = "sha256:changed"
    expect ValueError:
      discard open_vecherinka_store(database, mismatched)
    check store.checkpoint().get.payload_text == "saved"
    store.close()

  test "resume never creates a missing database":
    let root = Path(createTempDir("vecherinka-store-missing-", ""))
    let database = root / Path("missing.sqlite3")
    expect IOError:
      discard open_vecherinka_store(database, test_metadata())
    check not fileExists($database)

  test "unsafe or colliding file entries roll back the whole transition":
    let root = Path(createTempDir("vecherinka-store-unsafe-", ""))
    let database = root / Path("run.sqlite3")
    let store = create_vecherinka_store(database, test_metadata())
    expect ValueError:
      store.commit_transition(-1,
        [stored(1, "unsafe", files = @[
          StoreFile(name: "../outside", bytes: @[1'u8])])],
        checkpoint(0, "not committed"))
    expect ValueError:
      store.commit_transition(-1,
        [stored(1, "collision", files = @[
          StoreFile(name: "bundle", bytes: @[1'u8]),
          StoreFile(name: "bundle/member", bytes: @[2'u8])])],
        checkpoint(0, "not committed"))
    check store.artifact(1).isNone
    check store.checkpoint().isNone
    store.close()
