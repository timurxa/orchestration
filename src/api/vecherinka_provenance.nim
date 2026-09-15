## Persistent artifact provenance storage and path-based reader API.
##
## This module intentionally exposes no database-driver types. Runtime code
## uses ProvenanceStore; tools and RSI consumers use ProvenanceReader.

## `db_connector/db_sqlite` currently needs this import in Nim 2.3.x so its
## blob-copy implementation can resolve copyMem during module analysis.
{.warning[UnusedImport]: off.}
import std/algorithm
{.warning[UnusedImport]: on.}
import std/[options, os, paths, sequtils, strutils, times]
import db_connector/db_sqlite

type
  ProvenanceStore* = ref object
    database_path*: Path
    run_dir*: Path
    db: DbConn
    next_commit_seq: int64
    closed: bool

  ProvenanceReader* = ref object
    database_path*: Path
    run_dir*: Path
    db: DbConn
    closed: bool

  ArtifactProvenance* = object
    path*: Path
    predecessors*: seq[Path]
    children*: seq[Path]

  ProvenanceRun* = object
    run_dir*: Path
    status*: string
    started_at_ns*: int64
    finished_at_ns*: int64
    last_commit_seq*: int64

const schema_statements = [
  "PRAGMA foreign_keys = ON",
  "PRAGMA journal_mode = WAL",
  """CREATE TABLE IF NOT EXISTS run (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);""",
  """CREATE TABLE IF NOT EXISTS artifact (
  path TEXT PRIMARY KEY,
  commit_seq INTEGER NOT NULL,
  committed_at_ns INTEGER NOT NULL
);""",
  """CREATE TABLE IF NOT EXISTS edge (
  child_path TEXT NOT NULL,
  predecessor_path TEXT NOT NULL,
  position INTEGER NOT NULL,
  PRIMARY KEY (child_path, position),
  FOREIGN KEY (child_path) REFERENCES artifact(path),
  FOREIGN KEY (predecessor_path) REFERENCES artifact(path)
);""",
  "CREATE INDEX IF NOT EXISTS edge_predecessor_idx ON edge(predecessor_path)",
  "CREATE INDEX IF NOT EXISTS edge_child_idx ON edge(child_path)"
]

proc unix_ns(): int64 =
  getTime().toUnix() * 1_000_000_000'i64

proc normalized_path(path: Path): string =
  ## `expandFilename` requires the target to exist; database files do not
  ## exist yet during run initialization, so use lexical absolutization.
  absolutePath($path)

proc stored_path(run_dir, artifact_dir: Path): string =
  let absolute_artifact = normalized_path(artifact_dir)
  let absolute_run = normalized_path(run_dir)
  if Path(absolute_artifact).isRelativeTo(Path(absolute_run)):
    relativePath(absolute_artifact, absolute_run)
  else:
    ## The input artifact normally lives outside run_dir. Keeping it absolute
    ## preserves its meaning instead of turning it into a fragile ../ path.
    absolute_artifact

proc resolved_path(run_dir: Path; stored: string): Path =
  if isAbsolute(stored):
    Path(stored)
  else:
    run_dir / Path(stored)

proc exec_sql(database: DbConn; statement: string) =
  database.exec(SqlQuery(statement))

proc set_run_value(store: ProvenanceStore; key, value: string) =
  store.db.exec(
    sql"INSERT OR REPLACE INTO run(key, value) VALUES(?, ?)", key, value)

proc run_value(database: DbConn; key: string): string =
  database.getValue(sql"SELECT value FROM run WHERE key = ?", key)

proc open_provenance_store*(database_path, run_dir: Path): ProvenanceStore =
  if $database_path == "" or $run_dir == "":
    raise newException(ValueError, "provenance database and run directory are required")
  new result
  result.database_path = Path(normalized_path(database_path))
  result.run_dir = Path(normalized_path(run_dir))
  result.closed = false
  try:
    result.db = open($result.database_path, "", "", "")
    for statement in schema_statements:
      exec_sql(result.db, statement)
    set_run_value(result, "schema_version", "1")
    set_run_value(result, "run_dir", $result.run_dir)
    set_run_value(result, "status", "running")
    set_run_value(result, "started_at_ns", $unix_ns())
    set_run_value(result, "finished_at_ns", "")
    set_run_value(result, "last_commit_seq", "0")
  except CatchableError:
    if not result.db.isNil:
      result.db.close()
    result.db = nil
    raise

proc close*(store: ProvenanceStore) =
  if store.isNil or store.closed:
    return
  store.db.close()
  store.db = nil
  store.closed = true

proc set_status*(store: ProvenanceStore; status: string) =
  if store.isNil or store.closed:
    raise newException(ValueError, "provenance store is closed")
  set_run_value(store, "status", status)
  set_run_value(store, "finished_at_ns",
    if status == "running": "" else: $unix_ns())

