# vecherinka_runtime implementation plan

## Goal

Compile typed `vecherinka` output into one in-memory runtime tree:

```nim
let vecherinka_data = VecherinkaData(@[Flow(...), ...])
```

No byte serialization. `Artifact` stores typed Nim values/expressions. Compile-time typing remains source of truth.

## Observed typed-AST contract

Current `vecherinka` expansion was dry-run with `expandMacros`:

- Flow reference lets are `FlowSpec[A, B](ir: FlowIR(kind: firk_ref, id: ...))`.
- Generated flow proc bodies retain `()(cheap[A, B], prompt)`, `first >>> second`, and `fanout((...))` shapes.
- `fan` expands to `fanout`; recognizer cannot require source spelling `fan`.
- `so`, `it`, and `lift` appear as `FlowSpec` constructors containing `FlowIR` constructors.
- `so` body is nested under `cast[pointer](proc ...)`.
- `lift` stores `(...).ir` in `FlowIR.inner`; recursively inspect its typed `FlowSpec` constructor before lowering.
- Model call, `>>>`, `fanout`, and `pure` are recognized from their typed call shapes and specialized directly into runtime nodes.
- Ref `entry` field defaults false in generated ref lets. Authoritative entry flag lives on `.flow_ir(id, entry)` proc pragma.
- `repr` is diagnosis only. Match bound symbols, node kinds, static types, and constructor fields.

Consequent: recognizer must descend through constructors, field accesses, casts, nested proc bodies, tuple arguments, and `FlowIR.inner`; use typed symbol identity plus shape.

## Decisions

- Generated `so` functions use uniform `Artifact` ABI.
- Generated ABI name must differ from user/source flow names, for example `vecherinka_so_fn_<id>`.
- `>>>` is not a runtime node. It is encoded through node input fields and nested flow structure.
- Emit exactly one `fk_flow` per declared flow.
- Store complete model-call payload: profile (including model name and reasoning effort), prompt, endpoint types, and future syntax payload.
- Raw artifacts may reference locals. Copy typed Nim expressions into their original generated lexical scope.
- Unsupported `FlowSpec` is compile-time error.
- No generic empty runtime kind exists; every recognized special syntax maps directly to its specialized runtime kind.

Current `so` contract requires body result `FlowSpec[void, B]`. Plain `B` bodies such as `so(int, string, value): $value` are invalid; output must use explicit `pure(...)`.

## Required runtime shape

Conceptual only; exact field names may differ:

```nim
type
  ArtifactKind = enum
    vtk_none
    # one generated variant per registered non-void type

  Artifact = object
    case kind: ArtifactKind
    of vtk_none: discard
    # generated typed field for each variant

  FlowKind = enum
    fk_flow, fk_ref, fk_model, fk_so, fk_fanout, fk_pure,
    fk_it, fk_lift, fk_raw

  Flow = ref object
    kind: FlowKind
    domain, codomain: ArtifactKind
    input: Flow
    # kind-specific payload fields

  FlowFn = proc(input: Artifact): Flow {.nimcall.}
  VecherinkaData = seq[Flow]
```

`FlowFn` input is always `Artifact`. Wrapper unpacks input according to declared domain, executes copied typed body, then returns lowered `Flow`. External flow references disappear during lowering, so generated `so` functions do not capture them. `FlowSpec[void, B]` body results become lowered flow nodes; never cast `FlowSpec` to `Flow`.

Every node has `input`. `>>>` assigns its left lowered node to the right node's `input`; no compose node exists. A missing `input` means no explicit upstream child. Node kind defines whether that means ambient input or no input.

## Scope and passes

Runtime transform is local to each `vecherinka_runtime` invocation. Do not globalize local `FlowSpec` declarations or raw expressions outside their lexical proc.

Recognition is type-based. Any expression with type `FlowSpec[A, B]` is a special flow value; its initializer is lowered, and its endpoints register `A` and `B`. Preserve ordinary Nim bindings and identifiers. A local alias becomes a local runtime `Flow` after its initializer is lowered; later uses need no manual alias lookup. Nim's own lexical scope handles shadowing. Expression-only flow bodies reject mutable FlowSpec dataflow.

Use global indexes only within current invocation:

1. Index declarations and `.flow_ir(id, entry)` procs.
2. Discover all endpoint/raw types.
3. Assign deterministic artifact names.
4. Lower each declaration and nested flow expression.
5. Validate and emit.

Index and type discovery precede emission. Lowering may recurse per proc after shared indexes exist.

## Declaration discovery

For every proc with a `flow_ir(id, entry)` pragma call, record:

- id, entry;
- source proc node/body;
- typed domain/codomain.

For every declaration `let name = FlowSpec(... firk_ref, id)`, record name/id/domain/codomain. Join by id. Each joined pair emits one `fk_flow` with original name and entry flag.

Reject duplicate ids, missing pairs, endpoint mismatch, unknown references.

Do not assume declaration order. Forward refs and duplicate ref uses are normal.

## Syntax recognition

Recognition must use typed AST call shape and bound symbols, not spelling alone. Each special syntax lowers directly to its specialized runtime node. `FlowIR` fields supply payload for forms such as references, projections, lifts, and `so`; typed call AST supplies model-call, fanout, pure, and `>>>` operands.

Recognized categories:

- `FlowSpec` reference declaration;
- model-call constructor;
- `so` constructor;
- `fanout`/`fan` constructor;
- `pure` constructor;
- `it`/projection constructor;
- `lift` constructor;
- compose `>>>` shape;
- ordinary typed expression consumed as raw artifact.

Every recognized special element registers its input/output endpoint types before lowering.

Tuple-valued fanout operands remain ordinary typed Nim values. Lower tuple literal elements recursively. If a tuple variable is used, lower its initializer to a runtime tuple or preserve the runtime tuple binding; do not resolve it by global name. Preserve nested fanout structure; never flatten it accidentally.

## Lowering rules

### Declared flow

```text
fk_flow(name, domain, codomain, entry, root)
```

`root` is lowered from matching generated proc body/result. No separate top-level runtime node for generated proc.

### Reference

```text
fk_ref(name = referenced declaration name,
       domain = referenced domain,
       codomain = referenced codomain)
```

Use name for runtime readability; retain id internally only if diagnostics/validation need it.

### Model call

```text
fk_model(domain, codomain,
         profile, model, reasoning, prompt, other payload)
```

Model profile values must be copied or represented in runtime-compatible form. No payload may silently disappear.

### `so`

```text
fk_so(domain, codomain, fn = proc(input: Artifact): Flow {.nimcall.} = ...)
```

Current `so` contract is flow-valued: body must produce `FlowSpec[void, codomain]`. Plain value bodies are unsupported; current direct `so(int, string, value): $value` fails before runtime lowering. Generated function gets collision-safe internal name. It unpacks `input` through a fresh Artifact parameter, reconstructs typed local matching original `so` parameter, runs copied ordinary statements and recursively lowered special expressions, then returns lowered output flow. User local names remain lexical. Merely changing original parameter type to `Artifact` breaks copied references.

Require `so` input pattern to be one identifier for initial implementation, or preserve full binding pattern in the generated wrapper. Generate fresh internal symbols. Flow references in copied body become runtime data nodes, not captured Nim variables.

### Fanout and implicit `>>>`

Canonical form:

```text
left >>> fan(right1, right2)
```

becomes one `fk_fanout` whose explicit `input` is lowered `left`, and whose `operations` are `[right1, right2]`.

For `fan(...)` without left operand, leave `input` absent; fanout consumes ambient input. `pure` has no upstream input. Raw values provide explicit input when used by a downstream node.

For ordinary composition `left >>> right`, no compose node. Lower left first, attach exactly once as `right.input`. Nim's left-associated shape gives `a >>> b >>> c` as `c(input = b(input = a))`. Reject attaching into already-explicit right input unless normalization rule explicitly unwraps it. Never detach or duplicate left operand.

`raw >>> fan(...)` uses `fk_raw` as fanout input. `flow_ref >>> model` uses `fk_ref` as model input. Do not lose either operand.

Every node has the same `input` field. `fk_fanout` additionally stores ordered `operations`; `fk_model` stores payload; `fk_raw` and `fk_pure` store Artifact. Missing `input` has meaning defined by node kind, not by a separate compose node.

Current fixture dry-run:

```text
first_second                 fk_model
first_third                  fk_model
second_third                 fk_model
first_third_1                fk_model(input = fk_ref(first_second))
first_third_2                fk_ref(second_third, input = fk_ref(first_second))
first_second_third_fanout_2 fk_fanout(input = ambient,
                                      operations = [fk_ref(first_second), fk_ref(first_third)])
so_test                      fk_so(wrapper)
lens_multiple                fk_it(path = [[index 1], [field "first"]])
lift_identity                fk_lift(inner = fk_it(identity))
entry_flow                   fk_model, entry = true
```

Exactly ten `fk_flow` roots. Nested refs remain `fk_ref`; never duplicate declared roots. `so_test` wrapper lowers local `e` to `fk_fanout(input = fk_raw(First()), operations = [...])`, preserves `echo`/`discard`, returns `fk_pure(Second())`. `entry = true` comes from pragma id 9, not ref constructor default.

### Pure

```text
fk_pure(value = Artifact(kind, original typed expression))
```

`pure(v)` has domain `void`, codomain `typeof(v)`. Preserve typed expression AST in its generated local scope.

### Projection

```text
fk_it(domain, codomain, path = ItPath)
```

Store normalized path data, not merely spelling. Endpoint codomain may be tuple/string/object/variant-derived type and must enter Artifact registry.

Runtime projection execution is separate. Store serialized `ItPath` plus a later runtime projector of the form `it_runtime(input, path)`. No interpreter implementation belongs in this pass.

If projection syntax is applied to a local projection alias, the existing projection macro must preserve or recover its path before this pass. This is frontend syntax handling, not runtime alias resolution.

### Lift

```text
fk_lift(domain, codomain, pattern, inner = recursively lowered flow)
```

Store runtime-compatible serialized pattern data plus original spelling when useful. Descriptor must retain here/keep/wildcard, tuple/object structure, variant tag/branch, field names, literal/type atoms, and nesting. `inner` may be ref, model, `so`, projection, another lift, or composed flow.

`LiftPatternTree` contains compile-time `NimNode` values; never emit it unchanged as runtime payload. Generate serialized runtime pattern data. Runtime lift execution is later work; this pass must only preserve enough information for a runtime worker to construct work nodes from input plus serialized lift definition.

### Raw artifact

```text
fk_raw(value = Artifact(kind = registered typeof(expr), typed value = expr))
```

Only ordinary expressions consumed as flow values become raw nodes. Preserve expression AST in its generated local scope. Register `typeof(expr)`. `void` raw values reject.

Generated wrapper evaluates copied expression exactly once when constructing `fk_raw`/`fk_pure`. If deferred evaluation is required, store typed thunk instead. Arbitrary Nim expression is not byte-serializable data.

### Local FlowSpec bindings

Local `FlowSpec` lets inside `so` are not declared top-level flows and must not emit `fk_flow`. Lower their typed initializers to local runtime `Flow` values. Later identifiers remain ordinary Nim identifiers bound to those values; no manual lexical symbol environment is required. Global declared refs lower to fresh `fk_ref` nodes per occurrence.

Because declared flow bodies are expressions, reject mutable FlowSpec dataflow and runtime-dependent top-level selection. Tuple aliases are valid when their typed initializers lower to runtime flow tuples.

Local type declarations inside wrapper cannot become variants in invocation-global `Artifact` if generated type sits outside lexical scope. Default plan: reject local endpoint/raw types with compile-time diagnostic. Supporting them needs scope-local erased representation.

### Flow-body shape

Declared flow proc bodies must be expressions producing one statically lowerable `FlowSpec`. Reject dynamic top-level `if`, `case`, loops, mutable FlowSpec variables, and helper-proc escapes.

`so` retains its existing typed body/block semantics. Lower special expressions inside it; preserve ordinary Nim statements and local bindings.

Preserve source evaluation order. Do not hoist raw/pure expressions or local expressions while constructing static data. Duplicate references create distinct runtime node instances, even when declaration target same.

## Type registry and generated Artifact

Register every `FlowSpec[A,B]` endpoint plus every non-void raw value type. Deduplicate by compiler type identity, not `repr`.

Generate:

- stable `ArtifactKind` variant;
- typed `Artifact` field;
- pack helper;
- unpack helper;
- compile-time mapping from type identity to kind.

