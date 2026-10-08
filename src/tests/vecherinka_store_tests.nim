import std/[options, os, paths, sequtils, strutils, tempfiles, unittest]
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
    check attempt.get.output_artifact_id.isNone
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

  test "graph, worker conversations, and live polling are queryable in SQLite":
    let root = Path(createTempDir("vecherinka-inspectability-", ""))
    let database = root / Path("run.sqlite3")
    let store = create_vecherinka_store(database, test_metadata())
    let execution = store.start_execution("owner-test", 42)
    expect ValueError:
      discard store.start_execution("owner-intruder", 43)
    store.register_workflow_graph(
      [WorkflowNode(flow_key: "entry", kind: "fk_model"),
       WorkflowNode(flow_key: "finish", kind: "fk_pure")],
      [WorkflowEdge(source_flow_key: "entry", edge_kind: "continuation",
        position: 0, target_flow_key: "finish")], execution)
    discard store.append_conversation_event(ConversationEvent(
      execution_id: execution, kind: "run.note", details_json: "{}"))
    store.commit_transition(-1, [stored(0, "input"), stored(1, "output",
      @[0'u64], request_id = "i:0")], checkpoint(0, "{}"),
      attempts = [StoreAttempt(request_id: "i:0", state: sasPrepared,
        payload_text: "{}", flow_key: "entry", input_artifact_id: 0,
        reserved_output_artifact_id: 1,
        model: "luna", effort: "low")])
    let session = store.start_worker_session("i:0", execution, "agent-1")
    check store.attempt("i:0").get.reserved_output_artifact_id == 1
    check store.attempt("i:0").get.output_artifact_id.isNone
    let outgoing = store.append_conversation_event(ConversationEvent(
      execution_id: execution, kind: "protocol.message", direction: "outgoing",
      request_id: "i:0", session_id: session.session_id, agent_id: "agent-1",
      rpc_id: "i:12", raw_json: "{\"id\":12,\"method\":\"turn/start\"}",
      write_state: "attempted"))
    store.set_conversation_write_state(outgoing, "write_returned")
    discard store.append_conversation_event(ConversationEvent(
      execution_id: execution, kind: "protocol.message", direction: "incoming",
      rpc_id: "i:12", thread_id: "thread-1", raw_json:
        "{\"id\":12,\"result\":{\"thread\":{\"id\":\"thread-1\"}}}"))
    let server_request = store.append_conversation_event(ConversationEvent(
      execution_id: execution, kind: "protocol.message", direction: "incoming",
      request_id: "i:0", session_id: session.session_id, agent_id: "agent-1",
      rpc_id: "i:40", raw_json: "{\"id\":40,\"method\":\"tool/call\"}"))
    discard store.append_conversation_event(ConversationEvent(
      execution_id: execution, kind: "protocol.message", direction: "outgoing",
      rpc_id: "i:40", raw_json: "{\"id\":40,\"result\":{}}"))
    let reader = open_vecherinka_reader(database)
    defer: reader.close()
    let snapshot = reader.poll(0)
    check snapshot.snapshot.status == "running"
    check snapshot.events.len >= 4
    let protocol = snapshot.events.filterIt(it.kind == "protocol.message" and
      it.rpc_id == "i:12")
    check protocol.len == 2
    check protocol[0].request_id == "i:0"
    check protocol[0].session_id == session.session_id
    check protocol[0].write_state == "write_returned"
    check protocol[1].request_id == "i:0"
    check protocol[1].session_id == session.session_id
    check protocol[1].thread_id == "thread-1"
    let response = snapshot.events.filterIt(it.rpc_id == "i:40" and
      it.direction == "outgoing")
    check response.len == 1
    check response[0].request_id == "i:0"
    check response[0].session_id == session.session_id
    check server_request > 0
    check session.session_id > 0
    let query_only = open($database, "", "", "")
    query_only.exec(SqlQuery("PRAGMA query_only = ON"))
    expect DbError:
      query_only.exec(SqlQuery("UPDATE run_metadata SET status = 'failed'"))
    query_only.close()
    discard store.append_conversation_event(ConversationEvent(
      execution_id: execution, kind: "protocol.message", direction: "outgoing",
      request_id: "i:0", session_id: session.session_id,
      raw_json: "{}", write_state: "attempted"))
    store.finish_execution(execution)
    let restarted = store.start_execution("owner-restarted", 43)
    let final_page = reader.poll(snapshot.last_event_id)
    check final_page.events.anyIt(it.write_state == "outcome_unknown")
    store.finish_execution(restarted)
    store.close()

  test "stale execution takeover fences the previous writer":
    let root = Path(createTempDir("vecherinka-execution-lease-", ""))
    let database = root / Path("run.sqlite3")
    let store = create_vecherinka_store(database, test_metadata())
    let previous = store.start_execution("owner-old", 51)
    let external = open($database, "", "", "")
    external.exec(sql"UPDATE run_execution SET heartbeat_at_ns = 0 WHERE execution_id = ?",
      previous)
    external.close()
    let current = store.start_execution("owner-new", 52)
    expect ValueError:
      store.commit_transition(-1, [], checkpoint(0, "stale"),
        execution_id = previous)
    check store.checkpoint().isNone
    store.check_execution_owner(current)
    store.finish_execution(current)
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
    let legacy = open($database, "", "", "")
    legacy.exec(SqlQuery("""CREATE TABLE run_metadata (
      singleton INTEGER PRIMARY KEY, run_id TEXT NOT NULL, workflow_id TEXT NOT NULL,
      workflow_fingerprint TEXT NOT NULL, workflow_manifest_json TEXT NOT NULL,
      codec_version INTEGER NOT NULL, checkpoint_version INTEGER NOT NULL,
      status TEXT NOT NULL)"""))
    legacy.exec(sql"""INSERT INTO run_metadata VALUES(1, ?, ?, ?, ?, ?, ?, 'interrupted')""",
      metadata.run_id, metadata.workflow_id, metadata.workflow_fingerprint,
      metadata.workflow_manifest_json, metadata.codec_version,
      metadata.checkpoint_version)
    legacy.exec(SqlQuery("""CREATE TABLE artifact (
      artifact_id INTEGER PRIMARY KEY, codec_id TEXT NOT NULL,
      codec_version INTEGER NOT NULL, payload_text TEXT NOT NULL,
      operation TEXT NOT NULL, flow_kind TEXT NOT NULL, request_id TEXT NOT NULL)"""))
    legacy.exec(SqlQuery("""CREATE TABLE predecessor (
      artifact_id INTEGER NOT NULL REFERENCES artifact(artifact_id),
      position INTEGER NOT NULL, predecessor_id INTEGER NOT NULL REFERENCES artifact(artifact_id),
      PRIMARY KEY (artifact_id, position))"""))
    legacy.exec(SqlQuery("CREATE TABLE checkpoint (singleton INTEGER PRIMARY KEY, sequence INTEGER NOT NULL, format_version INTEGER NOT NULL, status TEXT NOT NULL, payload_text TEXT NOT NULL)"))
    legacy.exec(SqlQuery("CREATE TABLE model_attempt (request_id TEXT PRIMARY KEY, state TEXT NOT NULL, payload_text TEXT NOT NULL)"))
    legacy.exec(sql"""INSERT INTO artifact VALUES(1, 'test', 1, 'payload', '', '', '')""")
    legacy.exec(sql"""INSERT INTO artifact VALUES(2, 'test', 1, 'model-output',
      'model', 'fk_model', 'i:9')""")
    legacy.exec(sql"""INSERT INTO model_attempt VALUES('i:9', 'sasCommitted',
      '{"flow_key":"old-model","input_artifact_id":"1","output_artifact_id":"2"}')""")
    legacy.exec(sql"INSERT INTO checkpoint VALUES(1, 0, 2, 'interrupted', 'saved')")
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
    let migrated_attempt = reopened.attempt("i:9").get
    check migrated_attempt.flow_key == "old-model"
    check migrated_attempt.input_artifact_id == 1
    check migrated_attempt.reserved_output_artifact_id == 2
    check migrated_attempt.output_artifact_id == some(2'i64)
    reopened.register_workflow_graph(
      [WorkflowNode(flow_key: "old-model", kind: "fk_model",
        details_json: "{\"model\":\"gpt-6-luna\",\"effort\":\"low\"}")], [])
    check reopened.attempt("i:9").get.model == "gpt-6-luna"
    check reopened.attempt("i:9").get.effort == "low"
    reopened.close()
    let verify = open($database, "", "", "")
    check verify.getValue(SqlQuery("PRAGMA user_version")) == "8"
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
