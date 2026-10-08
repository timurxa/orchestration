## Low-level SQLite authority for durable Vecherinka run values.
## Payload text and file bytes live in SQLite; each transition can commit
## artifact values, ordered predecessor IDs, and its checkpoint atomically.

{.warning[UnusedImport]: off.}
import std/algorithm
{.warning[UnusedImport]: on.}
import std/[json, options, os, paths, strutils, times]
import db_connector/db_sqlite

type
  VecherinkaStore* = ref object
    database_path*: Path
    db: DbConn
    closed: bool

  VecherinkaReader* = ref object
    database_path*: Path
    db: DbConn
    closed: bool

  StoredArtifact* = object
    id*: uint64
    codec_id*: string
    codec_version*: int
    payload_text*: string
    predecessor_ids*: seq[uint64]
    operation*: string
    flow_kind*: string
    request_id*: string

  WorkOccurrence* = object
    work_id*: int64
    flow_key*: string
    kind*: string
    state*: string
    input_artifact_id*: int64
    output_artifact_id*: Option[int64]
    request_id*: string
    expansion_id*: int64
    join_id*: int64
    root_name*: string
    slot*: int

  WorkEdge* = object
    source_work_id*: int64
    target_work_id*: int64
    relation*: string
    position*: int

  StoreMetadata* = object
    run_id*: string
    workflow_id*: string
    workflow_fingerprint*: string
    workflow_manifest_json*: string
    codec_version*: int
    checkpoint_version*: int

  StoreAttemptState* = enum
    sasPrepared,
    sasSubmitted,
    sasUnknown,
    sasOutputReceived,
    sasCommitted,
    sasFailed

  StoreAttempt* = object
    request_id*: string
    state*: StoreAttemptState
    payload_text*: string
    flow_key*: string
    input_artifact_id*: int64
    reserved_output_artifact_id*: int64
    output_artifact_id*: Option[int64]
    model*: string
    effort*: string

  WorkflowNode* = object
    flow_key*: string
    kind*: string
    expansion_id*: int64
    details_json*: string

  WorkflowEdge* = object
    source_flow_key*: string
    edge_kind*: string
    position*: int
    target_flow_key*: string
    expansion_id*: int64

  WorkflowExpansion* = object
    expansion_id*: int64
    parent_flow_key*: string
    input_artifact_id*: int64
    root_flow_key*: string
    graph_signature*: string

  WorkerSession* = object
    session_id*: int64
    request_id*: string
    execution_id*: int64
    generation*: int
    agent_id*: string
    thread_id*: string
    state*: string

  WorkerSessionUpdate* = object
    session_id*: int64
    state*: string

  ConversationEvent* = object
    event_id*: int64
    execution_id*: int64
    kind*: string
    direction*: string
    request_id*: string
    session_id*: int64
    agent_id*: string
    rpc_id*: string
    thread_id*: string
    turn_id*: string
    raw_json*: string
    details_json*: string
    write_state*: string
    timestamp_ns*: int64

  StoreSnapshot* = object
    status*: string
    checkpoint_sequence*: int64
    checkpoint_payload*: string
    execution_id*: int64
    heartbeat_at_ns*: int64
    history_started_at_ns*: int64

  StorePoll* = object
    snapshot*: StoreSnapshot
    events*: seq[ConversationEvent]
    last_event_id*: int64

  StoreCheckpoint* = object
    sequence*: int64
    format_version*: int
    status*: string
    payload_text*: string

const
  store_schema_version* = 8
  legacy_store_schema_version = 5
  previous_store_schema_version = 6
  inspectability_store_schema_version = 7
  checkpoint_format_version* = 2
  execution_lease_timeout_ns = 30_000_000_000'i64

proc exec_sql(db: DbConn; statement: string) =
  db.exec(SqlQuery(statement))

proc as_sql_id(id: uint64): int64 =
  if id > uint64(high(int64)):
    raise newException(ValueError, "artifact ID exceeds SQLite integer range")
  int64(id)

proc as_artifact_id(id: string): uint64 =
  let parsed = parseBiggestInt(id)
  if parsed < 0:
    raise newException(ValueError, "stored artifact ID is negative")
  uint64(parsed)

proc require_open(store: VecherinkaStore) =
  if store.isNil or store.closed:
    raise newException(ValueError, "Vecherinka store is closed")

proc timestamp_ns(): int64 =
  int64(epochTime() * 1_000_000_000.0)

proc require_active_execution(store: VecherinkaStore; execution_id: int64) =
  if execution_id <= 0:
    raise newException(ValueError, "execution ID is required")
  let row = store.db.getRow(sql"""SELECT r.active_execution_id,
      e.ended_at_ns FROM run_metadata r LEFT JOIN run_execution e
        ON e.execution_id = r.active_execution_id
      WHERE r.singleton = 1""")
  if row.len < 2 or row[0].len == 0 or parseBiggestInt(row[0]) != execution_id or
      row[1].len == 0 or parseBiggestInt(row[1]) != 0:
    raise newException(ValueError, "SQLite execution ownership was lost")

proc check_execution_owner*(store: VecherinkaStore; execution_id: int64) =
  require_open(store)
  require_active_execution(store, execution_id)

proc create_inspectability_tables(db: DbConn) =
  exec_sql(db, """CREATE TABLE workflow_node (
    flow_key TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    expansion_id INTEGER NOT NULL DEFAULT 0,
    details_json TEXT NOT NULL DEFAULT '{}'
  )""")
  exec_sql(db, """CREATE TABLE workflow_edge (
    source_flow_key TEXT NOT NULL REFERENCES workflow_node(flow_key),
    edge_kind TEXT NOT NULL,
    position INTEGER NOT NULL,
    target_flow_key TEXT NOT NULL REFERENCES workflow_node(flow_key),
    expansion_id INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(source_flow_key, edge_kind, position, expansion_id)
  )""")
  exec_sql(db, """CREATE TABLE run_execution (
    execution_id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_token TEXT NOT NULL,
    owner_pid INTEGER NOT NULL,
    started_at_ns INTEGER NOT NULL,
    heartbeat_at_ns INTEGER NOT NULL,
    ended_at_ns INTEGER NOT NULL DEFAULT 0
  )""")
  exec_sql(db, """CREATE TABLE worker_session (
    session_id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id TEXT NOT NULL REFERENCES model_attempt(request_id),
    execution_id INTEGER NOT NULL REFERENCES run_execution(execution_id),
    generation INTEGER NOT NULL,
    agent_id TEXT NOT NULL,
    thread_id TEXT NOT NULL DEFAULT '',
    state TEXT NOT NULL,
    UNIQUE(request_id, generation),
    UNIQUE(execution_id, agent_id)
  )""")
  exec_sql(db, "CREATE INDEX worker_request_idx ON worker_session(request_id, generation)")
  exec_sql(db, """CREATE TABLE conversation_event (
    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
    execution_id INTEGER NOT NULL REFERENCES run_execution(execution_id),
    kind TEXT NOT NULL,
    direction TEXT NOT NULL DEFAULT '',
    request_id TEXT NOT NULL DEFAULT '',
    session_id INTEGER REFERENCES worker_session(session_id),
    agent_id TEXT NOT NULL DEFAULT '',
    rpc_id TEXT NOT NULL DEFAULT '',
    thread_id TEXT NOT NULL DEFAULT '',
    turn_id TEXT NOT NULL DEFAULT '',
    raw_json TEXT NOT NULL DEFAULT '',
    details_json TEXT NOT NULL DEFAULT '{}',
    write_state TEXT NOT NULL DEFAULT '',
    timestamp_ns INTEGER NOT NULL
  )""")
  exec_sql(db, "CREATE INDEX conversation_session_idx ON conversation_event(session_id, event_id)")
  exec_sql(db, "CREATE INDEX conversation_request_idx ON conversation_event(request_id, event_id)")
  exec_sql(db, "CREATE INDEX conversation_thread_idx ON conversation_event(thread_id, event_id)")
  exec_sql(db, """CREATE TABLE workflow_expansion (
    expansion_id INTEGER PRIMARY KEY,
    parent_flow_key TEXT NOT NULL,
    input_artifact_id INTEGER NOT NULL,
    root_flow_key TEXT NOT NULL,
    graph_signature TEXT NOT NULL
  )""")

