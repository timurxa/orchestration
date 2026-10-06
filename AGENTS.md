# Running Vecherinka workflows

Run from the repository root. The example below writes a `run-*` directory
containing `vecherinka.sqlite3` under the current working directory. SQLite is
the durable artifact, graph, conversation, and checkpoint store; the model's
filesystem workspace is temporary staging.

```bash
cd /Users/alex/areas/productive/orchestration
PATH="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS:$PATH" \
CODEX_HOME="$PWD/.codex-task-state" \
CODEX_SQLITE_HOME="$PWD/.codex-task-state" \
nim c -r --panics:on --threads:on --path:src/api \
  src/examples/vecherinka_parallel_research.nim
```

The child `codex app-server` needs writable Codex state, valid authentication,
and outbound access to the Codex service. GPT-6 Luna requires a CLI/model
catalog that includes `gpt-6-luna`; the system Homebrew CLI 0.146 rejected it,
while the app-bundled CLI 0.160 succeeded. `codex_runtime` resolves `codex` via
`PATH`, so put a compatible executable first. If `.codex-task-state/` is
missing or stale, create or refresh this physical copy from a normal Terminal
while Codex and other `codex` processes are closed:

```bash
mkdir -p .codex-task-state
chmod 700 .codex-task-state
ditto "/Users/alex/Library/Application Support/CodexState/." \
  "$PWD/.codex-task-state/"
```

This copy may contain authentication data. It is ignored by Git; do not commit
or expose it. A symlink to the external state directory is insufficient in a
restricted task sandbox.

The Luna profile maps to `gpt-6-luna`. Verify the example's `run-*` SQLite
database reaches `finished` before treating a live workflow run as successful.

## Runtime limits

- Generated Codex agents use `approval_policy=never` and
  `sandbox=workspace-write`, with each model call's working directory as its
  cwd. The child can write its workspace, so run workflows only in an
  isolated disposable checkout or worktree.
- The research example requests current sources, but Vecherinka configures no
  search/retrieval tool. Source access depends on tools available to the child
  app-server; a prompt cannot provide browsing by itself. Verify sources in
  the resulting report.
- The run loop has no deadline or cancellation API. A request that stalls
  while the app-server remains alive can leave the caller waiting indefinitely.
- `initial_budget` is a fixed admission estimate, not measured provider spend.
  Retries and protocol turns are not charged; see
  [the budgeting contract](src/docs/vecherinka_budgeting_spec.md).

The repo has no `src/main.nim`; compile a specific example as above. The
workflow language and supported shapes are documented in the
[DSL guide](src/docs/vecherinka_dsl_guide.md).

Generated workflows expose `resume_<solve>(database_path, ...)`. Preserve the
database path selected by the caller, or locate it under `run-*/`, to resume
after interruption.
Dynamic `so` callbacks must be deterministic and side-effect free because
resume rebuilds their returned graph from the saved input and budget snapshot.
