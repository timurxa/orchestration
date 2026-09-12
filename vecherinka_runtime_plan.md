# `vecherinka_runtime` plan

## State

Current work: lower typed Vecherinka syntax into simply typed runtime data.

Done:

- `Flow[A]` is a module-level ref object over generated Artifact carrier `A`.
- `Flow` variants currently: `fk_top`, `fk_model`, `fk_raw`, `fk_ref`, `fk_it`,
  `fk_fanout`, `fk_so`, `fk_lift`.
- `Flow.continuation` stores producer-side continuation. `>>>` has no runtime
  composition node.
- Compile-time `LoweredFlow(head, tail)` supports O(1) continuation append.
- Model calls lower to `fk_model`.
- `pure(value)` lowers to existing `fk_raw(value)` with no extra runtime
  variant.
- Flow references lower to named `fk_ref` nodes.
- `it` lowers to a non-capturing `.nimcall.` Artifact projector.
- `fk_fanout` lowers typed `fanout((...))` calls into ordered branch flows plus
  a generated tuple coalescer.
- `so_syntax` preserves typed `so` callback bodies until Artifact generation;
  `fk_so.execute` now lowers them into Artifact-to-Flow callbacks.
- `FlowIR.firk_so` no longer stores erased function pointers.
- Artifact type generation precedes lowering and uses hygienic generated names.
- Structural fanout coverage passes for model/ref branches, outer and inner
  continuations, branch-local composition, and nesting.
- Structural `so` coverage passes for callback generation, input rebinding,
  body composition, value-seeded composition, fanout, and outer continuation.
- Lift lowering is implemented as one local `fk_lift` node. Its work and
  reconstruction callbacks are anonymous `.nimcall.` procs over generated
  `Artifact`, and work slots are plain indexed tuples.
- Lift structural coverage passes for sequences, tuples, nested sequences,
  chained lifts, and a lift wrapping `so`.
- No major unresolved lift compromise remains. The dry-run hurdles were
  resolved locally with tuple work slots and generated callback symbols; the
  evaluator is the next independent slice.

Now:

- Implement the runtime evaluator over generated `Flow[Artifact]` trees,
  including `fk_raw`/`pure`, `fk_lift` work scheduling and reconstruction.
- Execute `fk_so` and `fk_lift` callbacks with concrete generated Artifact
  values.

Not done yet:

- Runtime evaluator.
- Runtime `pure` execution awaits evaluator; it will use same `fk_raw` path.
  Value-seeded `>>>` also lowers its left value through `fk_raw`.
- Runtime ref resolution and execution policy.
- JSON or wire serialization. `Flow` is currently in-memory generated data;
  existing `fk_it` already contains executable projector metadata.

No implementation should revive old placeholder kinds or duplicate completed
projector/composition work.

## Goal

Compile each declared Vecherinka flow into one in-memory `Flow[Artifact]` tree.
Source typing remains authoritative. Generated Artifact is a variant over all
registered non-void endpoint types. Runtime Flow nodes use that Artifact as
their carrier; they do not retain `FlowSpec`.

## Current source contract

The frontend currently provides:

```nim
FlowSpec[A, B]
FlowSpec[A, B](ir: FlowIR(...))
fan(x, y, ...)
fanout((x, y, ...))
so(domain, codomain, pattern) do: body
x >>> y
```

`fan` is a typed macro. It validates all inputs share one domain, builds a
typed tuple of branch expressions, then expands to `fanout(tuple)`. After
typing, the lowerer sees:

```text
Call(Sym("fanout"), TupleConstr(branch0, branch1, ...))
type: FlowSpec[Input, (Output0, Output1, ...)]
```

The source `fanout` proc currently returns `FlowSpec(... firk_empty)`, so its
typed call arguments—not `FlowIR`—are the branch source of truth. Do not
recognize only spelling `fan`; recognize the `fanout` proc shape and actual
`FlowSpec` type.

## Runtime shape

Current shape:

```nim
type
  FlowKind = enum
    fk_top, fk_model, fk_raw, fk_ref, fk_it, fk_fanout, fk_so

  Flow[A] = ref object
    continuation: Flow[A]
    case kind: FlowKind
    of fk_top:
      root: string
      body: Flow[A]
    of fk_model:
      profile: ProfileSpec
      prompt: string
    of fk_raw:
      value: A
    of fk_ref:
      name: string
    of fk_it:
      projector: proc(input: A): A {.nimcall.}
    of fk_fanout:
      branches: seq[Flow[A]]
      coalesce: proc(values: seq[A]): A {.nimcall.}
    of fk_so:
      execute: proc(input: A): Flow[A] {.nimcall.}
    of fk_lift:
      inner: Flow[A]
      destructure: proc(input: A):
        seq[tuple[result_index: int, input: A]] {.nimcall.}
      construct: proc(results: seq[A]; input: A): A {.nimcall.}
```

`fk_raw` seeds its continuation with a locally computed Artifact. `fk_fanout`
and `fk_so` are implemented. `fk_lift` is now structurally lowered but still
needs evaluator execution. `continuation` is common to all operation nodes.
`fk_top` wraps declaration metadata and is not an operation in a chain.

The coalescer is necessary: branch outputs share erased carrier `A`, while
fan output has static tuple type `(B, C, ...)`. Generated coalescer unpacks
each branch Artifact using its static codomain, constructs the tuple in source
order, and packs the tuple into one Artifact. This is analogous to the
existing executable `it` projector and avoids lift's variable-cardinality
work graph.

If a future wire-serialization boundary forbids executable fields, replace
both projector/coalescer fields with operation tags and a separate evaluator
registry. That is outside current in-memory scope.

## Composition invariant

Compile-time lowering returns:

```text
LoweredFlow = {head: NimNode, tail: NimNode}
```

Every leaf returns itself as both head and tail. Composition lowers both sides,
adds `right.head` to `left.tail.continuation`, then returns
`{left.head, right.tail}`. Existing branch-local composition uses same rule.

Fan composition:

```text
x >>> fan(a, b) >>> y

x.continuation = fanout(
  branches = [a, b],
  coalesce = typed_pack_tuple,
  continuation = y)
```

Each branch receives same ambient input. Branch output never becomes next
branch input. Branch order comes from `seq` index. Fan's continuation runs once
after coalescing. Nested fan remains nested; never flatten implicitly.

Value-seeded composition:

```text
value >>> flow

fk_raw(value = pack(value))
  .continuation = lower(flow)
```

The typed overload already establishes that `value` matches `flow`'s domain.
Lowerer preserves actual value AST, so local variables work. No active `so`
parameter tracking and no composition node are needed.

`pure(value)` uses the same representation without composition:

```text
pure(value) = fk_raw(value = pack(value))
```

The matcher requires an actual proc-shaped call with typed result
`FlowSpec[void, A]`, then queries the argument's real type. This supports
constructors, literals, and local symbols while keeping source typing as the
authority.

## `lift` lowering

`lift(pattern)[inner]` is a data node, not a composition node. The lowerer
keeps the existing typed lift pattern and maps it to:

```text
fk_lift(
  inner = lower(inner),
  destructure = proc(input: Artifact):
    seq[tuple[result_index: int, input: Artifact]] {.nimcall.},
  construct = proc(results: seq[Artifact]; input: Artifact): Artifact {.nimcall.}
)
```

`destructure` walks the input pattern in preorder. Each `here` appends one
indexed work tuple containing a packed inner-domain Artifact. `construct`
walks the retained original input shape in the same order, unpacks each
corresponding inner-codomain result, and rebuilds the outer codomain. Sequence
and Option cardinality therefore comes from the original input, not from the
result count. Tuple and object reconstruction reuse the existing lift emitters.

The callbacks are emitted inline at each lift occurrence. This keeps `Flow`
independent of generated helper/work types: no global `FakeWork`, lift registry,
or named helper declaration is needed. The lowerer's existing continuation
pairing gives `lift(...)[inner] >>> next` the shape:

```text
fk_lift(inner = lower(inner), continuation = lower(next))
```

The continuation belongs to the outer lift. It is not attached to `inner`.

Dry-run findings and resolutions:

- A generated `FakeWork` type cannot be named safely by module-level generic
  `Flow[A]`; indexed `(int, Artifact)` tuples remove that scope dependency.
- `sameType` can reject synthesized `lift_types` nodes despite identical
  spelling. The typed `make_lift` result is authoritative; the lowerer avoids
  redundant endpoint comparison and uses the inner expression's typed
  `FlowSpec`.
- Quote hygiene can make a compile-time variable named `input` collide with a
  tuple field. Generated callback locals use distinct symbols.
