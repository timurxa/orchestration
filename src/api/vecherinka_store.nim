## Low-level SQLite authority for durable Vecherinka run values.
## Payload text and file bytes live in SQLite; each transition can commit
## artifact values, ordered predecessor IDs, and its checkpoint atomically.

{.warning[UnusedImport]: off.}
import std/algorithm
{.warning[UnusedImport]: on.}
import std/[options, os, paths, strutils]
import db_connector/db_sqlite
import ./vecherinka_blob

type
  VecherinkaStore* = ref object
    database_path*: Path
    db: DbConn
    closed: bool

  StoreFile* = object
    name*: string
    bytes*: seq[byte]

  StoredArtifact* = object
    id*: uint64
    codec_id*: string
    codec_version*: int
    payload_text*: string
    predecessor_ids*: seq[uint64]
    operation*: string
    flow_kind*: string
    request_id*: string
    files*: seq[StoreFile]

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

  StoreCheckpoint* = object
    sequence*: int64
    format_version*: int
    status*: string
    payload_text*: string

const
  store_schema_version* = 5
  checkpoint_format_version* = 2

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
      status TEXT NOT NULL
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
    exec_sql(store.db, """CREATE TABLE artifact_file (
      artifact_id INTEGER NOT NULL REFERENCES artifact(artifact_id),
      name TEXT NOT NULL,
      bytes BLOB NOT NULL,
      PRIMARY KEY (artifact_id, name)
    )""")
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
      payload_text TEXT NOT NULL
    )""")
    store.db.exec(sql"""INSERT INTO run_metadata(
        singleton, run_id, workflow_id, workflow_fingerprint,
        workflow_manifest_json, codec_version, checkpoint_version, status)
      VALUES(1, ?, ?, ?, ?, ?, ?, 'created')""",
      metadata.run_id, metadata.workflow_id, metadata.workflow_fingerprint,
      metadata.workflow_manifest_json,
      metadata.codec_version, metadata.checkpoint_version)
    exec_sql(store.db, "PRAGMA user_version = 5")
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
    let version = result.db.getValue(sql"PRAGMA user_version")
    if version.len == 0 or parseInt(version) != store_schema_version:
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

proc bind_file(db: DbConn; artifact_id: int64; file: StoreFile) =
  if file.name.len == 0:
    raise newException(ValueError, "artifact file name cannot be empty")
  let normalized_name = normalizeRelativePath(file.name)
  if file.bytes.len == 0:
    db.exec(sql"INSERT INTO artifact_file(artifact_id, name, bytes) VALUES(?, ?, zeroblob(0))",
      artifact_id, normalized_name)
  else:
    var statement = db.prepare(
      "INSERT INTO artifact_file(artifact_id, name, bytes) VALUES(?, ?, ?)")
    try:
      statement.bindParams(artifact_id, normalized_name, file.bytes)
      if not db.tryExec(statement): dbError(db)
    finally:
      finalize(statement)

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

  var file_names: seq[string] = @[]
  for file in artifact.files:
    let normalized_name = normalizeRelativePath(file.name)
    if normalized_name in file_names:
      raise newException(ValueError, "duplicate artifact file name: " & file.name)
    file_names.add(normalized_name)
  for index, name in file_names:
    for other_index, other in file_names:
      if index != other_index and other.startsWith(name & "/"):
        raise newException(ValueError,
          "artifact file is also used as a directory: " & name)
  for index, file in artifact.files:
    bind_file(db, artifact_id,
      StoreFile(name: file_names[index], bytes: file.bytes))

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
    store.db.exec(sql"""UPDATE model_attempt SET state = ?, payload_text = ?
      WHERE request_id = ?""", $attempt.state, attempt.payload_text,
      attempt.request_id)
  else:
    if attempt.state != sasPrepared:
      raise newException(ValueError,
        "model attempts must be created in prepared state")
    store.db.exec(sql"""INSERT INTO model_attempt(
        request_id, state, payload_text) VALUES(?, ?, ?)""",
      attempt.request_id, $attempt.state, attempt.payload_text)

proc commit_transition*(store: VecherinkaStore;
    expected_previous_sequence: int64;
    artifacts: openArray[StoredArtifact]; checkpoint: StoreCheckpoint;
    attempts: openArray[StoreAttempt] = []) =
  ## All values and this checkpoint are one SQLite commit. A duplicate ID,
  ## duplicate file, or stale writer rolls back every row in the batch.
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
    let previous = store.db.getValue(sql"SELECT sequence FROM checkpoint WHERE singleton = 1")
    let actual_previous = if previous.len > 0: parseBiggestInt(previous) else: -1'i64
    if actual_previous != expected_previous_sequence:
      raise newException(ValueError, "checkpoint changed since transition was prepared")
    let previous_status = store.db.getValue(
      sql"SELECT status FROM run_metadata WHERE singleton = 1")
    validate_status_transition(previous_status, checkpoint.status)
    for artifact in artifacts:
      insert_artifact(store.db, artifact)
    for attempt in attempts:
      store.store_attempt(attempt)
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
  for row in store.db.getAllRows(sql"SELECT name, bytes FROM artifact_file WHERE artifact_id = ? ORDER BY name",
      artifact_id):
    var bytes = newSeq[byte](row[1].len)
    for index, value in row[1]:
      bytes[index] = byte(value)
    result.get.files.add(StoreFile(name: row[0], bytes: bytes))

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
  let row = store.db.getRow(sql"""SELECT state, payload_text FROM model_attempt
    WHERE request_id = ?""", request_id)
  if row.len == 0 or row[0].len == 0:
    return none(StoreAttempt)
  var state: StoreAttemptState
  try:
    state = parseEnum[StoreAttemptState](row[0])
  except ValueError:
    raise newException(ValueError, "invalid stored model-attempt state")
  some(StoreAttempt(request_id: request_id, state: state,
    payload_text: row[1]))

proc checkpoint*(store: VecherinkaStore): Option[StoreCheckpoint] =
  require_open(store)
  let row = store.db.getRow(sql"""SELECT sequence, format_version, status,
      payload_text
    FROM checkpoint WHERE singleton = 1""")
  if row.len == 0 or row[0].len == 0:
    return none(StoreCheckpoint)
  some(StoreCheckpoint(sequence: parseBiggestInt(row[0]),
    format_version: parseInt(row[1]), status: row[2], payload_text: row[3]))