proc create_work_dag_tables(db: DbConn) =
  exec_sql(db, """CREATE TABLE work_occurrence (
    work_id INTEGER PRIMARY KEY CHECK(work_id > 0),
    flow_key TEXT NOT NULL,
    kind TEXT NOT NULL,
    state TEXT NOT NULL CHECK(state IN
      ('queued', 'running', 'waiting', 'completed', 'failed')),
    input_artifact_id INTEGER NOT NULL,
    output_artifact_id INTEGER,
    request_id TEXT NOT NULL DEFAULT '',
    expansion_id INTEGER NOT NULL DEFAULT 0,
    join_id INTEGER NOT NULL DEFAULT 0,
    root_name TEXT NOT NULL DEFAULT '',
    slot INTEGER NOT NULL DEFAULT -1
  )""")
  exec_sql(db, "CREATE INDEX work_occurrence_request_idx ON work_occurrence(request_id)")
  exec_sql(db, "CREATE INDEX work_occurrence_output_idx ON work_occurrence(output_artifact_id)")
  exec_sql(db, """CREATE TABLE work_edge (
    source_work_id INTEGER NOT NULL REFERENCES work_occurrence(work_id),
    target_work_id INTEGER NOT NULL REFERENCES work_occurrence(work_id),
    relation TEXT NOT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    CHECK(source_work_id < target_work_id),
    PRIMARY KEY(source_work_id, target_work_id, relation, position)
  )""")
  exec_sql(db, "CREATE INDEX work_edge_target_idx ON work_edge(target_work_id)")
  exec_sql(db, "CREATE UNIQUE INDEX work_edge_slot_idx ON work_edge(source_work_id, relation, position)")

proc json_id(node: JsonNode; key: string): Option[int64] =
  if node.kind != JObject or not node.hasKey(key):
    return none(int64)
  try:
    case node[key].kind
    of JString: some(parseBiggestInt(node[key].getStr))
    of JInt: some(node[key].getBiggestInt)
    else: none(int64)
  except CatchableError:
    none(int64)

proc migrate_model_attempt_metadata(db: DbConn) =
  for row in db.getAllRows(sql"SELECT request_id, payload_text FROM model_attempt"):
    try:
      let payload = parseJson(row[1])
      let flow_key = if payload.kind == JObject and payload.hasKey("flow_key") and
          payload["flow_key"].kind == JString: payload["flow_key"].getStr else: ""
      let input_id = json_id(payload, "input_artifact_id")
      let reserved_id = json_id(payload, "output_artifact_id")
      if flow_key.len == 0 or input_id.isNone or reserved_id.isNone:
        continue
      db.exec(sql"""UPDATE model_attempt SET flow_key = ?,
          input_artifact_id = ?, reserved_output_artifact_id = ?,
          output_artifact_id = CASE WHEN state = 'sasCommitted' THEN
            (SELECT artifact_id FROM artifact WHERE request_id = ?)
            ELSE NULL END WHERE request_id = ?""",
        flow_key, input_id.get, reserved_id.get, row[0], row[0])
    except CatchableError:
      discard

proc refresh_attempt_profiles(db: DbConn; nodes: openArray[WorkflowNode]) =
  for node in nodes:
    if node.kind != "fk_model":
      continue
    if node.details_json.len == 0:
      continue
    let details = parseJson(node.details_json)
    if details.kind == JObject and details.hasKey("model") and
        details.hasKey("effort") and details["model"].kind == JString and
        details["effort"].kind == JString:
      db.exec(sql"""UPDATE model_attempt SET model = ?, effort = ?
        WHERE flow_key = ? AND (model = '' OR effort = '')""",
        details["model"].getStr, details["effort"].getStr, node.flow_key)

proc close*(store: VecherinkaStore)

proc open_database(database_path: Path): VecherinkaStore =
  if $database_path == "":
    raise newException(ValueError, "database path is required")
  new result
  result.database_path = Path(absolutePath($database_path))
  result.closed = false
  try:
    result.db = open($result.database_path, "", "", "")
    exec_sql(result.db, "PRAGMA foreign_keys = ON")
    exec_sql(result.db, "PRAGMA journal_mode = WAL")
  except CatchableError:
    if not result.db.isNil:
      result.db.close()
    result.db = nil
    result.closed = true
    raise

proc initialize_schema(store: VecherinkaStore; metadata: StoreMetadata) =
  if metadata.run_id.len == 0 or metadata.workflow_id.len == 0 or
      metadata.workflow_fingerprint.len == 0 or
      metadata.workflow_manifest_json.len == 0 or metadata.codec_version <= 0 or
      metadata.checkpoint_version <= 0:
    raise newException(ValueError, "complete store metadata is required")
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    let current_version = parseInt(store.db.getValue(sql"PRAGMA user_version"))
    let existing_tables = store.db.getValue(sql"""SELECT COUNT(*) FROM
      sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'""")
    if current_version != 0 or parseInt(existing_tables) != 0:
      raise newException(ValueError,
        "database already contains a SQLite store or unrelated schema")
    exec_sql(store.db, """CREATE TABLE run_metadata (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      run_id TEXT NOT NULL,
      workflow_id TEXT NOT NULL,
      workflow_fingerprint TEXT NOT NULL,
      workflow_manifest_json TEXT NOT NULL,
      codec_version INTEGER NOT NULL,
      checkpoint_version INTEGER NOT NULL,
      status TEXT NOT NULL,
      active_execution_id INTEGER,
      history_started_at_ns INTEGER NOT NULL DEFAULT 0
    )""")
    exec_sql(store.db, """CREATE TABLE artifact (
      artifact_id INTEGER PRIMARY KEY,
      codec_id TEXT NOT NULL,
      codec_version INTEGER NOT NULL,
      payload_text TEXT NOT NULL,
      operation TEXT NOT NULL,
      flow_kind TEXT NOT NULL,
      request_id TEXT NOT NULL
    )""")
    exec_sql(store.db, """CREATE TABLE predecessor (
      artifact_id INTEGER NOT NULL REFERENCES artifact(artifact_id),
      position INTEGER NOT NULL,
      predecessor_id INTEGER NOT NULL REFERENCES artifact(artifact_id),
      PRIMARY KEY (artifact_id, position)
    )""")
    exec_sql(store.db, """CREATE UNIQUE INDEX artifact_request_unique_idx
      ON artifact(request_id) WHERE request_id <> ''""")
    exec_sql(store.db, "CREATE INDEX predecessor_lookup_idx ON predecessor(predecessor_id)")
    exec_sql(store.db, """CREATE TABLE checkpoint (
      singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
      sequence INTEGER NOT NULL,
      format_version INTEGER NOT NULL,
      status TEXT NOT NULL,
      payload_text TEXT NOT NULL
    )""")
    exec_sql(store.db, """CREATE TABLE model_attempt (
      request_id TEXT PRIMARY KEY,
      state TEXT NOT NULL,
      payload_text TEXT NOT NULL,
      flow_key TEXT NOT NULL DEFAULT '',
      input_artifact_id INTEGER,
      reserved_output_artifact_id INTEGER,
      output_artifact_id INTEGER,
      model TEXT NOT NULL DEFAULT '',
      effort TEXT NOT NULL DEFAULT ''
    )""")
    create_inspectability_tables(store.db)
    create_work_dag_tables(store.db)
    store.db.exec(sql"""INSERT INTO run_metadata(
        singleton, run_id, workflow_id, workflow_fingerprint,
        workflow_manifest_json, codec_version, checkpoint_version, status,
        history_started_at_ns)
      VALUES(1, ?, ?, ?, ?, ?, ?, 'created', ?)""",
      metadata.run_id, metadata.workflow_id, metadata.workflow_fingerprint,
      metadata.workflow_manifest_json,
      metadata.codec_version, metadata.checkpoint_version, timestamp_ns())
    exec_sql(store.db, "PRAGMA user_version = " & $store_schema_version)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc create_vecherinka_store*(database_path: Path;
    metadata: StoreMetadata): VecherinkaStore =
  if fileExists($database_path) or dirExists($database_path):
    raise newException(ValueError, "store already exists: " & $database_path)
  result = open_database(database_path)
  try:
    initialize_schema(result, metadata)
  except CatchableError:
    result.close()
    raise