Artifact field names must be distinct from `ArtifactKind` variants, source identifiers, and generated wrapper names. Wrapper parameter names must likewise be fresh.

Names must avoid collisions with user names and generated helper names. Readable stems plus deterministic suffixes handle aliases, anonymous tuples, generic instances, same-spelled types from different scopes. `void` maps to `vtk_none` and has no field.

## Validation

Compile-time reject:

- unsupported `FlowSpec` constructor;
- missing declaration/proc pair;
- unknown reference;
- endpoint mismatch;
- raw `void` or unregistrable type;
- Artifact name collision after disambiguation;
- wrapper unpack/pack type mismatch;
- ambiguous composition/input shape.
- composition whose right node already has an input, unless an explicit associativity rule is added.
- unsupported plain-value `so` body;
- local type used as invocation-global Artifact variant;
- named intermediate projection whose path marker was not preserved;
- zero-`here` lift without specified constant semantics.
- `so` body form not accepted by chosen plain-value/`FlowSpec` normalization contract.
- raw/pure value whose static type is itself `FlowSpec`, unless explicit nested-flow Artifact semantics are added.
- direct `fanout` whose operation tuple is not recoverable syntax.

## Emission order

1. Artifact kind/object declarations.
2. Runtime `Flow`, `FlowFn`, payload types, helpers.
3. Collision-safe generated wrappers.
4. One `fk_flow` per declared flow.
5. `let vecherinka_data = VecherinkaData(@[...])`.
6. Preserve original declarations only if surrounding user code still references them; otherwise replace temporary `FlowSpec` layer.

## Battle-test matrix

Dry-run each case from typed `vecherinka` expansion through runtime tree:

- model call with every payload field;
- `a >>> b`, `a >>> b >>> c`, `a >>> fan(b,c)`;
- raw value `>>> fan(...)`;
- nested fanout and fanout-of-fanout;
- pure of constructor/local/tuple/variant value;
- projections, projection chains, duplicate selectors, ranges;
- lifts, composed lifts, lift of ref/model/so/projection;
- forward refs and duplicate refs;
- entry flows;
- local `FlowSpec` declarations inside `so`;
- local aliases/reuse of `FlowSpec` values inside `so`;
- anonymous/named/generic/alias/variant endpoint types;
- same display names from distinct scopes;
- ordinary statements between special expressions.
- nested runtime scopes with independently restarting flow IDs;
- FlowSpec values in conditionals, loops, tuple containers, mutable locals, helper returns, and nested-proc escapes.

Record source limitations separately: current `so` plain-value bodies fail before runtime; `it` append macro recognizes literal constructor shape, so `let p = it(T); p[0]` needs alias metadata or remains unsupported; `fan` currently compares AST/type spelling and may reject aliases or same-spelled scoped types before runtime.

Also test wrapper parameter hygiene: original `so` input identifier, nested locals, and raw expressions must bind after Artifact unpacking.

For each case record: source, typed shape, registered types, exact node fields, lexical scope, and rejection if no unique encoding exists.

## Acceptance invariant

Every statically typed special syntax occurrence has exactly one lowering. Every lowered node preserves domain, codomain, payload, operand order, lexical scope, and runtime input semantics. No `FlowSpec` survives emission except inside intentionally copied ordinary code, and no runtime node depends on unavailable source spelling.

Every model payload field must have defined source. Current syntax visibly supplies profile expression, endpoint types, and prompt; model/reasoning metadata requires corresponding fields in syntax or `ProfileSpec`, not invented values.

`it` and `lift` nodes preserve runtime-compatible serialized definitions. Their projector/work-node execution is a later runtime concern, not part of this lowering pass.

`ProfileSpec` carries model name and reasoning effort. Model-call lowering stores that profile plus prompt, endpoints, and future payload fields. `FlowIR` alone is not the model payload source.

Generated `FlowFn` uses Artifact ABI with specialized flow references inlined as runtime data. No external flow-reference capture remains.

Flow IDs, generated symbols, Artifact registries, and helper names are invocation-scoped. Nested `vecherinka_runtime` scopes are opaque boundaries; cross-scope FlowSpec use rejects unless explicit shared registry support is designed.