- Object patterns still require the existing source-level field typing to be
  compatible; this is a pre-existing typed-pattern limitation, not a runtime
  compromise.

## Fanout lowering

### Recognition

The lowerer uses a small Fusion matcher beside model-call matching:

1. Require node's actual type to be `FlowSpec[Input, Output]`.
2. Match `Call([callee, branches])`.
3. Verify `callee` is a proc symbol named `fanout`; the actual typed
   `FlowSpec` result and branch types remain authoritative.
4. Require `branches.kind == nnkTupleConstr` and `branches.len > 0`.
5. For each branch, query actual type. Require `FlowSpec[Input, BranchOutput]`.
6. Validate branch domain with `sameType` against fan input.
7. Validate fan output is tuple of branch codomains. Existing typed `fan`
   expansion establishes this; explicit validation protects direct `fanout`.

Do not add a new `FlowIRKind` for fanout. Existing `firk_empty` remains source
placeholder until a later frontend IR cleanup.

### Branch lowering

Inside `lower_flow_expr`, fanout is handled before model/it leaf fallback:

1. Lower each tuple child recursively with `lower_flow_expr`.
2. Store each lowered `.head` in generated ordered `seq[Flow[Artifact]]`.
3. Keep each branch's own continuation chain intact.
4. Generate typed coalescer from branch codomains and fan codomain.
5. Emit one `Flow[Artifact](kind: fk_fanout, branches: ..., coalesce: ...)`.
6. Return that node as both `head` and `tail`.

No branch is connected to another branch through ordinary continuation. Outer
`>>>` mutates only fan node's continuation via existing append helper.

### Coalescer generation

The lowerer generates a fresh `.nimcall.` proc with shape:

```text
proc(values: seq[Artifact]): Artifact {.nimcall.} =
  let branch0 = unpack Artifact as BranchOutput0 from values[0]
  let branch1 = unpack Artifact as BranchOutput1 from values[1]
  ...
  pack (branch0, branch1, ...) as fan Output
```

Reuse existing Artifact registry pack/unpack helpers. No new Artifact variants
for individual branches. Use static indexes, fresh symbols, no source-local
captures. Branch arity is fixed at compile time.

Generated coalescer is not lift machinery: no `FakeWork`, `here` cursor,
destructure loop, or reconstruction traversal.

## `so` lowering

### Research result

Three strategies were dry-run in disposable probes:

- Recover lambda from current `FlowIR.firk_so.fn` pointer cast: lambda AST is
  briefly visible, but pointer representation cannot be a reliable recognizer
  or source recovery mechanism.
- Preserve a typed macro-only source marker: compiles, retains body lambda
  through typed traversal, and needs no runtime registry. Chosen.
- Emit named helper procs: compiles after Artifact generation, but adds helper
  ordering/forward-declaration machinery and loses lexical captures under
  `.nimcall.`.

### Source marker

`so(domain, codomain, pattern) do: body` expands to a typed `so_syntax` call:

```text
so_syntax(proc(pattern: Domain): FlowSpec[void, Codomain] = body)
```

`so_syntax` returns ordinary `FlowSpec` source metadata. Lowerer recognizes the
typed call and consumes its lambda before emitting runtime data. It never stores
`NimNode` or source pointers in generated `Flow`.

### Runtime lowering

The lowerer emits `fk_so.execute: proc(Artifact): Flow[Artifact] {.nimcall.}`.
Lowering:

1. Match `so_syntax` with Fusion; unwrap compiler conversion around lambda.
2. Validate actual `FlowSpec[Domain, Codomain]`, one typed input parameter, and
   `FlowSpec[void, Codomain]` lambda result. Reject void callback domains in
   this slice because Artifact carries non-void values.
3. Lower original typed body while symbols retain type metadata. Then replace
   references bound to lambda parameter with a fresh generated local symbol.
   Symbol identity matters; replacing spelling alone breaks hygiene.
4. Recursively apply existing whole-body walker to lambda body. Nested model,
   ref, composition, fanout, it, and so nodes lower normally.
5. Emit one inline non-capturing `.nimcall.` callback returning `Flow[Artifact]`.
6. Emit `fk_so` as ordinary chain node. Existing `>>>` appends outer
   continuation to `fk_so`, never to callback-generated body.

First slice rejects lexical captures that cannot satisfy `.nimcall.`. Future
closure/environment support can relax this only if real source needs it.