proc open_vecherinka_store*(database_path: Path;
    expected: StoreMetadata): VecherinkaStore =
  if not fileExists($database_path):
    raise newException(IOError, "store does not exist: " & $database_path)
  result = open_database(database_path)
  try:
    let version_text = result.db.getValue(sql"PRAGMA user_version")
    var version = if version_text.len == 0: 0 else: parseInt(version_text)
    if version notin {legacy_store_schema_version,
        previous_store_schema_version, inspectability_store_schema_version,
        store_schema_version}:
      raise newException(ValueError, "unsupported Vecherinka store schema")
    let row = result.db.getRow(sql"""SELECT run_id, workflow_id,
        workflow_fingerprint, workflow_manifest_json, codec_version,
        checkpoint_version
      FROM run_metadata WHERE singleton = 1""")
    if row.len < 6:
      raise newException(ValueError, "store has no run metadata")
    let requested = expected
    if (requested.run_id.len > 0 and row[0] != requested.run_id) or
        row[1] != requested.workflow_id or
        row[2] != requested.workflow_fingerprint or
        row[3] != requested.workflow_manifest_json or
        parseInt(row[4]) != requested.codec_version or
        parseInt(row[5]) != requested.checkpoint_version:
      raise newException(ValueError,
        "store workflow or codec version does not match this program")
    if version < store_schema_version:
      exec_sql(result.db, "BEGIN IMMEDIATE")
      try:
        if version < inspectability_store_schema_version:
          ## Upgrade old stores through schema 7 before adding the occurrence
          ## DAG tables. Historical work occurrences cannot be backfilled.
          if version == legacy_store_schema_version:
            ## Schema 5's legacy artifact_file table remains unused.
            exec_sql(result.db, "PRAGMA user_version = " &
              $previous_store_schema_version)
          exec_sql(result.db, "ALTER TABLE model_attempt ADD COLUMN flow_key TEXT NOT NULL DEFAULT ''")
          exec_sql(result.db, "ALTER TABLE model_attempt ADD COLUMN input_artifact_id INTEGER")
          exec_sql(result.db, "ALTER TABLE model_attempt ADD COLUMN reserved_output_artifact_id INTEGER")
          exec_sql(result.db, "ALTER TABLE model_attempt ADD COLUMN output_artifact_id INTEGER")
          exec_sql(result.db, "ALTER TABLE model_attempt ADD COLUMN model TEXT NOT NULL DEFAULT ''")
          exec_sql(result.db, "ALTER TABLE model_attempt ADD COLUMN effort TEXT NOT NULL DEFAULT ''")
          exec_sql(result.db, "ALTER TABLE run_metadata ADD COLUMN active_execution_id INTEGER")
          exec_sql(result.db, "ALTER TABLE run_metadata ADD COLUMN history_started_at_ns INTEGER NOT NULL DEFAULT 0")
          result.db.exec(sql"UPDATE run_metadata SET history_started_at_ns = ? WHERE singleton = 1",
            timestamp_ns())
          create_inspectability_tables(result.db)
          migrate_model_attempt_metadata(result.db)
          version = inspectability_store_schema_version
          exec_sql(result.db, "PRAGMA user_version = " & $version)
        if version < store_schema_version:
          create_work_dag_tables(result.db)
        exec_sql(result.db, "PRAGMA user_version = " & $store_schema_version)
        exec_sql(result.db, "COMMIT")
      except CatchableError:
        try: exec_sql(result.db, "ROLLBACK")
        except CatchableError: discard
        raise
  except CatchableError:
    result.close()
    raise

proc metadata*(store: VecherinkaStore): StoreMetadata =
  require_open(store)
  let row = store.db.getRow(sql"""SELECT run_id, workflow_id,
      workflow_fingerprint, workflow_manifest_json, codec_version,
      checkpoint_version
    FROM run_metadata WHERE singleton = 1""")
  if row.len < 6:
    raise newException(ValueError, "store has no run metadata")
  StoreMetadata(
    run_id: row[0], workflow_id: row[1], workflow_fingerprint: row[2],
    workflow_manifest_json: row[3], codec_version: parseInt(row[4]),
    checkpoint_version: parseInt(row[5]))

proc validate_status(status: string) =
  if status notin ["created", "running", "interrupted", "finished", "failed"]:
    raise newException(ValueError, "invalid run status: " & status)

proc validate_status_transition(previous, next: string) =
  validate_status(next)
  let allowed = previous == next or
    (previous == "created" and next in ["running", "interrupted", "failed"]) or
    (previous == "running" and next in ["interrupted", "finished", "failed"]) or
    (previous == "interrupted" and next in ["running", "failed"])
  if not allowed:
    raise newException(ValueError,
      "invalid run status transition: " & previous & " -> " & next)

proc set_status*(store: VecherinkaStore; status: string) =
  require_open(store)
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    let previous = store.db.getValue(sql"SELECT status FROM run_metadata WHERE singleton = 1")
    validate_status_transition(previous, status)
    store.db.exec(sql"UPDATE run_metadata SET status = ? WHERE singleton = 1", status)
    store.db.exec(sql"UPDATE checkpoint SET status = ? WHERE singleton = 1", status)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc status*(store: VecherinkaStore): string =
  require_open(store)
  store.db.getValue(sql"SELECT status FROM run_metadata WHERE singleton = 1")

proc close*(store: VecherinkaStore) =
  if store.isNil or store.closed:
    return
  store.db.close()
  store.db = nil
  store.closed = true