proc record_artifact*(store: ProvenanceStore; artifact_dir: Path;
    predecessor_dirs: seq[Path]) =
  if store.isNil or store.closed:
    raise newException(ValueError, "provenance store is closed")

  let child_path = stored_path(store.run_dir, artifact_dir)
  var predecessor_paths: seq[string] = @[]
  for predecessor_dir in predecessor_dirs:
    predecessor_paths.add(stored_path(store.run_dir, predecessor_dir))

  inc store.next_commit_seq
  let commit_seq = store.next_commit_seq
  let committed_at = unix_ns()
  exec_sql(store.db, "BEGIN IMMEDIATE")
  var committed = false
  try:
    var artifact_statement = store.db.prepare(
      "INSERT INTO artifact(path, commit_seq, committed_at_ns) VALUES(?, ?, ?)")
    try:
      artifact_statement.bindParams(child_path, commit_seq, committed_at)
      if not store.db.tryExec(artifact_statement):
        dbError(store.db)
    finally:
      finalize(artifact_statement)

    for position, predecessor_path in predecessor_paths:
      var edge_statement = store.db.prepare(
        "INSERT INTO edge(child_path, predecessor_path, position) VALUES(?, ?, ?)")
      try:
        edge_statement.bindParams(child_path, predecessor_path, position)
        if not store.db.tryExec(edge_statement):
          dbError(store.db)
      finally:
        finalize(edge_statement)

    set_run_value(store, "last_commit_seq", $commit_seq)
    exec_sql(store.db, "COMMIT")
    committed = true
  finally:
    if not committed:
      try:
        exec_sql(store.db, "ROLLBACK")
      except CatchableError:
        discard

proc openProvenance*(database_path: Path): ProvenanceReader =
  if $database_path == "":
    raise newException(ValueError, "provenance database path is required")
  new result
  result.database_path = Path(normalized_path(database_path))
  result.run_dir = Path(normalized_path(Path(splitFile($result.database_path).dir)))
  result.closed = false
  try:
    result.db = open($result.database_path, "", "", "")
  except CatchableError:
    result.db = nil
    raise

proc close*(reader: ProvenanceReader) =
  if reader.isNil or reader.closed:
    return
  reader.db.close()
  reader.db = nil
  reader.closed = true

proc require_open(reader: ProvenanceReader) =
  if reader.isNil or reader.closed:
    raise newException(ValueError, "provenance reader is closed")

proc runInfo*(reader: ProvenanceReader): ProvenanceRun =
  require_open(reader)
  result.run_dir = reader.run_dir
  result.status = run_value(reader.db, "status")
  result.started_at_ns = parseInt(run_value(reader.db, "started_at_ns"))
  let finished = run_value(reader.db, "finished_at_ns")
  result.finished_at_ns = if finished.len == 0: 0 else: parseInt(finished)
  result.last_commit_seq = parseInt(run_value(reader.db, "last_commit_seq"))

proc query_paths(database: DbConn; query, value: string): seq[string] =
  for row in database.getAllRows(SqlQuery(query), value):
    if row.len > 0:
      result.add(row[0])

proc stored_artifact_path(reader: ProvenanceReader; path: Path): string =
  if not isAbsolute($path):
    $path
  else:
    stored_path(reader.run_dir, path)

proc artifact*(reader: ProvenanceReader; path: Path): Option[ArtifactProvenance] =
  require_open(reader)
  let stored = stored_artifact_path(reader, path)
  let found_path = reader.db.getValue(
    sql"SELECT path FROM artifact WHERE path = ?", stored)
  if found_path.len == 0:
    return none(ArtifactProvenance)
  some(ArtifactProvenance(
    path: resolved_path(reader.run_dir, stored),
    predecessors: query_paths(reader.db,
      "SELECT predecessor_path FROM edge WHERE child_path = ? ORDER BY position",
      stored).mapIt(resolved_path(reader.run_dir, it)),
    children: query_paths(reader.db,
      "SELECT child_path FROM edge WHERE predecessor_path = ? ORDER BY child_path, position",
      stored).mapIt(resolved_path(reader.run_dir, it))))

proc artifact_paths(reader: ProvenanceReader;
    minimum_commit_seq: int64): seq[string] =
  for row in reader.db.getAllRows(
      sql"SELECT path FROM artifact WHERE commit_seq > ? ORDER BY commit_seq",
      minimum_commit_seq):
    if row.len > 0:
      result.add(row[0])

proc artifactsAfter*(reader: ProvenanceReader;
    commit_seq: int64): seq[ArtifactProvenance] =
  require_open(reader)
  for path in artifact_paths(reader, commit_seq):
    let value = artifact(reader, resolved_path(reader.run_dir, path))
    if value.isSome:
      result.add(value.get)

proc artifacts*(reader: ProvenanceReader): seq[ArtifactProvenance] =
  artifactsAfter(reader, 0)

proc roots*(reader: ProvenanceReader): seq[Path] =
  require_open(reader)
  for value in artifacts(reader):
    if value.predecessors.len == 0:
      result.add(value.path)

proc leaves*(reader: ProvenanceReader): seq[Path] =
  require_open(reader)
  for value in artifacts(reader):
    if value.children.len == 0:
      result.add(value.path)
