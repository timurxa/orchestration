# Codebase hardening workflow

Compile from the repository root:

```sh
nim c --panics:on --threads:on --path:src/api \
  --out:src/examples/vecherinka_codebase_hardening \
  src/examples/vecherinka_codebase_hardening.nim
```

Run the compiled program with absolute paths for the codebase, its hardening
spec file, a new output directory, and the SQLite database:

```sh
src/examples/vecherinka_codebase_hardening \
  /path/to/codebase /path/to/hardening-spec.yaml \
  /path/to/hardening-output /path/to/run/vecherinka.sqlite3
```

The output directory contains `candidate/` and `hardening-report.md`. The
database stores workflow state and supports resuming through the generated
`resume_solve_codebase_hardening` procedure.

The hardening spec is a separate input file. It defines scope, requested
hardening degrees, and requirements; see
[`vecherinka_codebase_hardening.spec.yaml`](vecherinka_codebase_hardening.spec.yaml)
for an example. `formalize` records current behavior first, `reconcile`
compares and assimilates mismatches, `propose` creates an explicit plan,
`rewrite` applies supported proposals, and `review_candidate` checks the
candidate against the original behavior and plan. Review is a bounded repair
loop: rejected checks trigger a targeted repair followed by another review,
for at most two repair passes. It stops early when no checks are rejected.
Unknown checks remain unresolved and do not authorize edits; after the pass
limit, any remaining rejected checks are reported.

The output report includes the repair-pass count. This automated static review
does not run project tests or establish formal proof.

The workflow gives every source snapshot the same materialized root name,
`codebase`; the caller's directory name does not enter model paths. The
executable requires absolute CLI paths, so its working directory cannot change
which source, spec, output, or database it uses.

Run it from an isolated disposable checkout: the execution agent can write the
candidate workspace. The workflow does not run project tests or prove
correctness; inspect the report's supported, rejected, and unknown findings,
then run the relevant checks on the candidate yourself.

For Codex authentication and child-process setup, follow the repository's
`AGENTS.md` workflow instructions. In particular, make a physical writable
`CODEX_HOME`/`CODEX_SQLITE_HOME` state copy and put a compatible Codex CLI on
`PATH` before running.