proc require_open(reader: VecherinkaReader) =
  if reader.isNil or reader.closed:
    raise newException(ValueError, "Vecherinka reader is closed")

proc open_vecherinka_reader*(database_path: Path): VecherinkaReader =
  if not fileExists($database_path):
    raise newException(IOError, "store does not exist: " & $database_path)
  new result
  result.database_path = Path(absolutePath($database_path))
  result.closed = false
  try:
    result.db = open($result.database_path, "", "", "")
    exec_sql(result.db, "PRAGMA query_only = ON")
    exec_sql(result.db, "PRAGMA busy_timeout = 1000")
  except CatchableError:
    if not result.db.isNil:
      result.db.close()
    result.db = nil
    result.closed = true
    raise

proc close*(reader: VecherinkaReader) =
  if reader.isNil or reader.closed:
    return
  reader.db.close()
  reader.db = nil
  reader.closed = true

proc start_execution*(store: VecherinkaStore; owner_token: string;
    owner_pid: int64): int64 =
  require_open(store)
  if owner_token.len == 0 or owner_pid <= 0:
    raise newException(ValueError, "execution owner identity is required")
  let now = timestamp_ns()
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    let previous = store.db.getValue(sql"""SELECT active_execution_id
      FROM run_metadata WHERE singleton = 1""")
    if previous.len > 0:
      let previous_id = parseBiggestInt(previous)
      if previous_id > 0:
        let previous_row = store.db.getRow(sql"""SELECT heartbeat_at_ns, ended_at_ns
          FROM run_execution WHERE execution_id = ?""", previous_id)
        if previous_row.len > 0 and previous_row[1] == "0" and
            now - parseBiggestInt(previous_row[0]) < execution_lease_timeout_ns:
          raise newException(ValueError,
            "SQLite run already has a live execution owner")
        store.db.exec(sql"""UPDATE conversation_event
          SET write_state = 'outcome_unknown'
          WHERE execution_id = ? AND direction = 'outgoing'
            AND write_state = 'attempted'""", previous_id)
        store.db.exec(sql"""INSERT INTO conversation_event(
            execution_id, kind, request_id, session_id, agent_id,
            details_json, timestamp_ns)
          SELECT execution_id, 'worker_session.state', request_id, session_id,
            agent_id, '{\"state\":\"interrupted\"}', ? FROM worker_session
          WHERE execution_id = ? AND state IN ('starting', 'working')""",
          now, previous_id)
        store.db.exec(sql"""UPDATE worker_session SET state = 'interrupted'
          WHERE execution_id = ? AND state IN ('starting', 'working')""",
          previous_id)
        store.db.exec(sql"""UPDATE run_execution SET ended_at_ns = ?
          WHERE execution_id = ? AND ended_at_ns = 0""", now, previous_id)
    store.db.exec(sql"""INSERT INTO run_execution(
        owner_token, owner_pid, started_at_ns, heartbeat_at_ns)
      VALUES(?, ?, ?, ?)""", owner_token, owner_pid, now, now)
    result = parseBiggestInt(store.db.getValue(sql"SELECT last_insert_rowid()"))
    store.db.exec(sql"UPDATE run_metadata SET active_execution_id = ? WHERE singleton = 1",
      result)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc heartbeat_execution*(store: VecherinkaStore; execution_id: int64) =
  require_open(store)
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    require_active_execution(store, execution_id)
    store.db.exec(sql"""UPDATE run_execution SET heartbeat_at_ns = ?
      WHERE execution_id = ? AND ended_at_ns = 0""", timestamp_ns(), execution_id)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc finish_execution*(store: VecherinkaStore; execution_id: int64) =
  require_open(store)
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    require_active_execution(store, execution_id)
    let now = timestamp_ns()
    store.db.exec(sql"""INSERT INTO conversation_event(
      execution_id, kind, request_id, session_id, agent_id, details_json,
      timestamp_ns)
    SELECT execution_id, 'worker_session.state', request_id, session_id,
      agent_id, '{\"state\":\"interrupted\"}', ? FROM worker_session
    WHERE execution_id = ? AND state IN ('starting', 'working')""",
      now, execution_id)
    store.db.exec(sql"""UPDATE worker_session SET state = 'interrupted'
      WHERE execution_id = ? AND state IN ('starting', 'working')""", execution_id)
    store.db.exec(sql"""UPDATE run_execution SET ended_at_ns = ?, heartbeat_at_ns = ?
      WHERE execution_id = ? AND ended_at_ns = 0""", now, now, execution_id)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc insert_workflow_graph(db: DbConn; nodes: openArray[WorkflowNode];
    edges: openArray[WorkflowEdge]) =
  for node in nodes:
    let existing = db.getRow(sql"""SELECT kind, expansion_id, details_json
        FROM workflow_node WHERE flow_key = ?""", node.flow_key)
    if existing.len > 0 and existing[0].len > 0:
      if existing[0] != node.kind or parseBiggestInt(existing[1]) != node.expansion_id or
          existing[2] != node.details_json:
        raise newException(ValueError,
          "workflow node changed for stable key: " & node.flow_key)
    else:
      db.exec(sql"""INSERT INTO workflow_node(
            flow_key, kind, expansion_id, details_json) VALUES(?, ?, ?, ?)""",
        node.flow_key, node.kind, node.expansion_id, node.details_json)
  for edge in edges:
    let existing = db.getRow(sql"""SELECT target_flow_key
        FROM workflow_edge WHERE source_flow_key = ? AND edge_kind = ?
          AND position = ? AND expansion_id = ?""",
      edge.source_flow_key, edge.edge_kind, edge.position, edge.expansion_id)
    if existing.len > 0 and existing[0].len > 0:
      if existing[0] != edge.target_flow_key:
        raise newException(ValueError,
          "workflow edge changed for stable source key: " & edge.source_flow_key)
    else:
      db.exec(sql"""INSERT INTO workflow_edge(
            source_flow_key, edge_kind, position, target_flow_key, expansion_id)
          VALUES(?, ?, ?, ?, ?)""", edge.source_flow_key, edge.edge_kind,
        edge.position, edge.target_flow_key, edge.expansion_id)

proc insert_workflow_expansion(db: DbConn; expansion: WorkflowExpansion) =
  let existing = db.getRow(sql"""SELECT parent_flow_key, input_artifact_id,
      root_flow_key, graph_signature FROM workflow_expansion
    WHERE expansion_id = ?""", expansion.expansion_id)
  if existing.len > 0 and existing[0].len > 0:
    if existing[0] != expansion.parent_flow_key or
        parseBiggestInt(existing[1]) != expansion.input_artifact_id or
        existing[2] != expansion.root_flow_key or
        existing[3] != expansion.graph_signature:
      raise newException(ValueError,
        "dynamic workflow graph changed for expansion " & $expansion.expansion_id)
  else:
    db.exec(sql"""INSERT INTO workflow_expansion(
        expansion_id, parent_flow_key, input_artifact_id, root_flow_key,
        graph_signature) VALUES(?, ?, ?, ?, ?)""",
      expansion.expansion_id, expansion.parent_flow_key,
      expansion.input_artifact_id, expansion.root_flow_key,
      expansion.graph_signature)

