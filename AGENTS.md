# Running the Nim Codex integration

This project starts a child `codex app-server`, which must be able to write
Codex state and reach the Codex service.

## Codex task sandbox

The Codex task sandbox can write inside this repository but may not be allowed
to write to the normal macOS state directory under `~/Library/Application
Support`. Keep a physical, task-local copy of the state at
`.codex-task-state/`; a symlink to the external directory is not sufficient.

Create or refresh the copy from a normal Terminal while Codex and other
`codex` processes are closed:

```bash
cd /Users/alex/areas/productive/orchestration
mkdir -p .codex-task-state
chmod 700 .codex-task-state
ditto "/Users/alex/Library/Application Support/CodexState/." \
  "/Users/alex/areas/productive/orchestration/.codex-task-state/"
```

The copied state can contain authentication data. Never commit it or expose
it; `.codex-task-state/` is ignored by `.gitignore`.

Run the build with both state variables pointed at the existing local copy:

```bash
CODEX_HOME="/Users/alex/areas/productive/orchestration/.codex-task-state" \
CODEX_SQLITE_HOME="/Users/alex/areas/productive/orchestration/.codex-task-state" \
nim c -r --panics:on --threads:on -d:debug src/main.nim
```

To run an already-built binary, use the same environment variables:

```bash
CODEX_HOME="/Users/alex/areas/productive/orchestration/.codex-task-state" \
CODEX_SQLITE_HOME="/Users/alex/areas/productive/orchestration/.codex-task-state" \
./src/main
```

The network permission is separate from the filesystem fix: the child
app-server needs outbound access to complete an end-to-end run. Without it,
startup may succeed but requests will fail or retry.
