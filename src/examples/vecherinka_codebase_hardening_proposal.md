# Proof directed codebase hardening

**Status:** implementation specification. This document changes no workflow
code. A workflow built to this specification must preserve every limit below;
it must not label model analysis as proof.

The workflow takes a frozen codebase and a small hardening spec. It derives a
structural index, describes current behavior from leaves upward, maps the
requested intent from roots downward, proposes one coherent redesign, then
builds and checks a candidate. It may propose a large rewrite. It does not
optimize a numeric objective unless the user's task text names one and a
deterministic measurement is available.

## 1. Guarantees and non-guarantees

For one fixed source snapshot, hardening spec, frontend version, and tool
runner version, the deterministic part of the workflow MUST produce the same
file manifest, IDs, worklist, validation decisions, and state transitions.
Model text may vary; it is stored as a proposal with its evidence.

The workflow MUST distinguish these statements:

- **Indexed:** the pinned deterministic frontend returned a source-linked
  record. Generated-tool output is never indexed.
- **Covered:** the worker returned one behavior case or an explicit unknown
  for every indexed branch and exit site.
- **Check passed:** a named deterministic check passed for the declared
  candidate and environment.
- **Proved:** a named verifier accepted a machine-checkable obligation.

Indexing and coverage do not prove that a source record or natural-language
contract is semantically correct. Compilation and tests prove only the
properties exercised by those checks. A model cannot upgrade a claim to
`proved`, and the final report MUST state the exact checker and scope behind
each proof label. Without a verifier for a required semantic claim, the result
is a checked candidate with an explicit unknown, not a proof.

The workflow has no generic optimizer and claims no global minimum or maximum.
A request such as “substantially simplify the API code” is task text that
guides design. The workflow does not invent a line-count target or trade
behavior away to meet one.

The coverage claim is limited to the `roots` selected by the hardening spec,
their reachable calls and module initialization, and traversal stopped at
declared `trust` boundaries. A user who wants every subsystem covered must
name an entry root for each subsystem; code outside that reachable scope is
reported as unexamined, not complete.

## 2. Existing Vecherinka boundary

### 2.1 Value and runner conventions

The pseudocode below maps to Nim artifact types as follows: records are Nim
objects; lists are `seq[T]`; optional values are `Option[T]`; byte strings are
`Blob`; and tagged unions are Nim discriminated variant objects. `Hash` is a
64-character lowercase hexadecimal SHA-256 string. `RelativePath` is a
slash-separated UTF-8 string normalized by the parser. `SymbolId`, `SiteId`,
`GapId`, and `ClaimId` are validated UTF-8 strings with the exact prefixes and
hash encodings stated below. No artifact field uses maps, floating point,
pointer, proc, or `JsonNode` values. Objects serialize fields in declaration
order; sequences preserve order. Validators reject noncanonical paths, hashes,
IDs, enum values, and duplicate sequence keys before a stage can consume them.

The host owns a versioned `ToolchainRegistry`. Each entry binds a stable
registry ID to executable bytes, dependency/runtime closure, and a SHA-256
manifest. Registry entries are immutable during a run. OS isolation is a
separate required service, not a property implied by `PATH`, Python flags, or
the model worker's filesystem sandbox. Its version and policy hash are part
of every process result. A backend that cannot enforce the requested policy
is unavailable; there is no unsandboxed fallback.

For any `BlobTree`, `TreeHash` is SHA-256 of canonical JSON for the
UTF-8-byte-sorted sequence `[{path, sha256(file_bytes)}]`; empty directories
do not affect it. `Index.snapshot_hash` is `TreeHash` of the comment-free
projection passed to the frontend. Candidate parent hashes and process input
hashes use `TreeHash` of the actual stored tree, including generated comments.
`ArtifactHash(value)` is SHA-256 of canonical JSON for the artifact fields,
with each Blob replaced by its byte hash and each BlobTree replaced by its
TreeHash. Workflow references use these content hashes, never storage-assigned
artifact IDs. Define `index_hash` as SHA-256 of canonical JSON for exactly
`{snapshot_hash, frontend_id}`. This is the stable basis identity used by
`Analysis`, `UnitId`, and `GapId`; it is deliberately not the full `Index`
artifact hash, so `GapId` does not depend on itself. Where a consumer needs
the full index contents, it uses `ArtifactHash(Index)`.