proc register_workflow_graph*(store: VecherinkaStore;
    nodes: openArray[WorkflowNode]; edges: openArray[WorkflowEdge];
    execution_id: int64 = 0) =
  require_open(store)
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    if execution_id > 0:
      require_active_execution(store, execution_id)
    insert_workflow_graph(store.db, nodes, edges)
    refresh_attempt_profiles(store.db, nodes)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc workflow_expansion*(store: VecherinkaStore;
    expansion_id: int64): Option[WorkflowExpansion] =
  require_open(store)
  let row = store.db.getRow(sql"""SELECT parent_flow_key, input_artifact_id,
      root_flow_key, graph_signature FROM workflow_expansion
    WHERE expansion_id = ?""", expansion_id)
  if row.len == 0 or row[0].len == 0:
    return none(WorkflowExpansion)
  some(WorkflowExpansion(expansion_id: expansion_id, parent_flow_key: row[0],
    input_artifact_id: parseBiggestInt(row[1]), root_flow_key: row[2],
    graph_signature: row[3]))

proc start_worker_session*(store: VecherinkaStore; request_id: string;
    execution_id: int64; agent_id: string): WorkerSession =
  require_open(store)
  if request_id.len == 0 or agent_id.len == 0:
    raise newException(ValueError, "worker session requires request and agent IDs")
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    require_active_execution(store, execution_id)
    let generation_text = store.db.getValue(sql"""SELECT COALESCE(MAX(generation), -1) + 1
      FROM worker_session WHERE request_id = ?""", request_id)
    result = WorkerSession(request_id: request_id, execution_id: execution_id,
      generation: parseInt(generation_text), agent_id: agent_id, state: "starting")
    store.db.exec(sql"""INSERT INTO worker_session(
      request_id, execution_id, generation, agent_id, state)
      VALUES(?, ?, ?, ?, ?)""", result.request_id, result.execution_id,
      result.generation, result.agent_id, result.state)
    result.session_id = parseBiggestInt(store.db.getValue(sql"SELECT last_insert_rowid()"))
    store.db.exec(sql"""INSERT INTO conversation_event(
      execution_id, kind, request_id, session_id, agent_id, details_json,
      timestamp_ns) VALUES(?, 'worker_session.state', ?, ?, ?, ?, ?)""",
      execution_id, request_id, result.session_id, agent_id,
      "{\"state\":\"starting\",\"generation\":" & $result.generation & "}",
      timestamp_ns())
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc find_session(store: VecherinkaStore; execution_id: int64;
    agent_id: string): Option[WorkerSession] =
  let row = store.db.getRow(sql"""SELECT session_id, request_id, generation,
      agent_id, thread_id, state FROM worker_session
    WHERE execution_id = ? AND agent_id = ?""", execution_id, agent_id)
  if row.len == 0 or row[0].len == 0:
    return none(WorkerSession)
  some(WorkerSession(session_id: parseBiggestInt(row[0]), request_id: row[1],
    execution_id: execution_id, generation: parseInt(row[2]), agent_id: row[3],
    thread_id: row[4], state: row[5]))

proc set_worker_thread*(store: VecherinkaStore; session_id: int64;
    thread_id: string) =
  require_open(store)
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    let session = store.db.getRow(sql"SELECT execution_id FROM worker_session WHERE session_id = ?",
      session_id)
    if session.len == 0 or session[0].len == 0:
      raise newException(ValueError, "worker session does not exist")
    require_active_execution(store, parseBiggestInt(session[0]))
    store.db.exec(sql"UPDATE worker_session SET thread_id = ?, state = 'working' WHERE session_id = ?",
      thread_id, session_id)
    store.db.exec(sql"""INSERT INTO conversation_event(
      execution_id, kind, request_id, session_id, agent_id, thread_id,
      details_json, timestamp_ns)
    SELECT execution_id, 'worker_session.state', request_id, session_id,
      agent_id, ?, '{\"state\":\"working\"}', ? FROM worker_session
      WHERE session_id = ?""", thread_id, timestamp_ns(), session_id)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc set_worker_state*(store: VecherinkaStore; session_id: int64; state: string) =
  require_open(store)
  if state notin ["starting", "working", "finished", "failed", "interrupted"]:
    raise newException(ValueError, "invalid worker session state: " & state)
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    let session = store.db.getRow(sql"SELECT execution_id FROM worker_session WHERE session_id = ?",
      session_id)
    if session.len == 0 or session[0].len == 0:
      raise newException(ValueError, "worker session does not exist")
    require_active_execution(store, parseBiggestInt(session[0]))
    store.db.exec(sql"""INSERT INTO conversation_event(
        execution_id, kind, request_id, session_id, agent_id, details_json,
        timestamp_ns)
      SELECT execution_id, 'worker_session.state', request_id, session_id,
        agent_id, ?, ? FROM worker_session WHERE session_id = ?""",
      "{\"state\":\"" & state & "\"}", timestamp_ns(), session_id)
    store.db.exec(sql"UPDATE worker_session SET state = ? WHERE session_id = ?",
      state, session_id)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc update_worker_session(db: DbConn; update: WorkerSessionUpdate) =
  if update.state notin ["starting", "working", "finished", "failed", "interrupted"]:
    raise newException(ValueError, "invalid worker session state: " & update.state)
  let row = db.getRow(sql"""SELECT execution_id, request_id, agent_id, state
    FROM worker_session WHERE session_id = ?""", update.session_id)
  if row.len == 0 or row[0].len == 0:
    raise newException(ValueError, "worker session does not exist")
  if row[3] == update.state:
    return
  db.exec(sql"""INSERT INTO conversation_event(
      execution_id, kind, request_id, session_id, agent_id, details_json,
      timestamp_ns)
    VALUES(?, 'worker_session.state', ?, ?, ?, ?, ?)""",
    parseBiggestInt(row[0]), row[1], update.session_id, row[2],
    "{\"state\":\"" & update.state & "\"}", timestamp_ns())
  db.exec(sql"UPDATE worker_session SET state = ? WHERE session_id = ?",
    update.state, update.session_id)

