# Stepping-stone test progress

Started: 2026-09-13
Baseline commit: `89d275c savepoint`

## Protocol

- Every execution used finite `gtimeout --signal=TERM --kill-after=5s 120s`.
- Model profile stayed `gpt-5.6-luna`. No subagents used during execution.
- Successful runs used default `AgentPromptTemplates`; no model-behavior prompt
  fix was needed. Any future prompt fix may change `AgentPromptTemplates` only.
- Each completed run was checked for direct typed output, structured events,
  expanded generated flow graph, run artifact directories, and unrequested files.
- No run was repeated for variance. Reruns only followed harness corrections.
- No hard reset performed; changes remain recoverable untracked test artifacts.

## Stage status

| Stage | Status | Evidence |
|---|---|---|
| 0. Harness/baseline | passed | exact marker; one model graph |
| 1. Single model call | passed | exact two-field object copy |
| 2. `pure` + `>>>` | passed | raw seed, `so`, sequential model |
| 3. `fan` | passed/limited | fan-only passes; fan-to-follow-up blocked by R-001 |
| 4. `so` | passed | model and pure routes exact |
| 5. `it` | passed | field projection exact; ignored field absent |
| 6. `Location` | passed | input copied; declared output file exact |
| 7. Sequence lift | passed | two-item lift order/cardinality exact |
| 8. Option/tuple/object lift | passed | present/absent/reconstruction exact |
| 9. Variants/arrays/aliases | passed/limited | variant/named tuple pass; fixed output blocked by R-002 |
| 10. Advanced composition | passed | all currently usable features composed |

## Trial log

### 0. Baseline

- Trial 0: compile failed because test module omitted `std/macros`; no execution.
  Fixed import.
- Trial 1: passed. Exact marker. One `fk_model`, one `model.finish`, clean
  `run-dgilEBRL/artifact-1`.

### 1. Single model call

- Trial 2: compile passed, but `nim c -r ... -- stage-1` passed literal `--` to
  program; no execution.
- Trial 3: corrected executable invocation; passed. Exact two-field result,
  one model, clean `run-WLU1W4VS/artifact-1`.

### 2. `pure` and `>>>`

- Trial 4: passed with `nim c -r ... stage-2`. Graph/logs showed `fk_so`,
  `fk_raw`, one model, sequential completion. Exact result. Clean
  `run-67TalwqD/artifact-1..2`.

### 3. `fan`

- Trial 5: fan plus post-join model. Branches completed and `join.close`
  occurred, but runtime failed before final result. See R-001.
- Trial 6: fan-only isolation passed. Two model completions, ordered join slots,
  exact tuple, clean `run-K8XQz7ey/artifact-1..3`.

### 4. `so`

- Trial 7: model route passed with one model and exact output; pure route passed
  with zero model calls and exact output. Graphs matched both paths:
  `run-ISksorMj`, `run-PJIXIQ87`.

### 5. `it`

- Trial 8: `[[marker]]` compile probe failed; source showed extra AST bracket.
- Trial 9: `[marker]` execution passed. Graph showed `fk_so`, `fk_raw`,
  `fk_it`, one model; exact projected value; clean `run-sSeTJhWX/artifact-1..3`.

### 6. `Location`

- Trial 10: compile failed because `Location` lacked `==`; no execution.
- Trial 11: passed. Model received copied `source.txt`, created only declared
  `result.txt`, returned exact summary/path. `run-1DUVIY1b/artifact-1` contains
  exactly `source.txt` and `result.txt`.

### 7. `lift(seq[here])`

- Trial 12: passed. `jk_lift` slot count 2; model completions arrived out of
  order but indexed join reconstructed exact input order. Clean
  `run-7cYjGhpN/artifact-1..5`.

### 8. Option/tuple/object lift

- Trial 13: passed. Present Option made one inner call; absent Option made zero;
  tuple context and object untouched field survived. All run directories clean:
  `run-tLQrxTIi`, `run-xQLfef8W`, `run-psmqfPLm`, `run-eRmZXov8`.

### 9. Variants, arrays, named tuples

- Trial 14: variant compile needed explicit `std/json`; no execution.
- Trial 15: fixed-array model output failed compilation in generated Schematic
  code; no execution. See R-002.
- Trial 16: isolated supported cases passed. Top-level active variant and named
  tuple exact; clean `run-7ICtxkrS/artifact-1`, `run-ny5S2niN/artifact-1`.

### 10. Advanced composition

- Trial 17: passed. One direct `fan` join with two branches:
  - branch A: `so`, `pure`, `>>>`, `lift(seq[here])`, sequence, `Location`;
  - branch B: `so`, `>>>`, `it`, tuple join, supported variant output.
- Three model calls completed; nested `jk_lift` and outer `jk_fanout` closed;
  exact markers, source paths, variant branch, and tuple result verified.
- Run: `run-swQ9BUTK`. `artifact-6/source.txt` and `artifact-7/source.txt`
  contain only required copied payload; all other artifact directories empty.

## Issues

### H-001 — Missing `std/macros`

Test harness compile issue. Fixed by importing `std/macros`.

### H-002 — Nim argument delimiter

Trial invocation passed literal `--` as program argument. Corrected by invoking
compiled executable directly under `gtimeout`; later `nim c -r file stage-x`
worked as expected.

### S-001 — Guide `it` spelling discrepancy

Guide says `it(T)[[field]]`; current macro implementation requires source
`it(T)[field]`, because outer `[]` constructs selector group. Double brackets
fail parser expansion. Test uses source-confirmed `[field]` spelling.

### H-003 — Location assertion equality

`Location` has borrowed `$` but no `==`. Test compares `$location` with expected
relative path.

### H-004 — Schematic JSON import visibility

Generated variant extraction needs explicit `std/json` import in test module.
Fixed import; variant execution passed.

### R-001 — Fan followed by model loses owning request — resolved

Earlier runtime error: `codex event failed: completed turn has no owning request:`
followed by request ID `4aab4f5c-bc89-46f3-b818-08564eacf0b4`.

Fresh Stage 3 execution now completes fan, join, post-join model, and exact
typed output. Keep historical failure as regression evidence.

### R-002 — Fixed-array model-output contract — resolved

Earlier generated Schematic compile failure:
`type mismatch: Expression: min(schemaOf(T), 3)`. Fixed-array output now uses a
strict `{args: [...]}` transport envelope, matching the dynamic-tool boundary;
the generated materializer unwraps `args` before fixed-array conversion.
Inclusion tests and live Stage 9 pass exact values `[11,22,33]`.

### H-005 — `checked_prompt` literal requirement

Concatenated strings passed to `checked_prompt` fail with
`checked_prompt requires a string literal`. Manual template uses one literal;
no runtime impact.

### P-001 — Location output ambiguity

Default prompt produced repeated advanced-test mistakes: absolute path, input
path, and file contents submitted as output Location. Added short manual
template guidance: create required file inside working directory and return
relative filename; never return absolute path, input path, or file contents.
Stage 10 rerun had zero Location rejects.

## Current stop state

R-001 and R-002 resolved. Core primitives and advanced supported composition
pass with manual templates.

## Rerun: 2026-09-14

- Recompiled with finite `gtimeout`.
- Fresh executions passed stages 0–8, both fan variants, stage 9 variant and
  named tuple cases, and stage 10.
- Stage 10 manual-template run passed exact output and artifact review: only
  `artifact-6/source.txt` and `artifact-7/source.txt` contain files in
  `run-m0GqLffL`; all other artifact directories are empty.
- Stage 9 fixed-array execution passed after the `args` envelope fix.
