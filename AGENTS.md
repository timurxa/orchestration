# Running Vecherinka workflows

Run from the repository root. The example below writes `parallel-research.jsonl`
and a `run-*` directory under the current working directory.

```bash
cd /Users/alex/areas/productive/orchestration
CODEX_HOME="$PWD/.codex-task-state" \
CODEX_SQLITE_HOME="$PWD/.codex-task-state" \
nim c -r --panics:on --threads:on --path:src/api \
  src/examples/vecherinka_parallel_research.nim
```

The child `codex app-server` needs writable Codex state, valid authentication,
and outbound access to the Codex service. If `.codex-task-state/` is missing or
stale, create or refresh this physical copy from a normal Terminal while Codex
and other `codex` processes are closed:

```bash
mkdir -p .codex-task-state
chmod 700 .codex-task-state
ditto "/Users/alex/Library/Application Support/CodexState/." \
  "$PWD/.codex-task-state/"
```

This copy may contain authentication data. It is ignored by Git; do not commit
or expose it. A symlink to the external state directory is insufficient in a
restricted task sandbox.

## Runtime limits

- The generated agent uses `approval_policy=never` and
  `sandbox=danger-full-access`. The prompt's working-directory limit is not an
  OS-enforced boundary. Run only trusted workflows in an isolated disposable
  checkout or worktree.
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