proc append_conversation_event*(store: VecherinkaStore;
    event: ConversationEvent): int64 =
  require_open(store)
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    require_active_execution(store, event.execution_id)
    var session_id: Option[int64]
    var request_id = event.request_id
    if event.session_id > 0:
      session_id = some(event.session_id)
    elif event.agent_id.len > 0:
      let session = find_session(store, event.execution_id, event.agent_id)
      if session.isSome:
        session_id = some(session.get.session_id)
        if request_id.len == 0:
          request_id = session.get.request_id
    if session_id.isNone and event.thread_id.len > 0:
      let row = store.db.getRow(sql"""SELECT session_id FROM worker_session
        WHERE execution_id = ? AND thread_id = ? ORDER BY session_id DESC LIMIT 1""",
        event.execution_id, event.thread_id)
      if row.len > 0 and row[0].len > 0:
        session_id = some(parseBiggestInt(row[0]))
    if event.rpc_id.len > 0 and
        (request_id.len == 0 or session_id.isNone):
      let correlated_direction = if event.direction == "incoming": "outgoing" else: "incoming"
      let row = store.db.getRow(sql"""SELECT request_id, session_id FROM conversation_event
        WHERE execution_id = ? AND rpc_id = ? AND direction = ?
        ORDER BY event_id DESC LIMIT 1""", event.execution_id, event.rpc_id,
        correlated_direction)
      if row.len > 0:
        if request_id.len == 0:
          request_id = row[0]
        if session_id.isNone and row[1].len > 0:
          session_id = some(parseBiggestInt(row[1]))
    let session_value = if session_id.isSome: "?" else: "NULL"
    let insert_sql = SqlQuery("""INSERT INTO conversation_event(
      execution_id, kind, direction, request_id, session_id, agent_id, rpc_id,
      thread_id, turn_id, raw_json, details_json, write_state, timestamp_ns)
    VALUES(?, ?, ?, ?, """ & session_value & """, ?, ?, ?, ?, ?, ?, ?, ?)""")
    let timestamp = if event.timestamp_ns == 0: timestamp_ns() else: event.timestamp_ns
    if session_id.isSome:
      store.db.exec(insert_sql, event.execution_id, event.kind, event.direction,
        request_id, session_id.get, event.agent_id, event.rpc_id, event.thread_id,
        event.turn_id, event.raw_json, event.details_json, event.write_state,
        timestamp)
    else:
      store.db.exec(insert_sql, event.execution_id, event.kind, event.direction,
        request_id, event.agent_id, event.rpc_id, event.thread_id, event.turn_id,
        event.raw_json, event.details_json, event.write_state, timestamp)
    result = parseBiggestInt(store.db.getValue(sql"SELECT last_insert_rowid()"))
    if event.direction == "incoming" and event.thread_id.len > 0 and
        session_id.isSome:
      store.db.exec(sql"UPDATE worker_session SET thread_id = ?, state = 'working' WHERE session_id = ?",
        event.thread_id, session_id.get)
      store.db.exec(sql"""INSERT INTO conversation_event(
          execution_id, kind, request_id, session_id, agent_id, thread_id,
          details_json, timestamp_ns)
        SELECT execution_id, 'worker_session.state', request_id, session_id,
          agent_id, ?, '{\"state\":\"working\"}', ? FROM worker_session
        WHERE session_id = ?""", event.thread_id, timestamp_ns(), session_id.get)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc set_conversation_write_state*(store: VecherinkaStore; event_id: int64;
    state, details_json: string = "") =
  require_open(store)
  if state notin ["write_returned", "write_raised"]:
    raise newException(ValueError, "invalid outgoing write state: " & state)
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    let execution_id = store.db.getValue(sql"SELECT execution_id FROM conversation_event WHERE event_id = ? AND write_state = 'attempted' AND direction = 'outgoing'",
      event_id)
    if execution_id.len == 0:
      raise newException(ValueError, "outgoing conversation event is not pending")
    require_active_execution(store, parseBiggestInt(execution_id))
    if details_json.len > 0:
      store.db.exec(sql"UPDATE conversation_event SET write_state = ?, details_json = ? WHERE event_id = ?",
        state, details_json, event_id)
    else:
      store.db.exec(sql"UPDATE conversation_event SET write_state = ? WHERE event_id = ?",
        state, event_id)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc insert_artifact(db: DbConn; artifact: StoredArtifact) =
  let artifact_id = as_sql_id(artifact.id)
  if artifact.codec_id.len == 0 or artifact.codec_version <= 0:
    raise newException(ValueError, "artifact codec identity is required")
  db.exec(sql"""INSERT INTO artifact(
      artifact_id, codec_id, codec_version, payload_text,
      operation, flow_kind, request_id) VALUES(?, ?, ?, ?, ?, ?, ?)""",
    artifact_id, artifact.codec_id, artifact.codec_version,
    artifact.payload_text, artifact.operation, artifact.flow_kind,
    artifact.request_id)

  for position, predecessor_id in artifact.predecessor_ids:
    db.exec(sql"INSERT INTO predecessor(artifact_id, position, predecessor_id) VALUES(?, ?, ?)",
      artifact_id, position, as_sql_id(predecessor_id))

