# Nim macro/generic callback investigation

Date: 2026-09-12
Compiler: Nim 2.3.1 arm64; also checked 2.2.6, 2.2.10, `#devel`

Scope: confirm `vecherinka_ir` `so` callback problem; test workarounds. No
production source edits. Disposable probe: `so_call_probe.nim`; compile output
and Nim caches under `/tmp`.

## Baseline

Current generated structure checks pass. `so_model.body.execute != nil` passes.
No callback invocation in existing structural test.

Probe:

```nim
proc call_so[A](flow: Flow[A]): Flow[A] =
  flow.execute(default(A))

discard call_so(so_model.body)
```

Command:

```text
CODEX_HOME=.codex-task-state CODEX_SQLITE_HOME=.codex-task-state \
nim c --path:src --panics:on --threads:on \
  --nimcache:/tmp/vecherinka-so-generic-cache \
  -o:/tmp/vecherinka-so-generic so_call_probe.nim
```

Result: compiler crash:

```text
so_call_probe.nim(9, 24) Error: internal error: genFieldObjConstr
```

Same failure across Nim 2.2.6, 2.2.10, 2.3.1, `#devel`. This is compiler
bug, not user type mismatch.

## Root-cause narrowing

| Shape | Result |
|---|---|
| Source-defined `Flow[First]`, generic callback call | Pass |
| Macro-generated artifact `A`, generic `flow.execute(default(A))` | Crash |
| Same generated `Flow[A]`, generic `flow.execute(input)` with explicit `A` input | Pass |
| Existing `run_projector[A]` using `default(A)` | Pass for projector path |
| Generated plain/non-variant callback container with generic call | Pass |
| Generated tagged artifact plus simple variant callback container | Pass |
| Full `vecherinka_ir` generated artifact plus `so` callback plus `default(A)` | Crash |

Strong conclusion: `default(A)` alone fails for this generated Artifact inside
generic `default_for[A](flow: Flow[A]): A`; callback call is not root trigger.
Do not describe as “any generic function-pointer call fails.” Actual callback
call with supplied artifact input works.

Tested against actual generated output:

```nim
proc call_so_input[A](flow: Flow[A]; input: A): Flow[A] =
  flow.execute(input)

let called = call_so_input(so_model.body, raw_input.body.value)
```

Compile and `-r` run pass; callback returns expected `fk_ref`.

## Approaches

### 1. Pass ambient `A` input — preferred

Status: compile pass against actual `vecherinka_ir` output.

Evaluator already has ambient input while evaluating a flow. API should accept
that value. `so` domains are non-void, so no legitimate evaluator call needs
`default(A)`.

Pros: zero representation change; keeps typed `proc(input: A): Flow[A]`;
preserves macro-generated Artifact; simplest.

Hurdle: entry/evaluator tests must construct a valid Artifact through generated
code, not `default(A)`.

### 2. Generate concrete evaluator adapter

Status: pass in disposable macro-generated probe.

Generate, beside Artifact type, a concrete proc like:

```nim
proc invoke_so(flow: Flow[Artifact]; input: Artifact): Flow[Artifact] =
  flow.execute(input)
```

Concrete generated proc can also use `default(Artifact)` in probe. Generic
evaluator can delegate to generated adapter if a no-input test helper is needed.

Pros: typed callback; keeps `Flow[A]`; only evaluator bridge is generated.
Cons: generated per-artifact adapter; more macro plumbing. Better than making
all runtime types macro-only.

### 2b. Replace `default(A)` with `zeroDefault(A)`

Status: compile pass for original failing generic probe; runtime fails generated
Artifact validation (`artifact.kind == vak_2`). `zeroDefault` avoids compiler
object-construction path but does not create valid tagged input. Diagnostic-only
escape hatch, not evaluator design.

### 3. Store callback as `pointer`, cast at invocation

Status: pass in generated tagged-artifact + variant-container probe and actual
`vecherinka_ir` callback view (`-r`).

Shape:

```nim
execute: pointer

let callback = cast[proc(input: A): ErasedFlow[A] {.nimcall.}](flow.execute)
callback(input)
```

Pros: avoids compiler path; small runtime representation.
Cons: loses type checking; cast ABI must stay `.nimcall.`; closure environment
and lifetime unsafe; nil/wrong callback can become memory corruption. Generated
callbacks are currently noncapturing `.nimcall.` procs, but this remains sharp.

Recommendation: fallback only if concrete-input/generated-adapter route fails.

### 4. Move callback out of variant object / flatten Flow

Status: simple generated probes pass. A non-variant `PlainFlow[A]` with typed
callback survives generic invocation for macro-generated A.

Possible design: keep variant data in non-generic node; keep executable action in
separate typed sidecar. This may avoid problematic nested object codegen.

Cons: representation split; more allocations/indirection or less case-field
checking; not needed if approach 1 works.

### 5. Template, getter, callback-only generic helper

Status: no useful fix. Generic callback-only helper still crashes with
`default(A)`; template/direct external extraction cannot reliably name nested
gensym Artifact type. Explicit-input generic proc already solves call.

### 6. Upgrade compiler

Status: no fix in locally available 2.2.6, 2.2.10, 2.3.1, `#devel`.

## Final plan

1. Actual `-r` explicit-input callback probe passes.
2. Treat `default(A)` as invalid evaluator probe for generated Artifact.
3. Design evaluator with ambient `A` input; add generated valid-input fixture.
4. If a no-input adapter is needed, generate one concrete proc per Artifact
   type. Keep pointer erasure as documented fallback, not first choice.
5. Delete disposable probe. Leave this file as progress record.
