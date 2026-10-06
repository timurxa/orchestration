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
    predecessors: seq[uint64] = @[];
    operation = ""; flow_kind = ""; request_id = ""): StoredArtifact =
  StoredArtifact(id: id, codec_id: "test", codec_version: 1,
    payload_text: payload, predecessor_ids: predecessors,
    operation: operation, flow_kind: flow_kind, request_id: request_id)

proc checkpoint(sequence: int64; payload: string): StoreCheckpoint =
  StoreCheckpoint(sequence: sequence,
    format_version: checkpoint_format_version, status: "running",
    payload_text: payload)

suite "Vecherinka SQLite value store":
  test "reopens serialized payload, ordered predecessors, and checkpoint":
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
          @[3'u64, 2'u64, 3'u64],
          operation = "model", flow_kind = "fk_model", request_id = "request-1")],
      checkpoint(0, "{\"ready\":[7]}"),
      attempts = [StoreAttempt(request_id: "request-1", state: sasPrepared,
        payload_text: "{\"input_artifact\":7}")])
    store.close()

    let reopened = open_vecherinka_store(database, metadata)
    check reopened.metadata() == metadata
    var workflow_only = metadata
    workflow_only.run_id = ""
    let reopened_without_run_id = open_vecherinka_store(database, workflow_only)
    check reopened_without_run_id.metadata().run_id == metadata.run_id
    reopened_without_run_id.close()
    let artifact = reopened.artifact(7)
    check artifact.isSome
    check artifact.get.codec_id == "test"
    check artifact.get.codec_version == 1
    check artifact.get.payload_text == "payload α\n" & repeat("detail", 1000)
    check artifact.get.predecessor_ids == @[3'u64, 2'u64, 3'u64]
    check artifact.get.operation == "model"
    check artifact.get.flow_kind == "fk_model"
    check artifact.get.request_id == "request-1"
    check reopened.artifact_for_request("request-1").get.id == 7
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

  test "one model request cannot own multiple output artifacts":
    let root = Path(createTempDir("vecherinka-store-request-", ""))
    let store = create_vecherinka_store(root / Path("run.sqlite3"),
      test_metadata())
    expect DbError:
      store.commit_transition(-1,
        [stored(1, "first", request_id = "request-1"),
         stored(2, "second", request_id = "request-1")],
        checkpoint(0, "rolled back"))
    check store.artifact(1).isNone
    check store.artifact(2).isNone
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

  test "upgrades schema 5 without deleting its unused file table":
    let root = Path(createTempDir("vecherinka-store-upgrade-", ""))
    let database = root / Path("run.sqlite3")
    let metadata = test_metadata()
    let store = create_vecherinka_store(database, metadata)
    store.commit_transition(-1, [stored(1, "payload")], checkpoint(0, "saved"))
    store.close()

    let legacy = open($database, "", "", "")
    legacy.exec(SqlQuery("""CREATE TABLE artifact_file (
      artifact_id INTEGER NOT NULL REFERENCES artifact(artifact_id),
      name TEXT NOT NULL,
      bytes BLOB NOT NULL,
      PRIMARY KEY (artifact_id, name))"""))
    legacy.exec(sql"INSERT INTO artifact_file VALUES(?, ?, ?)",
      1, "legacy.bin", @[0'u8, 255'u8])
    legacy.exec(SqlQuery("PRAGMA user_version = 5"))
    legacy.close()

    let reopened = open_vecherinka_store(database, metadata)
    check reopened.artifact(1).get.payload_text == "payload"
    reopened.close()
    let verify = open($database, "", "", "")
    check verify.getValue(SqlQuery("PRAGMA user_version")) == "6"
    check verify.getValue(sql"SELECT COUNT(*) FROM artifact_file") == "1"
    verify.close()

  test "terminal run status cannot be reopened as active":
    let root = Path(createTempDir("vecherinka-store-terminal-", ""))
    let database = root / Path("run.sqlite3")
    let store = create_vecherinka_store(database, test_metadata())
    store.commit_transition(-1, [], StoreCheckpoint(sequence: 0,
      format_version: checkpoint_format_version, status: "running",
      payload_text: "active"))
    store.commit_transition(0, [], StoreCheckpoint(sequence: 1,
      format_version: checkpoint_format_version, status: "finished",
      payload_text: "done"))
    expect ValueError:
      store.set_status("running")
    expect ValueError:
      store.commit_transition(1, [], checkpoint(2, "reopen"))
    check store.status() == "finished"
    check store.checkpoint().get.status == "finished"
    store.close()