proc insert_work_occurrence(db: DbConn; work: WorkOccurrence) =
  if work.work_id <= 0 or work.flow_key.len == 0 or work.kind.len == 0 or
      work.state notin ["queued", "running", "waiting", "completed", "failed"]:
    raise newException(ValueError, "invalid work occurrence")
  let exists = db.getValue(sql"SELECT EXISTS(SELECT 1 FROM work_occurrence WHERE work_id = ?)",
    work.work_id) == "1"
  let previous = db.getRow(sql"""SELECT flow_key, kind, input_artifact_id
    FROM work_occurrence WHERE work_id = ?""", work.work_id)
  if not exists:
    if work.output_artifact_id.isSome:
      db.exec(sql"""INSERT INTO work_occurrence(
        work_id, flow_key, kind, state, input_artifact_id, output_artifact_id,
        request_id, expansion_id, join_id, root_name, slot)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        work.work_id, work.flow_key, work.kind, work.state,
        work.input_artifact_id, work.output_artifact_id.get,
        work.request_id, work.expansion_id, work.join_id, work.root_name,
        work.slot)
    else:
      db.exec(sql"""INSERT INTO work_occurrence(
        work_id, flow_key, kind, state, input_artifact_id, output_artifact_id,
        request_id, expansion_id, join_id, root_name, slot)
        VALUES(?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?)""",
        work.work_id, work.flow_key, work.kind, work.state,
        work.input_artifact_id, work.request_id, work.expansion_id,
        work.join_id, work.root_name, work.slot)
  else:
    if previous[0] != work.flow_key or previous[1] != work.kind or
      parseBiggestInt(previous[2]) != work.input_artifact_id:
      raise newException(ValueError,
        "work occurrence identity changed: " & $work.work_id)
    let previous_state = db.getValue(sql"SELECT state FROM work_occurrence WHERE work_id = ?",
      work.work_id)
    let valid_state_change = previous_state == work.state or
      (previous_state == "queued" and work.state in ["running", "waiting", "completed", "failed"]) or
      (previous_state == "running" and work.state in ["waiting", "completed", "failed"]) or
      (previous_state == "waiting" and work.state in ["running", "completed", "failed"])
    if not valid_state_change:
      raise newException(ValueError, "invalid work state transition: " &
        previous_state & " -> " & work.state)
    if work.output_artifact_id.isSome:
      db.exec(sql"""UPDATE work_occurrence SET state = ?,
        output_artifact_id = ?, request_id = ?, expansion_id = ?, join_id = ?,
        root_name = ?, slot = ? WHERE work_id = ?""",
        work.state, work.output_artifact_id.get, work.request_id,
        work.expansion_id, work.join_id, work.root_name, work.slot,
        work.work_id)
    else:
      db.exec(sql"""UPDATE work_occurrence SET state = ?,
        request_id = ?, expansion_id = ?, join_id = ?, root_name = ?,
        slot = ? WHERE work_id = ?""",
        work.state, work.request_id, work.expansion_id, work.join_id,
        work.root_name, work.slot, work.work_id)

proc insert_work_edge(db: DbConn; edge: WorkEdge) =
  if edge.source_work_id <= 0 or edge.target_work_id <= edge.source_work_id or
      edge.relation.len == 0 or edge.position < 0:
    raise newException(ValueError, "work DAG edges must point forward")
  db.exec(sql"""INSERT OR IGNORE INTO work_edge(
    source_work_id, target_work_id, relation, position) VALUES(?, ?, ?, ?)""",
    edge.source_work_id, edge.target_work_id, edge.relation, edge.position)

proc allowed_attempt_transition(previous, next: StoreAttemptState): bool =
  if previous == next:
    return true
  case previous
  of sasPrepared:
    next in {sasSubmitted, sasUnknown, sasOutputReceived, sasFailed}
  of sasSubmitted:
    next in {sasUnknown, sasOutputReceived, sasCommitted, sasFailed}
  of sasUnknown:
    next in {sasSubmitted, sasOutputReceived, sasCommitted, sasFailed}
  of sasOutputReceived:
    next in {sasCommitted, sasFailed}
  of sasCommitted, sasFailed:
    false

proc store_attempt(store: VecherinkaStore; attempt: StoreAttempt) =
  if attempt.request_id.len == 0:
    raise newException(ValueError, "model attempt ID cannot be empty")
  let existing = store.db.getRow(sql"""SELECT state, payload_text
    FROM model_attempt WHERE request_id = ?""", attempt.request_id)
  if existing.len > 0 and existing[0].len > 0:
    var previous: StoreAttemptState
    try:
      previous = parseEnum[StoreAttemptState](existing[0])
    except ValueError:
      raise newException(ValueError, "invalid stored model-attempt state")
    if not allowed_attempt_transition(previous, attempt.state):
      raise newException(ValueError,
        "invalid model-attempt transition: " & $previous & " -> " & $attempt.state)
    if previous == attempt.state and existing[1] != attempt.payload_text:
      raise newException(ValueError,
        "same-state model attempt update changed its payload")
    if previous == attempt.state:
      return
    let output_update = if attempt.output_artifact_id.isSome:
      "output_artifact_id = ?, " else: ""
    let update_sql = SqlQuery("""UPDATE model_attempt SET state = ?, payload_text = ?,
        flow_key = CASE WHEN ? = '' THEN flow_key ELSE ? END,
        input_artifact_id = CASE WHEN ? = '' THEN input_artifact_id ELSE ? END,
        reserved_output_artifact_id = CASE WHEN ? = '' THEN reserved_output_artifact_id ELSE ? END,
        """ & output_update & """model = CASE WHEN ? = '' THEN model ELSE ? END,
        effort = CASE WHEN ? = '' THEN effort ELSE ? END
      WHERE request_id = ?""")
    if attempt.output_artifact_id.isSome:
      store.db.exec(update_sql, $attempt.state, attempt.payload_text,
        attempt.flow_key, attempt.flow_key,
        attempt.flow_key, attempt.input_artifact_id,
        attempt.flow_key, attempt.reserved_output_artifact_id,
        attempt.output_artifact_id.get,
        attempt.model, attempt.model, attempt.effort, attempt.effort,
        attempt.request_id)
    else:
      store.db.exec(update_sql, $attempt.state, attempt.payload_text,
        attempt.flow_key, attempt.flow_key,
        attempt.flow_key, attempt.input_artifact_id,
        attempt.flow_key, attempt.reserved_output_artifact_id,
        attempt.model, attempt.model, attempt.effort, attempt.effort,
        attempt.request_id)
  else:
    if attempt.state != sasPrepared:
      raise newException(ValueError,
        "model attempts must be created in prepared state")
    if attempt.output_artifact_id.isSome:
      store.db.exec(sql"""INSERT INTO model_attempt(
          request_id, state, payload_text, flow_key, input_artifact_id,
          reserved_output_artifact_id, output_artifact_id, model, effort)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        attempt.request_id, $attempt.state, attempt.payload_text,
        attempt.flow_key, attempt.input_artifact_id,
        attempt.reserved_output_artifact_id, attempt.output_artifact_id.get,
        attempt.model, attempt.effort)
    else:
      store.db.exec(sql"""INSERT INTO model_attempt(
          request_id, state, payload_text, flow_key, input_artifact_id,
          reserved_output_artifact_id, output_artifact_id, model, effort)
        VALUES(?, ?, ?, ?, ?, ?, NULL, ?, ?)""",
        attempt.request_id, $attempt.state, attempt.payload_text,
        attempt.flow_key, attempt.input_artifact_id,
        attempt.reserved_output_artifact_id, attempt.model, attempt.effort)
  store.db.exec(sql"""INSERT INTO conversation_event(
      execution_id, kind, request_id, details_json, timestamp_ns)
    SELECT active_execution_id, 'model_attempt.state', ?, ?, ?
    FROM run_metadata WHERE singleton = 1 AND active_execution_id IS NOT NULL""",
    attempt.request_id, "{\"state\":\"" & $attempt.state & "\"}", timestamp_ns())

proc commit_transition*(store: VecherinkaStore;
    expected_previous_sequence: int64;
    artifacts: openArray[StoredArtifact]; checkpoint: StoreCheckpoint;
    attempts: openArray[StoreAttempt] = [];
    graph_nodes: openArray[WorkflowNode] = [];
    graph_edges: openArray[WorkflowEdge] = [];
    expansions: openArray[WorkflowExpansion] = [];
    session_updates: openArray[WorkerSessionUpdate] = [];
    execution_id: int64 = 0;
    work_occurrences: openArray[WorkOccurrence] = [];
    work_edges: openArray[WorkEdge] = []) =
  ## All values and this checkpoint are one SQLite commit. A duplicate ID or
  ## stale writer rolls back every row in the batch.
  require_open(store)
  if expected_previous_sequence < -1 or
      checkpoint.sequence != expected_previous_sequence + 1:
    raise newException(ValueError,
      "checkpoint sequence must immediately follow its expected predecessor")
  if checkpoint.format_version != checkpoint_format_version:
    raise newException(ValueError, "unsupported checkpoint format version")
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    if execution_id > 0:
      require_active_execution(store, execution_id)
    let previous = store.db.getValue(sql"SELECT sequence FROM checkpoint WHERE singleton = 1")
    let actual_previous = if previous.len > 0: parseBiggestInt(previous) else: -1'i64
    if actual_previous != expected_previous_sequence:
      raise newException(ValueError, "checkpoint changed since transition was prepared")
    let previous_status = store.db.getValue(
      sql"SELECT status FROM run_metadata WHERE singleton = 1")
    validate_status_transition(previous_status, checkpoint.status)
    for artifact in artifacts:
      insert_artifact(store.db, artifact)
    insert_workflow_graph(store.db, graph_nodes, graph_edges)
    refresh_attempt_profiles(store.db, graph_nodes)
    for expansion in expansions:
      insert_workflow_expansion(store.db, expansion)
    for attempt in attempts:
      store.store_attempt(attempt)
    for update in session_updates:
      update_worker_session(store.db, update)
    for work in work_occurrences:
      insert_work_occurrence(store.db, work)
    for edge in work_edges:
      insert_work_edge(store.db, edge)
    store.db.exec(sql"""INSERT OR REPLACE INTO checkpoint(
        singleton, sequence, format_version, status, payload_text)
      VALUES(1, ?, ?, ?, ?)""",
      checkpoint.sequence, checkpoint.format_version, checkpoint.status,
      checkpoint.payload_text)
    store.db.exec(sql"UPDATE run_metadata SET status = ? WHERE singleton = 1",
      checkpoint.status)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(store.db, "ROLLBACK")
      except CatchableError: discard

