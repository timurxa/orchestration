# SQLite provenance plan

## Goal

Persist each run's artifact provenance in a SQLite database located inside
that run's artifact directory. The database must support simple post-run
inspection now and incremental consumers such as an RSI loop later.

This plan intentionally does not store artifact payloads. Payloads remain in
the existing artifact directories and files. SQLite stores the graph's
identity and relationships.

## Decisions

- Use `run_dir`, not `runtime_dir`, for the database location. `run_dir` is
  the unique directory containing `artifact-*` directories; `runtime_dir` is
  currently the process working directory.
- Name the file `vecherinka_provenance.sqlite3`.
- Store artifact paths relative to `run_dir`. The reader resolves them to
  usable paths. This keeps a run movable as one directory tree.
- Persist only direct predecessor edges. Children are queried from those
  edges rather than stored redundantly.
- Preserve predecessor order and duplicates with an edge position.
- `register_artifact` is the canonical persistence point. Reserved artifacts
  do not appear in the graph until they are actually registered.
- The runtime coordinator thread is the sole SQLite writer. Reader threads do
  not touch the database connection.
- SQLite is required for normal runs. Database initialization, write, or
  close errors should fail the run instead of silently producing incomplete
  provenance.
- Keep structured JSONL logging as diagnostics; SQLite becomes the canonical
  provenance store.

## Database schema

Create the schema when the run starts:

```sql
CREATE TABLE run (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE artifact (
  path TEXT PRIMARY KEY,
  commit_seq INTEGER NOT NULL,
  committed_at_ns INTEGER NOT NULL
);

CREATE TABLE edge (
  child_path TEXT NOT NULL,
  predecessor_path TEXT NOT NULL,
  position INTEGER NOT NULL,
  PRIMARY KEY (child_path, position),
  FOREIGN KEY (child_path) REFERENCES artifact(path),
  FOREIGN KEY (predecessor_path) REFERENCES artifact(path)
);

CREATE INDEX edge_predecessor_idx ON edge(predecessor_path);
CREATE INDEX edge_child_idx ON edge(child_path);
```

The `run` table should contain at least:

- `schema_version`
- `run_dir`
- `status` (`running`, `finished`, `failed`, or `aborted`)
- `started_at_ns`
- `finished_at_ns`
- `last_commit_seq`

Enable foreign keys and use WAL mode. WAL allows an RSI reader to inspect a
live run while the runtime continues writing. The database and any WAL files
must be treated as one unit while the connection is open.

## Runtime integration

### Startup

Modify `execute_flows` to:

1. create `run_dir`;
2. open `run_dir / "vecherinka_provenance.sqlite3"`;
3. create the schema and initialize the `run` metadata;
4. attach the store to `RuntimeContext`;
5. mark the run as `running`.

The store must be initialized before the input artifact is registered, so the
input artifact is represented in the database like every other artifact.

### Artifact commit

Modify `register_artifact` to perform one transaction:

1. validate that each predecessor ID resolves to a registered artifact;
2. convert predecessor artifact directories to run-relative paths;
3. assign the next monotonic `commit_seq`;
4. insert the artifact path;
5. insert one edge per predecessor, using its sequence position;
6. update `run.last_commit_seq`;
7. commit the transaction.

The artifact table and all of its edges must become visible atomically.

Manual registration with no predecessors remains valid. It simply inserts a
root artifact. Unknown predecessor IDs should be rejected because they cannot
be represented safely as paths.

### Shutdown

In the existing `execute_flows` `finally` block:

1. determine `finished`, `failed`, or `aborted`;
2. update the run status and finish timestamp;
3. close the SQLite connection.

If shutdown itself encounters a database error, preserve the original runtime
failure where possible and report the database error as additional context.

## Nim reader module

Add a reusable, checked-in module:

```text
src/vecherinka_provenance.nim
```

Do not generate a Nim source file per run. The SQLite database is the generated
run artifact; a stable reader module is easier to compile, version, and use
from tools or an RSI process.

The module should hide the SQLite driver types and expose only provenance
types:

```nim
type
  ArtifactProvenance* = object
    path*: Path
    predecessors*: seq[Path]
    children*: seq[Path]

  ProvenanceRun* = object
    runDir*: Path
    status*: string
    startedAtNs*: int64
    finishedAtNs*: int64
    lastCommitSeq*: int64

  ProvenanceReader* = ref object
```

Initial API:

```nim
proc openProvenance*(databasePath: Path): ProvenanceReader
proc close*(reader: ProvenanceReader)
proc runInfo*(reader: ProvenanceReader): ProvenanceRun
proc artifact*(reader: ProvenanceReader;
               path: Path): Option[ArtifactProvenance]
proc artifacts*(reader: ProvenanceReader): seq[ArtifactProvenance]
proc artifactsAfter*(reader: ProvenanceReader;
                     commitSeq: int64): seq[ArtifactProvenance]
proc roots*(reader: ProvenanceReader): seq[Path]
proc leaves*(reader: ProvenanceReader): seq[Path]
```

`artifactsAfter` is the important RSI hook: the consumer can persist its last
commit sequence and process only newly committed artifacts.

Export the reader module from `vecherinka.nim` so a separate Nim tool can use
the same public API as a running Vecherinka program.

## Dependency work

Use the installed Nim `db_connector` package and its `db_connector/db_sqlite`
wrapper. With the installed Nim 2.3.1 toolchain, the compilation unit must also import
`std/algorithm`; otherwise the connector's blob-copy implementation reports
`copyMem` as unresolved during module analysis.

Before runtime changes, verify a minimal program can:

1. open a file database;
2. create the schema;
3. insert/query rows with bound parameters;
4. close cleanly;
5. compile under the project's normal Nim command.

## Tests

Add focused tests for:

- database creation and schema version;
- input/root artifact persistence;
- linear provenance;
- fanout and lift joins;
- multiple direct predecessors;
- duplicate predecessors and preserved positions;
- manual registration without predecessors;
- rejection of unknown predecessor IDs;
- atomic visibility of an artifact and its edges;
- `artifactsAfter` commit-sequence polling;
- finished, failed, and aborted run status;
- opening the database after the runtime closes;
- moving the complete run directory and resolving relative paths.

Run the existing artifact provenance and runtime test suites after these tests.

## Human-readable output

Do not add a renderer to the runtime in the first SQLite change. A separate
small Nim tool can consume `vecherinka_provenance.nim` and print a tree or
emit DOT/SVG later. Keeping rendering outside runtime avoids coupling
execution correctness to presentation code while still making a human-readable
view straightforward to implement.

## Implementation order

1. Add the connector-backed SQLite store and schema initialization.
2. Attach store lifecycle to `RuntimeContext` and `execute_flows`.
3. Persist artifact commits and direct edges.
4. Add the public reader module and export it.
5. Add unit and integration tests.
6. Run the manual and parallel-research examples, inspect the databases, and
   compare their graphs against the existing JSONL/SVG output.