Callback body returns Flow data, not Artifact data. Callback input is the
ambient input for its returned Flow when evaluator arrives. Value-seeded
composition inside callback bodies emits `fk_raw` with a packed local value,
then attaches lowered flow through `continuation`. Standalone `pure` remains
unsupported.

## Runtime semantics

Future evaluator contract:

```text
run(node, ambient):
  if node.kind == fk_fanout:
    values = [run(branch, ambient) for branch in node.branches]
    output = node.coalesce(values)
  elif node.kind == fk_lift:
    works = node.destructure(ambient)
    results = newSeq[Artifact](works.len)
    for work in works:
      results[work.result_index] = run(node.inner, work.input)
    output = node.construct(results, ambient)
  else:
    output = step(node, ambient)
  if node.continuation != nil:
    return run(node.continuation, output)
  return output
```

Fan branches execute in stored order for initial deterministic semantics.
Parallel scheduling may come later, but must preserve ordered coalescing and
shared input. Branch continuations terminate at each branch's own tail.

## Validation

Reject:

- empty fan tuple;
- fanout call whose callee is not the `fanout` proc;
- non-`FlowSpec` branch;
- branch domain mismatch;
- fan output tuple arity/type mismatch;
- malformed branch tuple not recoverable from typed AST;
- continuation append to an already-linked tail;
- shared mutable AST node reused across source occurrences.

Existing validation remains unchanged for model calls, refs, projections, and
composition. Lift callbacks reject malformed IR and void inner endpoints.

## Current structural coverage

- `fan(model_a, model_b)` emits `fk_fanout` with two ordered model branches;
- `fan(ref_a, ref_b)` preserves symbolic names and fresh branch nodes;
- `fan(a, b) >>> c` attaches `c` to fan node, not either branch;
- `a >>> fan(b, c)` attaches fan to `a` tail;
- branch `(a >>> b)` preserves its internal continuation;
- nested `fan(fan(a, b), c)` preserves nested tuple shape and order;
- generated coalescer is non-nil and uses expected branch indexes;
- lowerer rejects direct invalid domain and empty-fan cases at compile time;
- existing model/ref/it/composition tests remain green;
- no runtime composition node appears in generated Flow data;
- `so` emits `fk_so` with non-nil `execute` callback;
- `so` body parameter rebinding compiles through ordinary statements;
- `value >>> flow` emits `fk_raw(value)` with flow as its continuation;
- value-seeded composition preserves local value expressions;
- `so` body composition preserves local continuation;
- `so` body fanout preserves nested `fk_fanout`;
- outer composition appends continuation to `fk_so`.
- `pure(value)` emits `fk_raw` directly;
- local-value `pure` preserves its source symbol;
- `pure(value) >>> next` attaches `next` to `fk_raw`.
- `lift(seq[here])[flow]` emits `fk_lift` with non-nil inner,
  destructure, and construct callbacks;
- tuple and nested-sequence lift patterns preserve slot order in both
  callbacks;
- Option lift patterns preserve presence/absence while consuming slots only
  for present values;
- chained lifts keep the second lift on the first lift's outer continuation;
- lift can wrap a `so` flow without moving the continuation into the inner
  flow.

## Known issues

- No evaluator currently exists; tests inspect generated structure/coalescer
  until execution support lands.
- `Flow` executable fields are in-memory metadata, not wire serialization.
- `fanout`'s generic `B` is currently permissive; lowerer validation prevents
  direct malformed calls from lying about output type.
- Calling `fk_so.execute` through a generic helper instantiated with generated
  Artifact currently triggers Nim 2.3.1 internal error `genFieldObjConstr`.
  Structural callback generation compiles; evaluator entrypoint must use a
  concrete generated Artifact path and be tested separately.
- Rebinding `so` input before typed traversal erased type metadata from copied
  AST. Implementation lowers original typed body first, then substitutes
  parameter symbol references.
- Lift object patterns still depend on source-level field type compatibility;
  no runtime workaround was added because the typed pattern itself rejects
  incompatible field changes.
- Existing `-d:vecherinka_ir_tests` fixture contains commented declarations
  with live assertions; unrelated stale harness failure must not drive fan
  design.

## Next slices

1. Implement evaluator for raw/model/ref/it/fanout/lift/so with shared ambient
   input.
3. Revisit executable fields only when actual serialization requirements
   arrive.