proc artifact*(store: VecherinkaStore; id: uint64): Option[StoredArtifact] =
  require_open(store)
  let artifact_id = as_sql_id(id)
  let rows = store.db.getAllRows(
    sql"""SELECT codec_id, codec_version, payload_text, operation, flow_kind,
        request_id FROM artifact WHERE artifact_id = ?""",
    artifact_id)
  if rows.len == 0:
    return none(StoredArtifact)

  result = some(StoredArtifact(id: id, codec_id: rows[0][0],
    codec_version: parseInt(rows[0][1]), payload_text: rows[0][2],
    operation: rows[0][3], flow_kind: rows[0][4], request_id: rows[0][5]))
  for row in store.db.getAllRows(sql"SELECT predecessor_id FROM predecessor WHERE artifact_id = ? ORDER BY position",
      artifact_id):
    result.get.predecessor_ids.add(as_artifact_id(row[0]))
proc artifact_for_request*(store: VecherinkaStore;
    request_id: string): Option[StoredArtifact] =
  require_open(store)
  if request_id.len == 0:
    raise newException(ValueError, "model request ID cannot be empty")
  let row = store.db.getRow(sql"SELECT artifact_id FROM artifact WHERE request_id = ?",
    request_id)
  if row.len == 0 or row[0].len == 0:
    return none(StoredArtifact)
  artifact(store, as_artifact_id(row[0]))

proc attempt*(store: VecherinkaStore; request_id: string): Option[StoreAttempt] =
  require_open(store)
  let row = store.db.getRow(sql"""SELECT state, payload_text, flow_key,
      input_artifact_id, reserved_output_artifact_id, output_artifact_id,
      model, effort FROM model_attempt
    WHERE request_id = ?""", request_id)
  if row.len == 0 or row[0].len == 0:
    return none(StoreAttempt)
  var state: StoreAttemptState
  try:
    state = parseEnum[StoreAttemptState](row[0])
  except ValueError:
    raise newException(ValueError, "invalid stored model-attempt state")
  some(StoreAttempt(request_id: request_id, state: state,
    payload_text: row[1], flow_key: row[2],
    input_artifact_id: if row[3].len == 0: 0 else: parseBiggestInt(row[3]),
    reserved_output_artifact_id: if row[4].len == 0: 0 else: parseBiggestInt(row[4]),
    output_artifact_id: if row[5].len == 0: none(int64)
      else: some(parseBiggestInt(row[5])),
    model: row[6], effort: row[7]))

proc work_occurrence*(store: VecherinkaStore;
    work_id: uint64): Option[WorkOccurrence] =
  require_open(store)
  let row = store.db.getRow(sql"""SELECT flow_key, kind, state,
      input_artifact_id, output_artifact_id, request_id, expansion_id,
      join_id, root_name, slot FROM work_occurrence WHERE work_id = ?""",
    int64(work_id))
  if row.len == 0 or row[0].len == 0:
    return none(WorkOccurrence)
  some(WorkOccurrence(work_id: int64(work_id), flow_key: row[0], kind: row[1],
    state: row[2], input_artifact_id: parseBiggestInt(row[3]),
    output_artifact_id: if row[4].len == 0: none(int64)
      else: some(parseBiggestInt(row[4])),
    request_id: row[5], expansion_id: parseBiggestInt(row[6]),
    join_id: parseBiggestInt(row[7]), root_name: row[8], slot: parseInt(row[9])))

proc work_occurrences*(store: VecherinkaStore): seq[WorkOccurrence] =
  require_open(store)
  for row in store.db.getAllRows(sql"""SELECT work_id, flow_key, kind,
      state, input_artifact_id, output_artifact_id, request_id, expansion_id,
      join_id, root_name, slot FROM work_occurrence ORDER BY work_id"""):
    result.add WorkOccurrence(work_id: parseBiggestInt(row[0]),
      flow_key: row[1], kind: row[2], state: row[3],
      input_artifact_id: parseBiggestInt(row[4]),
      output_artifact_id: if row[5].len == 0: none(int64)
        else: some(parseBiggestInt(row[5])),
      request_id: row[6], expansion_id: parseBiggestInt(row[7]),
      join_id: parseBiggestInt(row[8]), root_name: row[9], slot: parseInt(row[10]))

proc work_edges*(store: VecherinkaStore): seq[WorkEdge] =
  require_open(store)
  for row in store.db.getAllRows(sql"""SELECT source_work_id,
      target_work_id, relation, position FROM work_edge
      ORDER BY source_work_id, target_work_id, relation, position"""):
    result.add WorkEdge(source_work_id: parseBiggestInt(row[0]),
      target_work_id: parseBiggestInt(row[1]), relation: row[2],
      position: parseInt(row[3]))

proc checkpoint*(store: VecherinkaStore): Option[StoreCheckpoint] =
  require_open(store)
  let row = store.db.getRow(sql"""SELECT sequence, format_version, status,
      payload_text
    FROM checkpoint WHERE singleton = 1""")
  if row.len == 0 or row[0].len == 0:
    return none(StoreCheckpoint)
  some(StoreCheckpoint(sequence: parseBiggestInt(row[0]),
    format_version: parseInt(row[1]), status: row[2], payload_text: row[3]))

proc poll*(reader: VecherinkaReader; after_event_id: int64;
    limit: int = 256): StorePoll =
  require_open(reader)
  if after_event_id < 0 or limit <= 0 or limit > 10_000:
    raise newException(ValueError, "invalid live-reader cursor or page size")
  exec_sql(reader.db, "BEGIN")
  var committed = false
  try:
    let row = reader.db.getRow(sql"""SELECT r.status,
        COALESCE(c.sequence, -1), COALESCE(c.payload_text, ''),
        COALESCE(e.execution_id, 0), COALESCE(e.heartbeat_at_ns, 0),
        r.history_started_at_ns
      FROM run_metadata r
      LEFT JOIN checkpoint c ON c.singleton = r.singleton
      LEFT JOIN run_execution e ON e.execution_id = r.active_execution_id
      WHERE r.singleton = 1""")
    if row.len < 6:
      raise newException(ValueError, "store has no run snapshot")
    result.snapshot = StoreSnapshot(status: row[0],
      checkpoint_sequence: parseBiggestInt(row[1]),
      checkpoint_payload: row[2], execution_id: parseBiggestInt(row[3]),
      heartbeat_at_ns: parseBiggestInt(row[4]),
      history_started_at_ns: parseBiggestInt(row[5]))
    result.last_event_id = after_event_id
    for item in reader.db.getAllRows(sql"""SELECT event_id, execution_id, kind,
        direction, request_id, COALESCE(session_id, 0), agent_id, rpc_id,
        thread_id, turn_id, raw_json, details_json, write_state, timestamp_ns
      FROM conversation_event WHERE event_id > ? ORDER BY event_id LIMIT ?""",
      after_event_id, limit):
      let event_id = parseBiggestInt(item[0])
      result.events.add ConversationEvent(event_id: event_id,
        execution_id: parseBiggestInt(item[1]), kind: item[2], direction: item[3],
        request_id: item[4], session_id: parseBiggestInt(item[5]),
        agent_id: item[6], rpc_id: item[7], thread_id: item[8], turn_id: item[9],
        raw_json: item[10], details_json: item[11], write_state: item[12],
        timestamp_ns: parseBiggestInt(item[13]))
      result.last_event_id = event_id
    exec_sql(reader.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try: exec_sql(reader.db, "ROLLBACK")
      except CatchableError: discard
