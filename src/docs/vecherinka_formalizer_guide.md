# Formalizer workflow

[`vecherinka_formalizer.nim`](../examples/vecherinka_formalizer.nim) reads a
proposal, required-change comments, and a mandatory intention file. Its
[pseudocode](../examples/vecherinka_formalizer.pseudocode) describes the graph.
It writes `formalization.typ` and
`formalization-audit.typ` to a new output directory. Both files are standalone
Typst source. The run's SQLite database stores the workflow artifacts,
conversation events, and checkpoints.

## Build and run

From the repository root, build the executable:

```sh
nim c --panics:on --threads:on --path:src/api \
  --out:/tmp/vecherinka_formalizer src/examples/vecherinka_formalizer.nim
```

Set up `PATH`, `CODEX_HOME`, and `CODEX_SQLITE_HOME` as described in
[AGENTS.md](../../AGENTS.md), then start a run:

```sh
PATH="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS:$PATH" \
CODEX_HOME="$PWD/.codex-task-state" \
CODEX_SQLITE_HOME="$PWD/.codex-task-state" \
/tmp/vecherinka_formalizer \
  proposal.typ comments.md intention.md \
  formalizer-output run-formalizer.sqlite3
```

The three input paths may use any filenames; their contents are read as Blobs.
There is no workflow-defined input byte cap. The output directory is created
if needed. The program refuses to overwrite
either output file, so use a new output directory and database path for each
run. Keep the SQLite path and its `-wal`/`-shm` sidecars together.

The program prints the SQLite path before starting. To watch a live run from a
second terminal, wait for the database and sidecars to appear, then run
`/Users/alex/areas/productive/orchestration/tools/vecherinka-tui` with that
database path.

After an interruption, use the same executable and database path to resume:

```sh
PATH="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS:$PATH" \
CODEX_HOME="$PWD/.codex-task-state" \
CODEX_SQLITE_HOME="$PWD/.codex-task-state" \
/tmp/vecherinka_formalizer --resume \
  run-formalizer.sqlite3 formalizer-output
```

Resume can take over a stale owner after the runtime's heartbeat window; do
not resume while the original process is still active. Use a new output
directory if the original run already wrote its files.

## Workflow and usage bounds

1. One medium-effort Luna call inventories source-linked obligations, conflicts,
   and gaps. It must preserve all relevant items within an eight-item cap or
   mark the inventory incomplete. An incomplete inventory produces a Typst
   notice and audit instead of a partial formalization.
2. `lift(seq[here])` maps each inventory item independently. A typed `so`
   sends only obligations to medium-effort Luna calls; gaps and conflicts pass
   through without another model call. Each mapper receives only its item.
3. One high-effort Luna call synthesizes a concise candidate specification.
4. Four independent audits run in parallel: source coverage (high), intention
   alignment (high), formal rigor (xhigh), and Typst structure (medium). The
   source-coverage auditor checks the original files; the other auditors get
   only the compact inventory and candidate.
5. A typed `so` checks the findings' `action`. If any finding is marked
   repairable, one xhigh repair runs, followed by the same four audits once.
   There is no recursive repair loop. Unresolved findings remain in the audit.
6. A medium-effort Luna call writes the Typst audit. The formalization Blob is
   passed through unchanged.

Every model is GPT-6 Luna, and medium is the lowest effort used. The declared
fixed budget is 17.5 units. Given the eight-item and four-finding limits, the
workflow's maximum scheduled fixed estimate is 16.88 units across at most 20
model nodes, including one repair and a second audit pass. These are admission
estimates, not provider charges; protocol turns and retries are not charged by
Vecherinka. Prompts restrict
work to the supplied files and requested outputs, forbid browsing and
delegation, and bound finding lengths. Input and finding lengths are also
checked locally before their values continue through the graph.

The workflow does not compile Typst. Its Typst audit checks the source for
obvious structural problems and does not claim compiler validation. Inspect
the run with the [SQLite TUI guide](vecherinka_tui_guide.md), or query the
database directly.