The current artifact system serializes types known when the workflow is
compiled. The `vecherinka` macro collects flow types and emits codecs in
[`vecherinka_comptime.nim`](../api/vecherinka_comptime.nim). Runtime `so`
callbacks are compiled Nim procedures; they receive typed values and a budget
snapshot, have no artifact/workspace path API, and must be deterministic
because resume can replay them. See the [`so` contract in the DSL guide](../docs/vecherinka_dsl_guide.md#composition-and-data)
and the `fk_so` replay path in
[`vecherinka_runtime.nim`](../api/vecherinka_runtime.nim).

The Codex dynamic tool registry is also not a generated-code runner. It holds
Nim callbacks and the current generated model flow registers `finish_work` to
materialize a statically declared output type. See
[`codex_json.nim`](../api/codex_json.nim) and the model lowering in
[`vecherinka_comptime.nim`](../api/vecherinka_comptime.nim).

Every model task has one immutable typed input, one declared output type, and
one available model tool: `finish_work(output)`. Workers receive no shell,
filesystem, network, browser, or process tool. Source bytes and tool output
are untrusted data, never instructions; only `HardeningSpec.task` supplies
user intent. The host parses the returned value against the exact output
schema, rejects unknown fields and invalid references, and sends one
correction call containing the same input plus validator errors. After that,
the host records a typed unknown or terminates the stage as specified below.
No worker can choose the next state, name its own next task, or commit an
artifact directly.

Therefore artifact instantiation alone cannot execute a Python file. This
spec adds one static runtime operation, `run_process`, with a fixed typed
input/output ABI and two constructors: `run_tool` for generated Python and
`run_check` for registered project checks. The workflow graph contains these
compiled operations before any generated tool exists. A package is data; it
never creates new workflow nodes. `run_process` is a restricted process
runner, not a `so` callback and not a model dynamic tool.

```text
ProcessRequestKind = generated_tool | project_check

ProcessRequest = object
  case kind: ProcessRequestKind
  of generated_tool:
    package: ToolPackage
    request: ToolRequest
    source: BlobTree
  of project_check:
    check: Check
    candidate: BlobTree

ProcessResult {
  request_hash: Hash              # SHA-256 of canonical request encoding
  status: exited | timed_out | output_limit | launch_failed |
          isolation_unavailable
  exit_code: optional int         # 0..255; signal termination maps to 128+signal
  stdout: Blob
  stderr: Blob
  executable_hash: Hash
  executed_tools: [{ registry_id: String, sha256: Hash }]
  runner_hash: Hash
  sandbox_profile: generated_tool | project_check
  sandbox_profile_hash: Hash
}
```

`request_hash` is SHA-256 of canonical JSON for the request, replacing each
Blob with its hash and each BlobTree with its canonical tree hash. `exited`
means the child terminated normally or by signal and requires
`exit_code=Some(integer)` in 0..255; signal termination maps to `128+signal`.
Every other status requires `None`. `launch_failed` means no child started;
`timed_out` and `output_limit` mean the runner terminated the child tree.
`ProcessResultHash` is SHA-256 of canonical JSON containing request hash,
status, exit code, SHA-256 of stdout/stderr bytes, executable hash, ordered
executed-tool records, runner hash, and sandbox-profile hash. References to a
process result use this derived hash, not a storage-assigned artifact ID.

The host constructs an explicit sandbox file layout and cwd for each request.
For `run_tool`, only the tool file and requested source subset are readable;
the `source` BlobTree must contain exactly the `ToolRequest.files` with
matching hashes, and the tool can write only its private scratch directory.
For `run_check`, the
candidate or baseline tree is read-only, as are runtime/toolchain roots; only
private scratch is writable. `cwd` maps to the corresponding read-only tree
path, so checks direct build/test output to `TMPDIR` or another scratch path.
Build output cannot change the candidate being checked. The runner uses a
fixed environment (`LANG=C.UTF-8`, `TZ=UTC`, empty inherited environment,
private `HOME` and temporary directory, `TMPDIR` and `VECHERINKA_SCRATCH`
set to scratch) and a fixed cwd inside the sandbox. For checks,
`PATH` contains only wrappers for that check's registry closure; no host
`PATH` entries are visible. All check descendants share the 600-second wall
limit, a two-core CPU quota, and an 8 GiB memory limit. Generated tools
cannot start child processes. Project checks may start only registry-listed
executables, which are recorded in `ProcessResult.executed_tools`. The
top-level executable is selected only by registry ID; `argv` is passed
without a shell. Stdout is capped at 10 MiB and stderr at 1 MiB, enforced
while streaming; when a stream would exceed its cap, the runner stores only
the first cap bytes, terminates the process tree, and returns `output_limit`.
The profile hash identifies the OS isolation backend and
policy, executable registry, fixed environment, limits, and input layout.
The backend MUST deny access outside the declared writable roots, declared
read-only inputs, and read-only runtime/toolchain roots; deny network; and
enforce the process-specific child-execution policy. It denies devices,
inter-process sockets, inherited file descriptors other than stdin/stdout/
stderr, and signals to host processes. It MUST also prevent other external
side effects. If it cannot enforce or attest those
restrictions, it returns `isolation_unavailable` before starting the program.
`run_tool` denies child execution. `run_check` allows execution only from the
check's pinned registry closure. A nonzero exit or any non-`exited` status
cannot pass a check.

Process execution is at-least-once until its result and the next checkpoint
commit atomically: a crash after process exit but before commit may rerun it.
Both profiles are therefore confined to disposable filesystem state and have
no network or other external side effects. Resume reuses a committed result
only when request, input-tree, executable/toolchain, runner, and sandbox
profile hashes all match. A workflow manifest/runtime version mismatch rejects
resume rather than dispatching pending work under changed process semantics.

This is one conceptual flow operation but not a one-file API change. Its
implementation adds a typed `run_process` constructor, compile-time DSL
recognition/lowering, a process `FlowKind` and payload, executor dispatch,
graph/work records, completion/failure handling, artifact codecs, a workflow
manifest version, and checkpoint-resume validation. The process service is
owned by the host scheduler; it is not accessible from `so` or model code.

## 3. Input contract

The generated solve receives two semantic inputs:

```nim
type
  HardeningInput = object
    codebase: BlobTree
    spec: HardeningSpec
    spec_sha256: Hash             # hash of the exact source file bytes

  HardeningSpec = object
    version: int                 # must equal 1
    inspect: seq[string]         # relative path globs
    roots: seq[string]          # nonempty relative-path#qualified-name globs
    trust: seq[string]           # module-id#qualified-name selectors
    write: seq[string]           # relative path globs
    task: string                 # intent, context, trust assumptions, goal
    checks: seq[Check]

  Check = object
    name: string
    argv: seq[string]            # argv[0] is a registry ID; no shell
    cwd: string                  # relative to codebase root
```

The executable interface is `run` or `resume`, followed by
`--source-root ABS --spec ABS --output-root ABS --database ABS
--deadline-seconds N`. All four paths must be absolute; relative paths are
rejected and never resolved against process cwd. `N` is a positive integer
wall-clock limit enforced by the external supervisor. `run` requires a new
database; `resume` requires an existing database with matching input and
workflow-manifest hashes. The source root must
be a directory and the spec must be a regular file; both are checked without
following a final symlink. The CLI reads and validates the spec first,
computes `spec_sha256` over its exact bytes, and expands `inspect` against the
explicit source root using `lstat` without following symlinks. It copies only
matched regular files into `BlobTree`; before hashing, it strips any complete
well-formed `vecherinka-spec:v1` blocks from files as defined in §6.6. These
blocks are derived documentation from an earlier run and are never analysis
input. A reserved marker that is malformed or nested is a structured
preflight error. A matched symlink or non-regular entry is a
structured preflight error naming that path, before any model call. File
contents outside `inspect` are not read or persisted; directory names may be
enumerated transiently for matching. The resulting `BlobTree` is the
normalized comment-free input snapshot; the source root is never changed.
Before opening SQLite or creating output, the host resolves existing path
parents and rejects an output root that overlaps the source tree, a database
file inside the source tree, or a database file inside the output root. The
output root, database file, report file,
and candidate export path must not be symlinks; export uses a private staging
directory under the output root and an atomic rename. The runner writes only
`hardening-report.md` and `candidate/` under the explicit output root. This
enforces the source-immutability guarantee even when the caller chooses
overlapping paths.
Check commands therefore see
only this declared snapshot; every source/config/dependency file a check
needs must match `inspect`. The CLI uses the supplied absolute output and
SQLite paths as given. No stage derives meaning from process cwd, a directory
basename, or a temporary workspace name. `BlobTree` paths are
canonical relative paths, with no symlinks or duplicate normalized names.
At terminal commit, the host writes `output-root/hardening-report.md` and,
when a host-valid candidate exists, exports the selected candidate under
`output-root/candidate/`. It never edits `source-root`. Candidate selection
is the most recent candidate on which all configured checks passed; if none
passed, it is the latest host-valid candidate. With no checks, the single
allowed candidate is exported with terminal status `PARTIAL`.

`inspect` defines the source snapshot and inspection boundary: selectors
match leaf entries only; directories are traversed as containers and are
never included. Only matching regular files are read, persisted, or sent to
analysis workers. Other paths may be enumerated transiently for glob
matching, but their contents and metadata are not persisted or sent to
workers. Symlinks are never followed; if a selector matches a symlink or
other non-regular leaf entry, preflight fails with that path. `roots` are
entry points;
the call graph is followed down from them until a `trust` selector matches a
call target. A matched target is a trust boundary: its implementation is not
specified or rewritten, and callers cite the corresponding assumption from
`task`. An edge outside `inspect` that does not match `trust` is an unknown,
not an implicit trust decision. Every listed trust selector must match at
least one resolved internal or external call target; otherwise preflight
fails. `task` contains the human-readable trust assumptions, context, intent,
and desired degree of hardening. `write` is the authority plane: every added,
removed, or changed path in a candidate must match both `write` and `inspect`.
A write pattern may match no existing file; that permits an authorized new
file. The candidate path gate checks every changed path against both sets.

Path globs are slash-separated and relative to the `BlobTree` root. Paths
must be canonical: no leading/trailing slash, empty, `.` or `..` component,
backslash, NUL, or `#`. Version 1 supports `*` for zero or more Unicode scalar
values in one segment, `?` for one Unicode scalar, and `**` only as a complete
segment matching zero or more path segments. Matching is case-sensitive and
does not normalize Unicode. It supports no negation, braces, or shell
expansion. Patterns and file paths are validated and sorted by UTF-8 bytes
before matching.

Each root selector has the form `path-glob#qualified-name-glob`. It selects
all overloads that match; zero matches is an input error. Top-down work
starts from these roots and follows indexed callers/callees as specified in
the algorithm. Each trust selector has the form
`module-id#qualified-name-glob`; its module ID is exact and its name uses the
language-specific identifier normalization and glob matching rules. A
qualified name is owner identifiers and the declaration name joined by `.`
after canonicalization. Its glob uses `*` for zero or more Unicode scalar
values and `?` for one scalar; `.` is literal and no escape syntax is
supported. An
inspected source module uses its normalized relative path as module ID. A
registered external module uses
`toolchain://<registry-id>/<module-relative-path>`. The pinned frontend's
static import resolver supplies these identities without executing project
code. A selector that matches no resolved call target is an input error.

`task` is passed verbatim to every planning worker. It contains the user's
top-level intent, context, hardening degree, and assumptions. Those items do
not need parallel typed fields. The workflow has no objective parser or
numeric score field; prose such as “minimize lines” guides model design but
does not promise an optimum. If a measurable target must gate acceptance, it
must be encoded as a deterministic `Check`. An LLM-generated tool can report
a measurement but cannot make that acceptance decision. `checks` is typed
because it controls process execution: each check runs as exactly `argv` from
`cwd`, without a shell,
against the baseline and candidate. `argv[0]` is a registry ID resolved only
through the runner's explicit, versioned toolchain registry; ambient `PATH`
is ignored. That entry names the complete allowed child-executable closure
for the check, and the OS sandbox must deny execution outside it. Each check
name matches `[A-Za-z0-9_-]{1,64}` and is unique; checks are sorted by name
before execution. `cwd=""` means the tree root; any other cwd is a canonical
relative directory path that is a parent of at least one snapshot file. It
cannot escape the tree. `argv` is nonempty, all arguments are UTF-8 strings
without NUL, and the first argument is exactly one registry ID. An empty
`checks` list permits at most one candidate and can never produce
`COMPLETE` or a `proved` result. The candidate is exported with terminal
status `PARTIAL`, unless a valid `needs_user_input` decision stops the run
before a rewrite. Check commands run against
the read-only baseline/candidate tree with a private writable scratch
directory, fixed environment, no network, and a 600-second limit. Build/test
tools must direct outputs to scratch. Missing executables, timeouts, output-limit events, and
isolation failures are `unknown` or `fail`, never `pass`. Every check runs
once on the baseline and once on each candidate under the same profile hash;
all checks run even if an earlier one fails, so reports have the full result
set.
A baseline failure is recorded and does not count as a candidate pass; a
candidate passes only if every required check exits zero before timeout and
output limits.

The spec parser accepts a strict YAML 1.2 subset: mappings, sequences,
quoted/plain UTF-8 strings, the integer `version: 1`, and literal block strings
for `task`; it rejects duplicate keys, anchors, aliases, tags, merge keys,
implicit non-string scalars, unknown keys, wrong types, absolute paths, `..`,
unsupported glob forms, and invalid versions. `spec_sha256` is SHA-256 of the
exact spec file bytes. Source file hashes and `original_snapshot_hash` are
computed from the normalized, comment-free `BlobTree` bytes described above.
The canonical parsed spec hash is SHA-256 of canonical JSON for the validated
fields, and is distinct from `spec_sha256`.
The `inspect`, `roots`, `trust`, and `write` sequences reject duplicates and
are sorted by UTF-8 bytes before canonical hashing and matching. The `checks`
sequence rejects duplicate names and is sorted by name; each `argv` sequence
retains its declared order. The decoded `task` string preserves its scalar
sequence without Unicode normalization, must be nonempty valid UTF-8, and
must contain no NUL.

## 4. Durable artifacts and identifiers

SQLite's existing artifact store is the durable state. The core accumulated
state is the current `Index`, `Analysis`, accepted `ReconciliationSpec`, and
latest host-valid `Candidate`. Tool/check outputs and worker attempts are
immutable result artifacts. The workflow does not keep a second mutable
symbol worklist; scheduler work is derived from the `Index` and phase result
hashes.

### 4.1 `Index`

```text
Index {
  snapshot_hash: Hash
  frontend_id: String
  coverage: complete | partial
  files: [FileRecord]           # sorted by normalized path
  symbols: [SymbolRecord]       # sorted by SymbolId
  calls: [CallRecord]          # sorted by caller id and source span
  sites: [SiteRecord]          # sorted by symbol id and source span
  gaps: [Gap]                   # sorted by GapId, unique
}

FileRecord {
  path: RelativePath
  sha256: Hash
  parse: complete | partial | failed | unsupported
}

SymbolRecord {
  id: SymbolId
  path: RelativePath
  kind: SymbolKind
  owner: [CanonicalIdentifier]
  name: CanonicalIdentifier
  header: CanonicalTokenSequence
  implementation_hash: Hash
  span: [start_byte, end_byte)
}

SymbolKind = proc | func | method | iterator | converter | macro | template |
             module_init

CallRecord {
  caller: SymbolId
  site: SiteId
  resolution: unique | ambiguous | dynamic | trusted_boundary | external | unresolved
  targets: [SymbolId]
  external_targets: [{ module_id: String, qualified_name: String }]
}

SiteRecord {
  id: SiteId
  symbol: SymbolId
  kind: statement | branch_arm | loop_test | return | raise | call |
        break | continue | fallthrough | suspension
  span: [start_byte, end_byte)
}

Gap {
  id: GapId
  path: optional RelativePath
  span: optional span
  owner: optional SymbolId
  site: optional SiteId
  reason: String
}
```

`snapshot_hash` is `TreeHash` over every file passed to the frontend. Each
`FileRecord.sha256` is SHA-256 of the exact projected file bytes. `coverage`
is `complete` only when every selected file
is parsed by the Nim adapter with no syntax/construct gap; otherwise it is
`partial`. A parser crash is a workflow failure, not an Index coverage value.

Every file selected by `inspect` appears exactly once. Version 1 accepts Nim
source files only; any other selected file is `unsupported` and forces
`coverage=partial`. Non-code context belongs in `task`. The frontend is a
trusted, pinned syntax adapter compiled into or invoked by the host; it takes
only the exact selected file bytes and emits this `Index` schema. It does not
run project builds, macros, templates, or compile-time code. Its v1 parser
must visit every declaration and executable AST node and map each to a
`SymbolRecord`, `SiteRecord`, or explicit `Gap`. A `SymbolRecord` is emitted
for every named callable declaration of the listed `SymbolKind`s; parameters,
locals, types, and fields remain in their owning declaration source. Every
selected module receives one synthetic `module_init` symbol named
`$module_init`, which owns its executable top-level statements, runtime
initializers, and import-initialization call sites. Anonymous callables,
unsupported callable declarations, and macro-generated declarations produce
gaps. Site kinds are assigned as follows: `statement` for every executable
statement that is not one of the other listed kinds; `branch_arm` for each
if/case/try handler/when arm and short-circuit or conditional-expression arm;
`loop_test` for each explicit loop condition and each `for` iterator's
implicit next-item test, using the loop header span for the latter; `return`,
`raise`, `call`, `break`, and `continue` for those syntax nodes;
`fallthrough` for each callable's implicit normal completion; and
`suspension` for yield/await forms. A call expression is a call site even
when nested inside another expression. A node not covered by this mapping
creates a gap and makes file coverage partial. Conditional branches are all
indexed; a compile-time condition whose selected branch cannot be known
without executing project code remains a gap.

Each `import` or `from` module import creates a synthetic `call` SiteRecord
in the importing module's `module_init`, spanning the import syntax, and a
CallRecord to the imported module's `$module_init`. It resolves internally
only if that module is in the selected file manifest; it resolves externally
only if present in the pinned toolchain module manifest. Otherwise it is an
unresolved edge and gap. `include`, dynamic module loading, and import forms
the adapter cannot map exactly are gaps.

The adapter resolves only declarations whose identity it can determine from
syntax and lexical scope. It does not invoke Nim semantic analysis because
that can execute project compile-time code. A call target outside that
resolution contract is `ambiguous`, `dynamic`, `external`, or `unresolved` and
creates a gap. For an external target it reports the canonical module ID and
qualified name if known; otherwise there is no `external_target` and the edge
is unresolved. An inspected source module uses its normalized relative path
as module ID. A module from the pinned toolchain registry uses
`toolchain://<registry-id>/<module-relative-path>`. A matching `trust` selector
changes the edge to `trusted_boundary`, stops traversal there, and requires
an assumption claim grounded in `task`. `complete` means the pinned parser
reported complete structural coverage for all inspected Nim files; it does
not mean semantic call resolution or runtime behavior is complete.

The frontend owns symbol discovery and declaration headers. LLMs cannot add,
remove, rename, or deduplicate symbols. If no deterministic frontend supports
a code file, that file is unsupported and forces `coverage=partial`.

For a declaration the frontend can represent, calculate IDs exactly as
follows. `E(x)` is an unsigned 64-bit big-endian byte length followed by the
UTF-8 bytes of `x`. The header is an ordered sequence of `(token-kind,
token-bytes) pairs, each encoded as `E(token-kind) || E(token-bytes)`.
Comments and insignificant whitespace are omitted; Nim newline/indent tokens
are retained where they affect syntax. For Nim identifiers, preserve the
first character, then remove underscores and lowercase ASCII letters in the
remaining characters, matching Nim's [documented identifier equality](https://nim-lang.github.io/Nim/manual.html#identifier-equality).
Version 1 marks non-ASCII or backtick-quoted identifiers unsupported rather
than guessing their canonicalization. `name` stores the canonical form; raw
spelling is read from the declaration source span for display.

```text
key = E("sym-v1") || E(frontend_id) || E(language_id) ||
      E(normalized_relative_path) ||
      E(u32be(owner_count)) || concat(E(owner_identifier_i)) ||
      E(declaration_kind) ||
      E(canonical_name) || concat(header_token_i)
SymbolId = "sym-v1:" + lowercase_hex(SHA256(key))
```

The header includes parameters, generic parameters/constraints, return type,
default values, and declaration pragmas before the body delimiter. It excludes
the body and source line numbers. `implementation_hash` is SHA-256 of the
canonical token sequence for the body, excluding comments and insignificant
whitespace. A header change creates a new ID; a body change preserves it. A
collision is an index error, never resolved by enumeration order. An
unsupported declaration has no SymbolId. A generated
tool's candidate declaration also has no SymbolId and cannot be cited as
indexed coverage.

For each function, child-node paths come from a deterministic preorder AST
walk. `encode(child_index_path)` is `u32be(count)` followed by each child
index as `u32be`; `encode(span)` is the start and end byte offsets as two
unsigned 64-bit big-endian integers. The site key is:

```text
SiteId = "site-v1:" + lowercase_hex(SHA256(
           E("site-v1") || E(file_sha256) || E(SymbolId) || E(node_kind) ||
           encode(child_index_path) || encode(span)))
```

Site IDs are file-snapshot-local. A change to a file invalidates that file's
site contracts and requires rederivation. Spans are zero-based half-open byte
ranges `[start_byte, end_byte)` into the exact hashed file; source refs must
satisfy `0 <= start <= end <= file_length`. Optional encodings use `0x00` for
None and `0x01 || value` for Some, so absent and empty values differ. A gap ID
is `gap-v1:` plus lowercase SHA-256 of
`E(index_hash) || opt(E(path)) || opt(encode(span)) || opt(E(owner)) ||
opt(E(site)) || E(reason)`.

The deterministic host validates manifest coverage, hashes, enum values,
unique IDs, source bounds, sorted order, declaration/header correspondence,
call-site membership and these call invariants: `unique` has exactly one
internal target and no external targets; `ambiguous` has at least two total
distinct candidates across `targets` and `external_targets`; `external` has
at least one external target and no internal target; and `dynamic`/`unresolved`
has no candidate target. `trusted_boundary` has at least one internal or
external target that matches a declared selector. Target lists are sorted
and duplicate-free.
A generated tool cannot add
records to `Index`; its records remain tool observations. The host cannot
validate that a natural-language fact is true. A frontend's completeness is
relative to the pinned parser and its declared syntax boundary.

### 4.2 `Analysis`

Bottom-up and top-down results share one claim store:

```text
Analysis {
  index_hash: Hash
  spec_sha256: Hash
  completed_units: [UnitId]     # accepted work outputs, sorted and unique
  claims: [Claim]              # sorted by host-derived ClaimId
  gaps: [Gap]                  # sorted by GapId, duplicate IDs coalesced
  site_cases: [SiteCase]       # sorted by SiteId, exactly one per root-scope site
}

ClaimKind = observed | intent | inference | assumption | mismatch |
            check_failure | unknown
Relation = precondition | postcondition | effect | raises | guard | outcome

Claim {
  id: ClaimId                  # computed by host, never supplied by model
  kind: ClaimKind
  relation: Relation
  subjects: [SymbolId]
  site: optional SiteId
  statement: String
  evidence: [EvidenceRef]
}

EvidenceRef = SourceRef | TaskRef | ClaimRef | ToolRef | ToolGapRef | CheckRef | CheckSpecRef | GapRef
EvidenceDraft = EvidenceRef | GapDraftRef | ClaimDraftRef
ClaimDraftRef { draft_id }
SourceRef { path, sha256, start_byte, end_byte }
TaskRef { spec_sha256, task_start_byte, task_end_byte }
ClaimRef { claim_id }
ToolRef { tool_hash, output_hash, observation_index }
ToolGapRef { tool_hash, output_hash, gap_index }
CheckRef { check_name, process_result_hash }
CheckSpecRef { spec_sha256, check_name }
GapRef { gap_id }
GapDraftRef { draft_id }

GapDraft {
  draft_id: String
  path: RelativePath
  span: optional span
  owner: SymbolId
  site: optional SiteId
  reason: String
}

SiteCase { site_id, claim_ids: [ClaimId] } # bottom-up behavior claims only

ClaimDraft {
  draft_id: String
  kind: ClaimKind
  relation: Relation
  subjects: [SymbolId]
  site: optional SiteId
  statement: String
  evidence: [EvidenceDraft]
}
SiteCaseDraft { site_id: SiteId, draft_ids: [String] }
```

`UnitId` is `unit-v1:` plus SHA-256 of canonical JSON for `phase`,
`index_hash`, exact `spec_sha256`, and the sorted member SymbolIds. For a
top-down unit the member list has one SymbolId; for a bottom-up unit it is one
SCC. Binding the spec prevents reuse of work whose task or trust assumptions
changed. `Analysis.spec_sha256` must equal the input spec's exact-byte hash.

Claim IDs are `claim-v1:` plus SHA-256 of canonical JSON for the object
`{kind, relation, subjects, site, statement, evidence}`; `id` is excluded.
Subjects sort by SymbolId and evidence sorts by each reference's canonical
JSON bytes. Each `EvidenceRef` is a closed tagged object whose `kind` is the
lowercase variant name and whose remaining fields are exactly those shown in
its record above; optional values encode as
JSON null. `Analysis.claims` sorts by ClaimId and coalesces exact duplicate
records by that ID. Semantically similar records are not merged by
deterministic code. Every SourceRef span
is checked against its hashed file bytes. `TaskRef` offsets are zero-based,
half-open UTF-8 byte offsets in the decoded `task` string; the host checks
them against that string, and `spec_sha256` binds the exact original spec
bytes that produced it. A durable ClaimRef may reference only a claim committed by an earlier
kernel task. A ClaimDraftRef may refer only to an earlier ClaimDraft in the
same ordered response. The host resolves it to that draft's computed
ClaimRef before hashing the current claim. This permits a top-down worker to
emit an intent claim followed by a mismatch that cites it, while keeping the
dependency graph acyclic. ClaimRef evidence is the sole dependency relation;
the host computes IDs without model-supplied IDs.

Worker output may include `GapDraft`s and `ClaimDraft`s with local IDs using
`[A-Za-z0-9_-]{1,64}`; IDs are unique across both draft types in one response.
Each `GapDraft` must name an in-scope owner, use that symbol's exact path, and
have either no site or a site owned by that symbol; any span must be inside
the referenced file. Each draft gap must be referenced by at least one
`unknown` ClaimDraft. The host validates each gap source span and owner/site, computes
its GapId, replaces every GapDraftRef with the resulting GapRef, then resolves
ClaimDraftRefs in claim order and computes ClaimIds. No local draft ID is
persisted. A worker `unknown` claim
must reference exactly one existing Gap or one GapDraft; if it is a
GapDraftRef, the gap owner must be among the claim subjects and the claim's
site must equal the gap's site.
Host-generated
missing-output gaps use reason
`missing required claim: unit=<UnitId>; site=<SiteId>; relation=<Relation>`
and the corresponding site span and owner; missing symbol-contract gaps use
`missing required claim: unit=<UnitId>; symbol=<SymbolId>; relation=<Relation>`
and the declaration span/owner with `site=None`.

Evidence validation by kind is exact and allows no extra reference kinds:
`observed` has one or more SourceRefs; `intent` has a TaskRef or a ClaimRef
whose reference chain reaches a TaskRef; `inference` has a SourceRef or
ClaimRef; `assumption` has a TaskRef; `mismatch` has exactly two ClaimRefs,
one to an `observed` claim and one to an `intent` claim, both with the same
subjects as the mismatch and the intent reference chain reaching a TaskRef;
if the mismatch has a site, it equals the observed claim site;
`check_failure` is host-generated and has exactly a CheckSpecRef and a
CheckRef with the same check name, where the result is a candidate check
that exited nonzero; and `unknown` has exactly one GapRef. ToolRef and
ToolGapRef are permitted only in plan disposition evidence. Every
ClaimRef must resolve and every SourceRef must match a frozen file hash and
valid byte span. If a claim has subjects, each SourceRef must lie inside at
least one subject declaration span, and a non-null site must belong to one
of its subjects. Evidence arrays and `SiteCase.claim_ids` are sorted and
duplicate-free. All claim subjects must exist in
the deterministic root scope, except a host-generated workflow-level
`unknown` or `check_failure` may have no subject. Models may not emit
`check_failure`; an empty-subject unknown is host-generated only. A
trust-boundary assumption
claim is attached to the caller and call
site, and must contain a TaskRef; the host checks that the site targets the
matched trust selector.

The only host-generated unknowns with no symbol subject use the constructor
`host_workflow_unknown(reason_code, statement)`: create a Gap with all
location/owner/site fields null and `reason=reason_code`, then create a Claim
with `kind=unknown`, `relation=outcome`, empty subjects, `site=None`, the
given statement, and exactly that GapRef. Version 1 reason codes are
`no_checks_configured`, `rewrite_no_progress`, `invalid_reconciliation_plan`,
and `invalid_assessment`. Their human-readable statements are fixed by the
corresponding state rule. Other host unknowns must name a symbol or site.

Before model work, the host converts each `Index.gap` whose owner or site is
in root scope into a host unknown claim with `relation=outcome`, the gap owner
as its sole subject, its site if present, statement `indexed source gap: <reason>`,
and exactly that GapRef. A gap with a site must name that site's owning symbol.
If a gap in a reachable source file has neither owner nor site, Index
validation fails; the frontend must retain the enclosing module-init or
callable context. These host claims are included in `Analysis` and in the
corresponding SiteCase when they have a site. `GapRef` may resolve to either
`Index.gaps` or `Analysis.gaps`; `Analysis.gaps` stores only analysis-created
gaps, not copies of Index gaps. A worker may reference an existing Index gap
but cannot redraft it.

Every root-scope site has exactly one `SiteCase`. Each valid
`SiteCaseDraft` has exactly one entry for its site and refers only to
`ClaimDraft.draft_id`s from the same unit response. The host replaces these
local links with the computed ClaimIds. The final `SiteCase.claim_ids` is the
sorted unique set of that site's accepted bottom-up claims plus host-generated
Index-gap unknowns; top-down intent/mismatch claims remain in `Analysis` but
are not part of the behavior case. Required relations are:
`statement` requires `effect` and `outcome`; `branch_arm` and `loop_test`
require `guard` and `outcome`; `return`, `break`, `continue`, and `fallthrough`
require `outcome`; `raise` requires `raises`; `call` requires `outcome`,
`effect`, and `raises`; `suspension` requires `effect`, `outcome`, and
`raises`. A site is covered only when every required relation has at least
one linked non-unknown claim and no linked unknown claim. Its
`specified`/`unknown` result is derived, never stored.
A bottom-up response is accepted atomically only if every member contract,
site, required relation, and reference is valid. Any invalid or incomplete
response gets one correction call. If the correction is still invalid, the
host discards both responses and creates a deterministic `Gap` plus one
`kind=unknown` claim for every required member-level and site-level relation
in that SCC. Each claim statement is `worker supplied no valid claim for
required relation <relation>` and its sole evidence is that gap. The host
creates one SiteCase per site, marks the UnitId completed, and continues.
Thus a malformed response cannot partially replace valid prior analysis;
omissions remain visible to the reconciliation gate.

Each root-scope `SymbolId` also requires at least one non-unknown
implementation claim and no unknown claim for each relation `precondition`,
`postcondition`, `effect`, and `raises`, with `site=None`. Multiple claims
per relation are allowed. A claim such as “no externally visible effect” is still a proposed
source description, not a proof. If a relation is missing or only unknown,
the host adds a symbol-scoped unknown claim using the same deterministic gap
rule with `site=None`.

Canonical JSON v1 accepts UTF-8 strings, signed 64-bit integers, booleans,
null, arrays, and objects. It rejects floats and duplicate object keys. Object
keys are sorted by UTF-8 byte order; array order is preserved; integers use
minimal base-10 notation; strings are not Unicode-normalized, escape `"`, `\\`,
and U+0000–U+001F as `\\u00xx` with lowercase hex, and leave other UTF-8 bytes
unchanged. `/` is not escaped. This rule is used for ClaimIds, UnitIds, and
tool `value_json`.

The relation field provides a common Hoare-style vocabulary for preconditions,
postconditions, visible effects, failures, and per-site guards/outcomes. The
`statement` remains proposed natural language in v1; it is not a machine
predicate and cannot receive `proved` status without a future verifier
adapter. The v1 implementation has no such adapter, so its formal proof
status is always `not_proved`; passing project checks is reported separately.

Claims are epistemically distinct by `kind`. An implementation observation
does not become an intent. An inference or assumption does not become a
requirement. An assumption used at a call site retains its claim ID and
status; composition cannot upgrade it.

### 4.3 `ReconciliationSpec`

```text
ReconciliationSpec {
  basis_hash: Hash               # canonical hash of all inputs listed below
  region_symbols: [SymbolId]
  region_paths: [RelativePath]
  dispositions: [Disposition]   # one per mismatch/unknown/check-failure claim
  design: String
}

Disposition {
  claim_id: ClaimId
  action: repair | needs_user_input
  rationale: String
  question: optional String
  evidence: [EvidenceRef]
}
```

`region_paths` may include new files, but every path must match `write` and
`inspect` when added to a candidate. `region_symbols` must exist in the
current parent `Index`. `Analysis` contains claims only for the deterministic
root scope plus host-generated workflow-level check claims. Therefore the
relevant-claim set is exactly every `mismatch`, `unknown`, or `check_failure`
in `Analysis`, independent of the model-selected rewrite region. The planner
cannot hide a claim by shrinking that region. There must be exactly one
disposition per relevant claim. A `mismatch` is already validated as a
conflict between an observed claim and explicit TaskRef-grounded intent. An
`unknown` must remain explicit unless a rewrite removes its cause and
rederivation supplies a complete replacement. A `check_failure` is the
deterministic fact that a declared candidate check exited nonzero. Trust
boundary assumptions are not unknowns and cannot be used to relabel one.

For `repair`, the region must contain every cited source path and every
in-scope subject symbol; a cited GapRef also contributes its Gap.path when
present. `region_paths` must include the source path of every listed
`region_symbol`. A check failure with no source subject requires at least one
authorized `region_path`. Every disposition cites its target ClaimRef; its
evidence is sorted and duplicate-free. `rationale` is nonempty; `question`
is absent for `repair` and nonempty for `needs_user_input`. The region must be
within both inspection and write authority. For `needs_user_input`, its
`rationale` states why the answer affects the design; any such disposition terminates
before rewrite. Disposition arrays and region symbol/path arrays are sorted
and unique; dispositions sort by ClaimId. `basis_hash` is SHA-256 of
canonical JSON for `{original_snapshot_hash, spec_sha256,
index_artifact_hash, analysis_artifact_hash, tool_result_hash,
parent_tree_hash, check_result_hashes, rewrite_diagnostic_hash,
attempt_number}`. The values are TreeHash of the original source snapshot,
exact spec file SHA-256, ArtifactHash(Index), ArtifactHash(Analysis),
optional ArtifactHash(ToolResult) or null, TreeHash of the current parent,
an ordered array of `{attempt, check_name, process_result_hash}` for the
baseline (attempt 0) and candidate checks in attempt/name order, SHA-256 of
canonical JSON for RewriteDiagnostic records ordered by attempt (SHA-256 of
canonical JSON for the empty list when empty), and the next rewrite attempt
number. `design` describes the new structure,
interfaces, and how intent is preserved. It may propose a subsystem rewrite
or a small change. Diff size is not a tie-breaker unless `task` explicitly
says so.

### 4.4 `Candidate`

```text
Candidate {
  tree: BlobTree
  parent_hash: Hash              # TreeHash of the prior working tree
  analysis_hash: Hash            # Analysis used to render this candidate's comments
  plan_hash: Hash                # ArtifactHash(ReconciliationSpec)
  attempt: int                   # 1..3
  changed_paths: [RelativePath]  # sorted byte-diff from initial snapshot, including comments
  check_results: [CheckResult]   # sorted by check name
}

CandidatePatch {
  upserts: BlobTree             # changed or new regular files only
  deletes: [RelativePath]
}

CheckResult {
  name: String
  baseline: ProcessResult
  candidate: ProcessResult
}

CandidateAssessment {
  candidate_hash: Hash
  decision: satisfied | partial | revise | needs_user_input
  remaining_claims: [ClaimId]
  rationale: String
  question: optional String
}

RewriteDiagnostic {
  attempt: int                 # 1..3
  parent_hash: Hash             # TreeHash
  plan_hash: Hash               # ArtifactHash(ReconciliationSpec)
  kind: patch_invalid | candidate_gate_rejected | no_progress
  errors: [String]             # deterministic host messages, sorted and unique
}
```

The static flow `run_check: (Check, BlobTree) ~> ProcessResult` lowers to
`ProcessRequest.ProjectCheck`. Project checks use the same sandbox service as
generated tools, with the candidate tree mounted read-only and the declared
toolchain registry controlling child executables. Build and test outputs go
to the private scratch path.
The check result is pass iff `ProcessResult.status=exited` and
`exit_code=Some(0)`; otherwise it is fail or unknown according to the exact
status. `CheckResult` retains both complete process envelopes so the planner
can inspect bounded stdout/stderr without reconstructing them from paths.

Only a host-valid candidate is stored as a `Candidate` artifact; invalid
outputs are recorded as attempt diagnostics and never enter the candidate
set. The original source tree is immutable. Each rewrite starts from the
latest host-valid candidate, even if its checks failed, so the next attempt
can repair that tree. The best candidate is the most recent host-valid
candidate for which every required check passed; it is selected from
committed Candidate artifacts, not maintained as a second mutable copy. The
`analysis_hash` is `ArtifactHash(Analysis)` for the analysis used to render
this candidate's comments; the host verifies its `spec_sha256` against the
input spec and its `index_hash`/snapshot against the candidate projection.
The host applies `CandidatePatch` to produce the entire stored tree. Delete paths
are sorted and unique, and no path appears in both upserts and deletes.
Every LLM patch path must be in `region_paths` and match both `write` and
`inspect`; the patch is rejected whole on any violation. After rederivation,
the host updates generated comments for every root-scope symbol whose source
file matches both `write` and `inspect`. These deterministic comment changes
need not be in `region_paths`; they are never LLM patch content. Candidate
`changed_paths` is exactly the sorted set of paths in the union of the
candidate and initial snapshot whose file is absent on one side or has
different stored bytes; it includes generated comment changes. Every path must still match `write` and
`inspect` and be representable by `BlobTree`. It also
requires every matched
trust-boundary symbol's `implementation_hash` to remain identical. It never
silently filters unauthorized edits. A candidate whose comment-free
projection has the same TreeHash as its parent is `no_progress`; this is a
derived comparison, not a patch rejection. The host immediately records a
`no_progress` diagnostic for that attempt so any later plan sees it. The candidate still proceeds
through rederivation, comment rendering, checks, and assessment. If the
assessment says `revise` with no code progress, the workflow records
`rewrite_no_progress` and returns `PARTIAL` instead of repeating the same
plan. Generated comments never count as code progress.

Each invalid rewrite attempt commits one `RewriteDiagnostic` as a SQLite run
event, not as a second mutable worklist. The planner receives the ordered
diagnostics from this run. Invalid patches and candidate-gate rejections
preserve the exact sorted host validator messages. A no-progress diagnostic
has the sole error string `rewrite made no code progress`. If an assessment
requests `revise` for a no-progress candidate, the host adds
`host_workflow_unknown(rewrite_no_progress, "rewrite made no code progress")`
and terminates as `PARTIAL`; it does not add a duplicate diagnostic. The
`ReconciliationSpec.basis_hash` includes the
hash of the ordered diagnostic sequence, so a new plan cannot be reused after
different feedback.

The deterministic assessment gate accepts `satisfied` only when
`remaining_claims=[]`, every required candidate check is `pass`, every
root-scope site is specified, and no relevant mismatch, unknown,
check_failure, or gap remains; every disposition in the current plan is
`repair`. This resolves the plan's repair dispositions
collectively; no model-authored old-to-new claim mapping is needed. For
`revise`, `remaining_claims` is exactly the nonempty current relevant-claim
set. For `partial`, it is exactly that set and the set contains an unknown.
For `needs_user_input`, it is a nonempty subset of current relevant claims and
`question` is nonempty. `candidate_hash` must equal the actual candidate
`TreeHash`; claim lists are sorted and unique; `rationale` is nonempty;
`question` is absent except for `needs_user_input`. The host rejects
an invalid assessment and makes one explicit correction call; a second
invalid result terminates as `PARTIAL` with
`host_workflow_unknown(invalid_assessment, "Candidate assessment remained invalid after correction")`.

## 5. Generated tools

Generated tools are useful for project-specific parsing, summaries, or
measurements. They are executable, untrusted code. They may provide extra
observations; they cannot define symbols, close an unknown, approve a plan,
select a checker, or set a proof status.

After both kernels, one tool planner receives the `Index`, `Analysis`, and
`task`; it returns `none` or one `ToolRequest`. The request contains the
purpose, selected GapIds (which may be empty for a task-directed measurement),
and a fixed list of in-scope relative paths and hashes. GapIds and file paths
must be sorted and unique; every GapId must exist and every path must match
`inspect`, with the exact frozen file hash. The builder receives this request
and returns `ToolPackage { source: Blob }`. The only accepted file is
`tool.py`, at most 1 MiB, valid UTF-8, and without NUL; no dependency
installation is available. Python runs with isolated mode and site loading
disabled, so ambient and installed packages are unavailable. The script can
read only the selected source files as data. The package declares no schema
and cannot choose its permissions. The workflow supplies those from the
fixed ABI. If no tool is
requested, the workflow continues with existing gaps. If a package fails ABI
envelope validation (empty source, invalid UTF-8, NUL, or size limit), one
repair turn includes the validator's exact error; a second failure ends the
tool branch as unavailable. This check does not execute or certify the
package. Output-schema/evidence rejection after execution is a `ToolResult`
status and is not retried.

The transport records are:

```text
ToolRequest {
  gap_ids: [GapId]
  purpose: String
  files: [{ path: RelativePath, sha256: Hash }]
}
ToolPackage { source: Blob } # materialized to fixed path tool.py
```

The runner invokes the package through the new static `run_tool` flow with
fixed virtual paths inside both executions:

```text
argv = ["/toolchain/python3/bin/python3", "-I", "-S", "-B",
        "/workspace/tool.py", "/workspace/request.json", "/workspace/source"]
```

The `/toolchain/python3` mount maps to one fixed registry ID and its pinned
interpreter/standard-library hashes. `/workspace` has the same layout in both
clean executions, with the package, request, and selected source mounted at
the paths above. No ambient `PATH`, user site packages, or external Python
packages are used. Stable virtual paths prevent sandbox-specific host paths
from becoming accidental tool input.

`purpose` is a nonempty UTF-8 tool-specific instruction of at most 16 KiB;
the builder receives only that purpose, the selected gap records, and the
selected file bytes. It does not get a duplicate copy of the overall task.
The request JSON is UTF-8 canonical JSON:

```json
{"abi":1,"files":[{"path":"...","sha256":"..."}],"gaps":[{"id":"...","owner":"...","path":"...","reason":"...","site":"...","span":[0,1]}],"purpose":"..."}
```

The `gaps` array is sorted by GapId and contains exactly the requested gaps;
optional path/span/owner/site values are JSON null when absent. `files` is
sorted by path and contains exactly the requested subset. The source root is
read-only. The script writes no source files; it emits exactly one
JSON object to stdout and diagnostics to stderr:

```json
{"abi":1,"gaps":[{"path":null,"reason":"..."}],"observations":[{"evidence":[{"end_byte":1,"path":"...","sha256":"...","start_byte":0}],"kind":"...","value_json":"..."}]}
```

Each `value_json` must parse as JSON. Every evidence path/hash/span must name
bytes in the request. The stdout JSON parser rejects duplicate keys; output
object order is unrestricted and is normalized by the host. Output size is at most 10 MiB; stderr is capped at 1
MiB. Unknown keys, wrong ABI, invalid JSON, path escape, fabricated evidence,
nonzero exit, timeout, or out-of-limit output rejects the tool result. Gap
paths must be in the request or null for a request-wide gap. The host parses
each `value_json`, canonicalizes it, then sorts observations and gaps by
complete canonical encoding before comparison. Valid tool outputs are stored
with the tool source, request, interpreter/standard-library hashes, runner
version, and output hashes.

The runner MUST execute twice in clean sandboxes with identical bytes. A
completed `run_tool` stores exactly two `ProcessResultHash` values, including
when a launch fails or isolation is unavailable; a crash before commit stores
no `ToolResult` and resume may rerun the node. It compares process status,
exit code, stderr bytes, and stdout: when both stdout values are valid ABI
objects it compares their normalized canonical values; otherwise it compares
the raw stdout bytes. Any difference means `nondeterministic`. If equal
executions are not both `exited`, the
result is `unavailable`. If equal executions exited nonzero or their output
fails the ABI/evidence validator, the result is `rejected`. It is `accepted`
only when both exited zero and produced the same valid normalized output.
Only `accepted` results expose observations/gaps and have an `output_hash`;
all other statuses have empty observation/gap lists and `output_hash=None`.
For `accepted`, `output_hash` is SHA-256 of canonical JSON for the sorted
normalized observations and gaps, and `diagnostic=None`. All non-accepted
results have a nonempty diagnostic. The sandbox MUST provide read-only
tool/source inputs, a private
writable temporary directory, no network, no host environment variables or
credentials, no child-process creation, and fixed resource limits (one CPU
core, 30 seconds, 256 MiB memory). If the host cannot enforce this isolation, `run_tool`
fails closed; it never runs generated code unsandboxed. Repeatability is
evidence about these two executions, not a proof of tool correctness.

A static `run_tool` flow has the type
`(ToolPackage, ToolRequest, BlobTree) ~> ToolResult` and lowers to
`ProcessRequest.GeneratedTool`. It is a wrapper over the new `run_process`
runtime operation. Its flow key includes ABI and runner version. Its
cache/idempotency key is SHA-256 of tool bytes, canonical request, source
snapshot, interpreter, runner version, and sandbox-profile hash. Checkpoint restore reuses only an
exact matching committed result. This is the connection to the artifact
system: blobs transport and persist the package; the runner gives that data
executable meaning. Artifact codecs alone do not execute it.

The fixed result type is:

```text
ToolResult {
  status: accepted | rejected | nondeterministic | unavailable
  tool_hash: Hash
  request_hash: Hash
  output_hash: optional Hash
  execution_hashes: [Hash]       # exactly two ProcessResultHash values
  observations: [ToolObservation]
  gaps: [ToolGap]
  diagnostic: optional String
}

ToolObservation { kind: String, value_json: String, evidence: [SourceRef] }
ToolGap { path: optional RelativePath, reason: String }
```

The host validates these result invariants before commit:
`tool_hash=SHA256(ToolPackage.source)`, `request_hash=ArtifactHash(ToolRequest)`,
and `output_hash` follows the normalized-output rule above;
`execution_hashes` has
exactly two entries; and status-dependent fields obey the rules above. Every
`ToolObservation` has at least one source reference into the requested file
set. Every `ToolGap.path`, when present, belongs to that set. `ToolRef` and
`ToolGapRef` may cite only an accepted result and its matching output hash.

Tool observations may mention candidate declarations, but they remain
`ToolRef`s in `Analysis`; the host does not insert them into `Index` or use
them to allocate symbol work. If the pinned frontend cannot enumerate a
declaration, that system remains partial.

## 6. Kernels and deterministic work allocation

### 6.1 Freeze and index

1. Hash the exact `BlobTree`, parsed spec, frontend, and runner versions.
2. Expand `inspect` and `write` against the source directory. Reject empty
   `inspect` or `roots`, and any existing path matched by `write` but not
   `inspect`.
   Parse and validate root/trust selector syntax; symbol matching waits for
   `Index`.
3. Run the pinned frontend on every inspected source file. Every selected
   file receives a parse status. No file is silently skipped.
4. Construct `Index`, canonical IDs, syntax call edges, branch/exit sites,
   and gaps. Sort by their specified keys. Then resolve root/trust selectors
   against indexed callables and call targets; reject no-match selectors or
   any root also selected as a trust target.

The deterministic interface is
`index(frontend_id, selected_file_bytes, selected_file_manifest,
toolchain_module_manifest) -> IndexRecords`. The path and module manifests
contain only normalized names and hashes for files in `inspect`; source bytes
are supplied only for those files. V1 registers the Nim 2.3.1 syntax adapter:
the parser source is vendored from that release, and its source hash plus the
adapter build hash are recorded in the workflow manifest. No adapter is
registered for another Nim version. The adapter tokenizes and parses without invoking semantic
analysis, macro expansion, project code, or compile-time evaluation. Its
resolver maps imports to an inspected source path or a module in the pinned
toolchain manifest. It resolves a call
only when lexical scope and canonical name identify exactly one declaration;
overloads not distinguishable without type analysis are ambiguous. An import
or call outside those rules is unresolved. Updating the parser, resolver,
module manifest, or adapter build changes `frontend_id` and invalidates the
Index. The adapter MUST emit the records in §4.1 from the exact input bytes
and MUST declare unsupported constructs. A language with no registered
adapter remains partial; a model-generated extractor is not a substitute.

### 6.2 Bottom-up behavior kernel

Resolve root selectors. Add each root module's `module_init` symbol and the
transitive module-init symbols of its resolved imports. Follow indexed call
edges from that root set until an exact `trust` selector matches. The scope is
this reachable set minus trust targets. Calls to trust targets produce
assumption claims and are not traversed. Unresolved/dynamic/ambiguous edges
produce gaps and unknown claims; they do not create guessed work units.

Compute strongly connected components (SCCs) of the scoped call graph. Define
`UnitId` as specified in §4.2, with phase `bottom_up`, the current
`index_hash`, exact `spec_sha256`, and the lexicographically sorted member
SymbolIds.
Sort SCCs callee-first by topological order of the caller-to-callee graph;
break ties by each SCC's minimum SymbolId. Implement this as Kahn's algorithm
on the reversed SCC DAG, choosing the ready SCC with the smallest minimum
SymbolId at each step. One bottom-up worker task is one SCC, which keeps
recursion together and makes allocation deterministic. Each
task receives only:

- each member's source slice, symbol record, and branch/exit/call site IDs;
- summaries for outgoing callees, with claim IDs and epistemic kinds;
- explicit unresolved/dynamic edges and declared external assumptions.

It returns `BehaviorUnitOutput { unit_id, claims: [ClaimDraft], gaps:
[GapDraft], site_cases: [SiteCaseDraft] }`. Draft IDs are unique within the
response and match `[A-Za-z0-9_-]{1,64}`. They are only local links from a site case to its
draft claims; the host removes them after calculating durable ClaimIds. The
worker returns kinds `observed`, `assumption`, or `unknown`, cites source
spans and already committed callee claims, and covers each member's every
indexed site. The host checks exact unit/site coverage, known IDs, source
hashes, required relations, and evidence by claim kind. On a malformed
response the worker receives one explicit correction call with validator
errors. After a second invalid response, the host fills all missing unit/site
relations with deterministic unknown claims and advances. The host does not
certify natural-language truth. Recursion stays in one SCC task; no status is
upgraded to proved because an SCC summary exists.

### 6.3 Top-down intent kernel

Traverse the same scope caller-first from the root set using Kahn's algorithm
on the SCC DAG, choosing the ready SCC with the smallest minimum SymbolId;
within each SCC, process members by ascending SymbolId. A top-down
`UnitId` uses phase `top_down`, current `index_hash`, exact `spec_sha256`, and
the single SymbolId. The scheduler, not a model-generated symbol list,
determines the work set. Each
worker receives the full decoded `task` string unchanged, root path, current symbol, its caller
and callee edges, bottom-up claims for that symbol/callees, and valid earlier
TaskRefs/ClaimRefs. It returns `IntentUnitOutput { unit_id,
claims: [ClaimDraft], gaps: [GapDraft] }` with kinds `intent`, `inference`,
`mismatch`, or `unknown`. It emits `mismatch` only when it cites both a
bottom-up `observed` claim and an explicit top-down `intent` claim grounded in
a TaskRef; likely intent inferred from context cannot support a mismatch.
Obligations passed to callees are `intent` claims whose subject is the callee
and whose evidence reaches the root intent claim. An empty claims list means
the task text states no explicit intent for this symbol. Any inferred intent
from neighboring code remains `inference`; it is never silently treated as
user intent. The same one-correction-then-host-unknown rule applies. A valid
empty result means no explicit task requirement; a missing/invalid result
after correction discards the response and creates a gap with
`path=SymbolRecord.path`, `span=SymbolRecord.span`,
`reason=invalid_top_down_output`, `owner=SymbolId`, and `site=None`.
The host adds one unknown claim with `relation=outcome`, that symbol as its
subject, statement `top-down intent output remained invalid after correction`,
and the sole evidence GapRef before marking the unit complete.

Every UnitId is recorded in `Analysis.completed_units` after either a valid
model result or host-generated unknown completion following its bounded
correction.
The next unit is the first not-yet-completed unit in the deterministic order;
the ordered unit list is recomputed from `Index`, `HardeningSpec`, and the
completed IDs. This single `Analysis` artifact is both accumulated result and
progress state; no separate mutable symbol worklist exists. An unresolved
edge or unsupported reachable file produces a gap. Analysis continues for
other reachable symbols, but the affected system remains partial.

### 6.4 Optional tool stage

After both kernels, the planner in §5 receives all current gaps, the
`Index`, `Analysis`, and task text. It returns `none` or one validated
`ToolRequest`. The request is sent to one builder call, then to `run_tool`.
The planner's exact output is this discriminated union:

```text
ToolPlanKind = none | request
ToolPlan = object
  case kind: ToolPlanKind
  of none: discard
  of request: request: ToolRequest
```

The deterministic validator checks that all GapIds exist, file paths are
unique/sorted/in-scope, and hashes match the frozen source. A request may
name at most 128 gaps, at most 64 files, and at most 8 MiB of selected source
bytes in total; its purpose is at most 16 KiB. These bounds are checked before
the builder sees file contents. An invalid planner response receives one
correction call with the exact validation errors; a second invalid response
skips the optional tool stage and records the failed model attempt. The
output is attached by ToolRef to the reconciliation input and report; it does
not modify `Index` or retroactively mark a site covered. If no tool is
requested, the workflow continues. A tool package that fails its envelope
check receives one correction call; a second failure skips the optional tool
stage and records the failed model attempt. These pre-execution failures
create no `ToolResult` because no process ran. A rejected, nondeterministic,
or unavailable executed tool result is recorded and passed to reconciliation
as such; the workflow does not retry it or treat its output as evidence.

### 6.5 Reconciliation specification

After the optional tool stage, one planning worker receives the full `Index`,
`Analysis`, original `task`, optional `ToolResult`, current parent tree/hash,
current check outputs, and ordered rewrite diagnostics. It proposes a
`ReconciliationSpec` at the scale needed to preserve intent and correct
behavior. It must associate every relevant mismatch/unknown/check-failure
claim with `repair` or `needs_user_input`. The region can
include multiple components and interfaces when one coherent redesign is
simpler or more correct. `needs_user_input` terminates with the complete
kernel artifacts and the exact question; the workflow does not infer the
answer. The user edits `task` and starts a new run.

The deterministic plan gate checks that:

1. every SymbolId, ClaimId, path, and evidence reference exists;
2. the rewrite region is wholly within inspection and write authority;
3. every claim in the deterministic relevant-claim set from §4.3 has exactly
   one disposition;
4. each repair region includes its claim subjects/source files and fits the
   authority plane;
5. each `needs_user_input` entry has a concrete question;
6. no claim is relabeled as proved by the plan.

The gate checks references and authority; it cannot determine whether a model
missed a semantic conflict. A malformed plan receives one explicit
correction call; a second invalid plan terminates as `PARTIAL` with
`host_workflow_unknown(invalid_reconciliation_plan, "Reconciliation plan remained invalid after correction")`.
The workflow reaches planning only after both
kernels have finished, so the report retains their complete results.

### 6.6 Rewrite, rederive, check

The rewrite worker receives the accepted plan, latest host-valid tree (or
original tree) projected without generated comment blocks, the projected
bytes for `region_paths`, the full decoded `task` string unchanged, and
current relevant claims. It never receives old generated spec comments as
editable source.
It returns `CandidatePatch`: upserts are complete contents of changed/new
files, and deletes name removed files. Renames are a delete plus an upsert.
The host applies the patch to the current parent tree, preserving every
unmentioned file, then validates per-attempt and cumulative paths. Every
changed path must be in `region_paths`, match `write`, and match `inspect`;
every upsert is a regular file and deletes must exist in the parent. The host
also requires all trust-boundary implementation hashes to remain unchanged.
Invalid output is discarded whole and the validator's exact error is supplied
to the one allowed correction call. The rewrite attempt is counted before
dispatch; a second invalid result consumes that attempt and leaves the prior
working tree unchanged.

For every host-valid candidate, the host re-indexes the whole inspected tree
and recomputes the root/trust scope, SCCs, and both kernels from scratch. The
model supplies no old-to-new symbol mappings. Root selectors and trust
selectors must still match; if a root disappears or a trust boundary changes,
the candidate is rejected with that exact reason. Full rederivation avoids
incremental cache/invalidation rules and prevents stale caller summaries.
The host then renders comments for every current root-scope symbol whose
source path matches both `write` and `inspect`, using current claims; this
avoids model-supplied old/new symbol mappings and refreshes comments on
untouched callers after a broader rewrite. The report serializes the complete
current `Analysis` for all root-scope symbols. Source comments are inserted
only in write-authorized inspected files. A symbol's block contains each
complete claim record whose `subjects` includes that symbol or whose non-null
`site` belongs to that symbol, including evidence; a multi-subject claim
appears in each subject's block. ClaimRefs carry the dependency links. The
exact block is plain Nim comments: one
`# vecherinka-spec:v1 begin symbol=<SymbolId> source=<FileHash>` line,
followed by one `# <canonical-JSON>` line per claim. Each claim line is the
complete canonical JSON `Claim` record from §4.2. Claims sort by Relation
enum order, then ClaimId. The block ends with
`# vecherinka-spec:v1 end`. Statements use the canonical JSON string encoder.
The pinned Nim lexer recognizes marker lines only when they are actual
full-line comments beginning in column zero; marker-like text inside a string
literal is ordinary source. A block consists of exactly one valid begin line,
zero or more canonical Claim JSON comment lines, and one end line. Its
`symbol` and `source` fields must have valid v1 ID/hash syntax; each claim
line must parse as a canonical `Claim` object. Before the initial index and
every later index, the host strips the byte range from the beginning of the
begin line through the end of the end line, including its line ending when
present. It preserves every other byte. Unmatched, nested, malformed, or
interrupted reserved markers fail preflight or reject the candidate. The
stored `source` hash is informational and need not match the current
projection, so edits to code do not make an old block impossible to remove.
The renderer appends blocks to the projected file in ascending SymbolId
order; it inserts one LF first only when a nonempty file does not end in LF,
and terminates every generated line with LF. `SourceRef`s and the
Index hash refer to this comment-free projection. The checked Candidate
contains the comments, whose
header records the projection's file hash. Thus rendering is deterministic
and does not create self-referential source hashes.

The host runs every configured check once against the baseline in precheck,
then once against each host-valid candidate. A check result includes exact
status, exit code, bounded stdout/stderr, executable hash, sandbox-profile
hash, and a process-result hash. Candidate checks use the same profile as the
baseline. A check passes only when its exact argv exits zero before timeout
or output limits. A nonzero exit produces check evidence and routes to a new
plan; `timeout`, `output_limit`, `unavailable`, or isolation failure terminates
as `PARTIAL` because the environment cannot establish the check result. A
baseline failure is recorded but is not itself a candidate failure. A
baseline process status other than `exited` prevents `COMPLETE`, even if a
later candidate invocation exits successfully. No model can override a check
outcome.

For each candidate check that exits nonzero, the host adds a
`check_failure` claim before planning. It has `relation=outcome`, no subject
or site, statement `check <name> returned exit code <integer>`, and evidence
`CheckSpecRef(spec_sha256, name)` plus `CheckRef(name, process_result_hash)`.
If `checks` is empty, the host adds a workflow-level unknown with reason
`no_checks_configured`, statement `No deterministic acceptance check was configured`,
relation `outcome`, no subject/site, and the GapRef. The workflow may create
one candidate, then returns `PARTIAL` without an assessment unless a valid
`needs_user_input` decision stopped it earlier. It never accepts `satisfied`
or `COMPLETE` without checks. If all candidate checks pass, one assessment worker receives
the original task, current claims, accepted plan, candidate, and exact check
outputs. `satisfied` stops only when the host gate
finds complete structural coverage for the root scope, no relevant unknown,
mismatch, or check_failure claim, every required check passed, and every plan
disposition is resolved. `partial` stops with at least one existing
unknown/gap claim.
`revise` routes to planning with existing remaining claims; the checked
candidate becomes the base for the next attempt. `needs_user_input` stops
with the nonempty question. Assessment of the user's prose goal remains a
model judgment and is not proof; v1 always reports formal proof status
`not_proved`.

## 7. State machine, bounds, and terminal results

The durable phase is derived from committed artifact/checkpoint records:

```text
PRECHECK
  invalid input or unsafe tree entry -> FAILED
  otherwise run every baseline check
  any baseline status != exited -> PARTIAL
  all baseline checks exited (exit code may be nonzero) -> INDEX

INDEX
  selector/scope validation failure -> FAILED
  otherwise -> BOTTOM_UP

BOTTOM_UP
  process first uncompleted SCC; when none remain -> TOP_DOWN
TOP_DOWN
  process first uncompleted symbol; when none remain -> TOOL_PLAN

TOOL_PLAN
  no tool, or invalid ToolRequest after one correction -> PLAN
  valid request -> TOOL_BUILD

TOOL_BUILD
  valid package -> TOOL_RUN
  invalid package after one correction -> PLAN (no ToolResult was executed)

TOOL_RUN
  run exactly twice as specified in §5; create ToolResult -> PLAN
  any ToolResult status is recorded; it never blocks PLAN

PLAN
  invalid output after one correction -> add
    host_workflow_unknown(invalid_reconciliation_plan, ...), then PARTIAL
  any needs_user_input disposition -> NEEDS_INPUT
  valid plan with attempts remaining -> REWRITE
  valid plan with no attempts remaining -> EXHAUSTED

REWRITE
  increment attempt before the first worker call
  invalid patch or host candidate-gate failure -> give exact errors one
    correction call; if still invalid, retain parent and go to PLAN when
    attempts remain, otherwise EXHAUSTED
  any valid patch -> record no_progress if its comment-free tree equals the
    parent projection; reindex, render comments, run kernels, then CHECK

CHECK
  any candidate status != exited -> PARTIAL
  any candidate exit code != 0 -> add host check_failure claim; PLAN when
    attempts remain, otherwise EXHAUSTED
  all candidate checks pass and checks nonempty -> ASSESS
  checks empty after one valid candidate -> PARTIAL

ASSESS
  invalid output after one correction -> add
    host_workflow_unknown(invalid_assessment, ...), then PARTIAL
  needs_user_input -> NEEDS_INPUT
  partial with valid remaining claims -> PARTIAL
  satisfied with every deterministic gate true -> COMPLETE
  revise with code progress and attempts remaining -> PLAN
  revise with no code progress -> add host no-progress unknown, then PARTIAL
  revise with no attempts remaining -> EXHAUSTED
```

`FAILED`, `PARTIAL`, `NEEDS_INPUT`, `EXHAUSTED`, `COMPLETE`, and
`INTERRUPTED` are terminal. The external deadline supervisor may move any
nonterminal phase to `INTERRUPTED`; resume continues from the last committed
checkpoint. Baseline checks run once in `PRECHECK`; their `ProcessResult`s
remain fixed for the run and are copied by hash into each `CheckResult`.
Candidate-gate rejection includes write-authority violations, changed trust
implementations, missing roots/boundaries, malformed source, and invalid
comment markers. These are fed back through the same single correction call
as a malformed patch.

Every state transition commits its input hashes, output artifact ID, and
status before scheduling the next state. A resumed run reuses a stage only
when all declared input hashes and tool versions match. Any source/spec/
frontend/runner change invalidates dependent results. Work order and unit IDs
are derived from `Index` and the spec; `Analysis.completed_units` records
accepted outputs so replay selects the same next unit. No model-authored
inventory is persisted as control state.

Version 1 uses fixed limits: three rewrite attempts total; one correction call
for each malformed model result; one builder correction after a pre-run tool
package-envelope validation failure; and exactly two executions per completed
tool-run node.
Every generated solve sets Vecherinka `finish_work_retry_limit=0`; the
workflow's explicit correction node is the only model-output retry. A rewrite
attempt is counted before dispatch, so malformed output, no progress, and
nonzero checks all consume one attempt. Each snapshot gets at most one
bottom-up task per SCC and one top-down task per symbol. With `B` bottom-up
SCCs and `N` root-scope symbols per snapshot, at most four complete analysis
passes occur (original plus three rewrite candidates), four plans, three
rewrite workers, and three assessments occur. Let `Bmax` and `Nmax` be the
maximum SCC and symbol counts across those snapshots. Including one correction
per model result, the LLM-call upper bound is
`2 * (4*(Bmax+Nmax) + 4 + 3 + 3 + 2)`: plans, rewrites, assessments, and the
optional tool planner/builder respectively. The caller must supply a finite
run deadline to the
external supervisor. The supervisor launches the solve as a child process.
On deadline it terminates and reaps the whole child process group, then opens
the SQLite store, records an `INTERRUPTED` event against the last committed
checkpoint, and writes the interruption report. `resume` may clear that
terminal marker and continue from the checkpoint; any process operation that
exited before its artifact commit may run again.

Terminal meanings:

- `COMPLETE`: the assessment says `satisfied`; every root-scope symbol and
  site is covered; every reached call is resolved internally or matches a
  declared trust boundary; the check list is nonempty and every candidate
  check passes;
  every baseline check launched and exited (its exit code may be nonzero);
  every disposition is resolved; and no relevant unknown, mismatch, or
  check_failure remains. It means the bounded workflow completed against the
  task text. It does not mean formal proof; v1 always reports
  `formal_proof_status=not_proved`.
- `PARTIAL`: a candidate may exist, but a root-scope unknown, unsupported
  construct in that scope, unresolved mismatch, or unavailable required
  check prevents `COMPLETE`. Failure of an optional generated tool alone does not prevent
  `COMPLETE`; its associated source gap must still be resolved by other
  evidence or remain a relevant unknown.
- `NEEDS_INPUT`: the report identifies the exact missing user decision,
  authority, or assumption. All completed independent analysis is retained.
- `EXHAUSTED`: the rewrite limit ended without an assessment of `satisfied`;
  report the best checks-passing candidate, if one exists, otherwise the
  latest host-valid candidate, plus every attempt diagnostic and check result.
- `FAILED`: invalid input, corrupt artifact, or an unrecoverable runtime
  error. Preserve the last committed artifacts and diagnostic.
- `INTERRUPTED`: the finite caller deadline or runtime budget stopped work;
  preserve the last committed artifacts and resume from that checkpoint.

The report is always generated for a terminal state. It contains source and
spec hashes, frontend/tool versions, inventory coverage, behavior and intent
claims with evidence, reconciliation plan, changed paths, baseline/candidate
check results, terminal status, and exact unresolved obligations. Its main
claim set is for the exported candidate: it loads the exact `Analysis` named
by `Candidate.analysis_hash`, then loads its `Index` by `Analysis.index_hash`.
The host verifies the analysis spec hash and that the index snapshot hash
matches the candidate's comment-free projection. The report also lists
per-attempt plans, analyses, candidates, and checks by content hash. If no
candidate exists, the main claim set is the latest committed analysis.
Generated comment blocks carry the projected source hash and claim IDs; they
are readable references to the proposal, not proof.

## 8. Implementation boundary

Implementation order:

1. Add the strict spec parser and a scope-first source collector that resolves
   the explicit source root, expands `inspect` without following symlinks,
   snapshots only matched regular files, and reports matched unsupported
   entries before model work.
2. Define exact artifact object types and validators for `Index`, `Analysis`,
   `ReconciliationSpec`, `CandidatePatch`, `Candidate`, `ToolPackage`,
   `ToolRequest`, `ToolResult`, and process/check results. Add all endpoint
   types statically to the workflow so compile-time codec generation sees
   them.
3. Implement the pinned Nim syntax/import adapter as deterministic host code
   and a pure typed flow. Do not invoke project semantic analysis or macros.
4. Extend the DSL/compiler/runtime/checkpoint path with the static
   `run_process` flow described in §2, plus the versioned tool registry,
   streaming output caps, process-tree termination, and an OS isolation
   backend that passes every fail-closed policy in §2. An unavailable backend
   means no tool/check execution and can never yield `COMPLETE`.
5. Implement the one-SCC bottom-up loop and one-symbol top-down loop over
   deterministic unit IDs; merge model drafts and host-generated unknowns
   into the single `Analysis` artifact.
6. Implement optional tool planning/execution, reconciliation validation,
   CandidatePatch application, comment projection/rendering, full
   rederivation, check loops, bounded assessment, and report generation.
7. Implement the external supervisor contract in §7 before documenting the
   workflow as runnable.

The LLM-authored Python package is a normal `Blob` artifact whose codec is
compiled into the static workflow. It does not instantiate a runtime flow or
callback. Only `run_process` gives the bytes executable meaning, under its
fixed ABI and OS sandbox. The current Vecherinka artifact-instantiation path
alone cannot run generated source code.
