# Vecherinka runtime implementation plan

## Status

This plan replaces `vecherinka_runtime_plan.md`. It is the implementation
record and remaining-work plan for the runtime.

## State

Current work: merged Slice 4/5 plus structural POSIX IPC plumbing complete;
real LLM decoding and Codex agent messaging remain.

Slices 1 through 3 are implemented in
[`src/vecherinka_runtime.nim`](/Users/alex/areas/productive/orchestration/src/vecherinka_runtime.nim)
and exercised by
[`src/vecherinka_runtime_execution_test.nim`](/Users/alex/areas/productive/orchestration/src/vecherinka_runtime_execution_test.nim).

The former Slices 4 and 5 are merged into one slice. The former Slice 6 is
deleted.

Verified with Nim 2.3.1, `--threads:on`, and `--panics:on`:

- focused lazy-execution test: compile and run passed;
- generated model execution with injected transport: compile and run passed;
- existing `vecherinka_runtime_model_test.nim`: compile passed;
- existing `vecherinka_interface_test.nim`: compile and run passed;
- existing `vecherinka_tests.nim`: compile passed.

Implemented state includes `Resume`, iterative activations, root/ref handling,
immediate raw/it handling, model suspension, lazy `so`, unified fanout/lift
joins, indexed result slots, work-node input/output ledger, a main-owned
ready/event queue, deferred fake submission, `ModelCallSpec`, generated model
preparation callbacks, and real solve-input packing.

The model submit path is an artifact-level test seam. Generated model
preparation produces `ModelCallSpec`; each spec carries an erased generated
submit adapter. That adapter unpacks the concrete input, builds type-specific
LLM context/tools, and passes an `LlmCallSpec` to fake/injected transport.
The deterministic transport materializes a typed debug Artifact and queues a
deferred event without Codex. Existing generated packers remain on `Flow` for
future real response materialization.

Next work: generated real LLM-output decoding and Codex agent messaging.
POSIX readers and main-thread channel routing are now wired structurally, but
no agent message submission is included.

Progress ledger:

- [x] Slice 1: lazy structural activation, WorkNodes, resumes, joins, and
  deferred submit seam.
- [x] Slices 2/3: actual input packing, generated model preparation, pending
  request Events, and fake end-to-end execution.
- [x] Merged Slice 4/5: generated type-specific submit, output kind,
  Artifact-variant debug materialization, injected/fake completion, and
  end-to-end validation.
- [x] Isolated generated-submit shape probe: concrete input unpacking,
  type-specific LLM context/tools, raw transport seam, deferred materializer;
  passed under Nim 2.3.1, `--threads:on`, and ARC.
- [ ] Generated real LLM-output adapter: deferred. Merged Slice 4/5 only
  implements its deterministic debug stand-in.
- [x] Structural Codex/POSIX input plumbing: context-owned event channel, concurrent
  stdout/stderr readers, framing, stop wakeup, and main-thread event handling.
- [ ] Codex agent messaging: intentionally deferred until its contract is
  defined.

### Merged Slice 4/5 implementation record

Implemented in `src/vecherinka_runtime.nim` and
`src/vecherinka_comptime.nim`:

- `ModelCallSpec[A]` now carries `output_kind`, `debug_output`, and an erased
  `submit` pointer. The pointer is cast only at the generated dispatch
  boundary.
- Generated model preparation validates the actual input Artifact and stores
  the model-specific submit adapter in the returned spec.
- The generated adapter unpacks the concrete input, creates typed context and
  a deterministic output tool registry, then calls generic `submit_llm` with
  `LlmCallSpec[A]`.
- Debug materialization emits a `case` over the registry ordinal and builds
  the matching generated Artifact discriminator/value branch. String output
  uses `debug:<tool-name>`; other output types currently use the typed
  `default_debug_value[T]` fallback until factories/decoders are added.
- `LlmOutput` is structured (`tool_name` plus JSON `arguments`) so the future
  decoder uses the same boundary.
- `execute_flows` accepts an optional `LlmTransport[A]`; generated solve
  wrappers expose the same optional transport while preserving existing
  one-argument call sites. This is the complete no-Codex test seam.
- Runtime events use uniform payload fields and assignment-based construction.
  This avoids Nim 2.3.1 `genFieldObjConstr` failures for generated variant
  artifacts. `void` endpoints are excluded from the Artifact registry because
  they are flow endpoints, not runtime values.
- Generated submit remains anonymous/erased inside `ModelCallSpec`; attempts
  to store typed or named recursive generic callbacks triggered Nim compiler
  internal errors. The erased callback preserves generic code generation and
  isolates that workaround.

No Codex agent message, Cilk worker, or reader-owned plan mutation was added.
Readers now perform POSIX pipe framing and send events through the runtime
context channel; the main thread
solely owns `CodexRuntime` and `WorkPlan`.

Current code:

- `src/vecherinka_runtime.nim` defines the recursive `Flow[A]` recipe.
- `src/vecherinka_comptime.nim` lowers typed flows into that recipe and
  generates one tagged `VecherinkaArtifact` type per macro expansion.
- `Flow.continuation` represents sequential composition.
- `fk_top` declares a named root and its body.
- `fk_ref` names another root.
- `fk_model` is an asynchronous model boundary.
- `fk_model.prepare` produces a `ModelCallSpec`; its erased `submit` field
  holds the generated full submit adapter, distinct from generic
  `RuntimeContext.transport`.
- `fk_fanout` creates indexed branches and a coalescer.
- `fk_lift` creates input-dependent indexed work and a constructor.
- `fk_so` produces another `Flow` after receiving an input.
- `WorkNode`, lazy execution, joins, generated submit, and the fake/injected
  transport seam implement the current slice. Codex submission and pipe
  transport are deliberately not wired yet.

This implementation task changed the runtime, added a focused runtime test,
and updated this document. Existing unrelated working-tree changes were
preserved.
Four isolated Nim probes were compiled outside the repository:

- `/private/tmp/generated_submit_probe.nim`: generated full submit function
  unpacks typed input, builds LLM context/tools, calls raw transport, and
  materializes typed output; passed under ARC.

- `/private/tmp/vecherinka_resume_probe.nim`: `Resume` and nested `so`, passed
  under default memory management, ARC, and ORC.
- `/private/tmp/probe_b_joinstate.nim`: unified fanout/lift join, out-of-order
  completion, nested joins, and empty lift, passed under default memory
  management and ARC.
- `/private/tmp/probe_c_async_submit.nim`: deterministic asynchronous submit,
  pending request lookup, event delivery, and continuation, passed with Nim
  2.3.1 and `--threads:on`.

## System goal

Vecherinka is a typed declarative language for orchestrating Codex agents.
Generated data is an executable structural recipe. The recipe says what work
can be attempted, how typed artifacts move between operations, where branches
join, and where runtime output creates more recipe structure.

The runtime must:

1. accept an entry artifact;
2. lazily activate only the recipe node that currently has an input;
3. issue multiple independent API calls without blocking on each one;
4. resume the correct continuation when an artifact arrives;
5. preserve indexed fanout/lift joins and typed artifact variants;
6. keep all mutable orchestration state on the main thread;
7. retain enough work-node provenance to inspect inputs, outputs, parents,
   requests, joins, failures, and completion.

This is API orchestration, not CPU scheduling. Cilk is useful as a mental model
for spawn/sync at fanout and lift, but the first runtime needs no Cilk worker
pool and no CPU worker pool.

## Non-goals

- eagerly converting every `Flow` node into a runtime graph node;
- recursive evaluator calls on the Nim call stack;
- parallel CPU execution;
- generic serialization of arbitrary domain types;
- using `default(A)` as an artifact input;
- allowing reader threads to mutate `WorkPlan` or `CodexRuntime`;
- making the Codex transport part of the recipe evaluator.

## Two structures, not one

There are two related structures.

### Immutable recipe

`Flow[A]` is the compile-time-generated structural recipe. It is shared by all
activations and is never mutated during execution.

`fk_top` and `fk_ref` are recipe navigation. `fk_raw` and `fk_it` are immediate
operations. `fk_model`, `fk_fanout`, `fk_lift`, and `fk_so` are boundaries where
runtime state may be suspended or expanded.

### Dynamic execution ledger

The work graph is the runtime ledger for one execution. It contains only
materialized operations and joins. It is not a copy of the recipe.

The executor uses short-lived activation tokens. A token carries one real
artifact and a return destination. Suspended model calls and joins retain the
return destination until they can produce an artifact.

## Core runtime records

The following is close to the final Nim shape. The generated artifact type is
represented by `A`; generated solve code will instantiate the runtime with its
concrete `VecherinkaArtifact`.

```nim
type
  WorkID = uint64

  WorkState = enum
    ws_waiting,
    ws_running,
    ws_done,
    ws_failed,
    ws_cancelled

  WorkKind = enum
    wk_model,
    wk_fanout,
    wk_lift,
    wk_so

  ResumeKind = enum
    rk_continue,
    rk_join,
    rk_finished

  Resume[A] = ref object
    case kind: ResumeKind
    of rk_continue:
      flow: Flow[A]
      next: Resume[A]
    of rk_join:
      join_id: WorkID
      slot: int
    of rk_finished:
      discard

  Activation[A] = object
    flow: Flow[A]
    input: A
    parent: Option[WorkID]
    resume: Resume[A]

  WorkNode[A] = ref object
    id: WorkID
    kind: WorkKind
    state: WorkState
    parent: Option[WorkID]
    input: Option[A]
    output: Option[A]
    request_id: Option[RequestId]
    error_message: Option[string]

  JoinKind = enum
    jk_fanout,
    jk_lift

  JoinFinalizer[A] = proc(
    values: seq[A];
    original: Option[A]
  ): A {.nimcall.}

  JoinState[A] = ref object
    id: WorkID
    kind: JoinKind
    parent: Option[WorkID]
    remaining: int
    slots: seq[Option[A]]
    resume: Resume[A]
    original: Option[A]
    finalizer: JoinFinalizer[A]

  PendingModel[A] = ref object
    node_id: WorkID
    request_id: RequestId
    resume: Resume[A]

  ModelCallSpec[A] = object
    profile: ProfileSpec
    prompt: string
    input: A
    submit: pointer                 ## erased generated adapter
    ## The generated Artifact variant expected from this model call. Keep this
    ## as an ordinal/portable runtime value: the generated enum type is a
    ## macro-local type and must not leak into the generic runtime module.
    output_kind: int
    ## Generated code supplies typed response materialization containing the
    ## case over output_kind. Generated submit passes it to transport.
    debug_output: proc(output_kind: int; output: LlmOutput): A {.nimcall.}

  ## Structured output delivered by fake or real transport. Real transport
  ## populates tool_name/arguments from Codex server output.
  LlmOutput = object
    tool_name: string
    arguments: JsonNode

  ## Transport-facing spec. Generated submit functions fill its type-specific
  ## context, tools, and response materializer.
  LlmCallSpec[A] = object
    profile: ProfileSpec
    prompt: string
    typed_context: string
    tools: DynamicToolRegistry
    output_kind: int
    materialize: proc(output_kind: int; output: LlmOutput): A {.nimcall.}

  LlmTransport[A] = proc(
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
  ) {.nimcall.}

  RuntimeContext[A] = ref object
    events: Channel[GlobalEvent]
    events_open: bool
    transport: LlmTransport[A]
    ## Optional handwritten ModelSubmitter remains test compatibility only.
    submitter: ModelSubmitter[A]
    next_request_id: int64

  WorkPlan[A] = object
    roots: Table[string, Flow[A]]
    entry: Flow[A]
    ready: Deque[Activation[A]]
    nodes: Table[WorkID, WorkNode[A]]
    joins: Table[WorkID, JoinState[A]]
    pending_models: Table[string, PendingModel[A]]
    next_work_id: WorkID
    finished: bool
    failed: bool
```

`WorkNode.input` and `WorkNode.output` satisfy provenance needs. They are not
the scheduler's input slots. The active input is in `Activation`; indexed join
slots are in `JoinState`. This removes the old `input_values` concept.

`Option[A]` is intentional. It represents absence without constructing an
invalid generated tagged artifact. Never replace it with `default(A)`.

`ModelCallSpec.output_kind` is not a scheduler input and is not an arbitrary
model hint. It is the expected output branch of the model node. The generated
debug constructor is the type-safe bridge from generic runtime code back into
the macro-generated `VecherinkaArtifact` object variant.

## Why `after` disappears

The previous design carried both:

- `flow.continuation`, the local continuation of the current recipe node;
- `after`, the enclosing activation's continuation.

Both pieces of information are necessary. Separate fields make nested `so`,
fanout, and lift hard to reason about. `Resume` combines them into one return
destination.

For a suspended node:

```nim
let parent_resume = activation.resume
let local_resume = if current.continuation.isNil:
  parent_resume
else:
  Resume[A](
    kind: rk_continue,
    flow: current.continuation,
    next: parent_resume
  )
```

The executor later delivers the result to `local_resume`.

- `rk_continue` schedules a Flow with the artifact.
- `rk_join` writes the artifact into one indexed slot.
- `rk_finished` records execution completion.

The helper is deliberately constant-size:

```nim
proc prepend_continuation[A](
    flow: Flow[A];
    parent: Resume[A]
): Resume[A] =
  if flow.isNil:
    parent
  else:
    Resume[A](kind: rk_continue, flow: flow, next: parent)
```

It does not recursively flatten a long continuation chain. The isolated probe
showed that nested `so` requires the linked `next` field; a flat target is
insufficient.

Nim generic object constructors need explicit instantiation in this area:

```nim
Resume[A](kind: rk_continue, flow: next_flow, next: parent)
Activation[A](flow: flow, input: value, parent: none(WorkID),
  resume: parent)
```

## Lazy evaluator

The evaluator is an iterative state machine. It never calls itself to handle a
child recipe.

```nim
proc execute_flows[A](
    context: RuntimeContext[A];
    top_level_flows: seq[Flow[A]];
    input: A
) =
  var plan = init_work_plan(top_level_flows)
  plan.ready.add Activation[A](
    flow: plan.entry,
    input: input,
    parent: parent,
    resume: Resume[A](kind: rk_finished)
  )

  while not plan.finished:
    drain_ready_batch(context, plan)

    if plan.ready.len == 0 and not plan.finished:
      handle_global_event(plan, recv_global_event(plan.context))
```

`drain_ready_batch` has a bounded budget so a large immediate recipe cannot
starve incoming model completions.

```nim
proc handle_activation[A](
    context: RuntimeContext;
    plan: var WorkPlan[A];
    activation: Activation[A]
) =
  var current = activation.flow
  var value = activation.input

  while not current.isNil:
    case current.kind
    of fk_top:
      current = current.body

    of fk_ref:
      current = resolve_root(plan.roots, current.name)

    of fk_raw:
      value = current.value
      current = current.continuation

    of fk_it:
      value = current.projector(value)
      current = current.continuation

    of fk_model:
      suspend_model(context, plan, current, value,
        activation.parent, activation.resume)
      return

    of fk_so:
      let child = current.execute(value)
      let resume = prepend_continuation(current.continuation,
        activation.resume)
      plan.ready.add Activation[A](
        flow: child,
        input: value,
        parent: activation.parent,
        resume: resume
      )
      return

    of fk_fanout:
      suspend_fanout(context, plan, current, value,
        activation.parent, activation.resume)
      return

    of fk_lift:
      suspend_lift(context, plan, current, value,
        activation.parent, activation.resume)
      return

  deliver_resume(context, plan, activation.resume, value)
```

`prepend_continuation` is constant-size: it creates one `rk_continue` frame for
the current node's continuation and points it at the parent resume. The
evaluator itself remains a loop and never recursively handles a child.

`fk_top`, `fk_ref`, `fk_raw`, and `fk_it` do not allocate WorkNodes. They either
navigate the recipe or transform the current artifact immediately.

## Root initialization

The plan stores root bodies, not top wrappers:

```nim
proc init_work_plan[A](flows: seq[Flow[A]]): WorkPlan[A] =
  for top in flows:
    doAssert top.kind == fk_top
    if result.roots.hasKey(top.root):
      raise newException(ValueError, "duplicate root: " & top.root)
    result.roots[top.root] = top.body

    if top.entry:
      if not result.entry.isNil:
        raise newException(ValueError, "multiple entry roots")
      result.entry = top.body

  if result.entry.isNil:
    raise newException(ValueError, "missing entry root")
```

`fk_ref` resolves at activation time. It does not clone or mutate a recipe.
Each activation gets independent runtime state.

Do not use `ref_hops_since_boundary`. It can reject valid lazy structures and
does not define the real safety policy. Pure alias cycles should be rejected by
static validation if possible. Runtime-determined cycles remain legal. Add an
execution budget, cancellation, or timeout as the general safety valve.

## Work-node creation

WorkNodes are ledger entries, not execution frames.

```nim
proc new_work_node[A](
    plan: var WorkPlan[A];
    kind: WorkKind;
    parent: Option[WorkID];
    input: Option[A]
): WorkID =
  let id = plan.next_work_id
  inc plan.next_work_id
  plan.nodes[id] = WorkNode[A](
    id: id,
    kind: kind,
    state: ws_running,
    parent: parent,
    input: input,
    output: none(A),
    request_id: none(RequestId),
    error_message: none(string)
  )
  id
```

The exact `none(A)` spelling must be checked against Nim's generic inference;
the important rule is that no Artifact value is fabricated.

When an operation produces an artifact, update its ledger node before routing
the artifact through `Resume`. Child branch nodes reference their join node as
parent. The graph therefore records both operation provenance and dynamic
fanout/lift structure without copying all recipe nodes.

## Unified joins

Fanout and lift differ only in how child inputs are produced and how the final
artifact is constructed.

```nim
proc begin_join[A](
    context: RuntimeContext;
    plan: var WorkPlan[A];
    kind: JoinKind;
    child_activations: seq[tuple[index: int, flow: Flow[A], input: A]];
    parent: Option[WorkID];
    original: Option[A];
    finalizer: JoinFinalizer[A];
    resume: Resume[A]
) =
  let join_id = new_work_node(
    plan,
    if kind == jk_fanout: wk_fanout else: wk_lift,
    parent,
    original
  )

  var join = JoinState[A](
    id: join_id,
    kind: kind,
    parent: parent,
    remaining: child_activations.len,
    slots: newSeq[Option[A]](child_activations.len),
    resume: resume,
    original: original,
    finalizer: finalizer
  )
  plan.joins[join_id] = join

  if child_activations.len == 0:
    finalize_join(context, plan, join_id)
    return

  for child in child_activations:
    plan.ready.add Activation[A](
      flow: child.flow,
      input: child.input,
      parent: some(join_id),
      resume: Resume[A](
        kind: rk_join,
        join_id: join_id,
        slot: child.index
      )
    )
```

The actual implementation should use separate `begin_fanout` and
`begin_lift` wrappers to obtain child inputs and child recipes, but one
`JoinState` and one `accept_join_result` path.

The ledger input is `original` for lift and `none(A)` for fanout. The finalizer
must handle an empty child list without reading a child slot.

Join result acceptance:

```nim
proc accept_join_result[A](
    context: RuntimeContext;
    plan: var WorkPlan[A];
    join_id: WorkID;
    slot: int;
    value: A
) =
  let join = plan.joins[join_id]
  if slot < 0 or slot >= join.slots.len:
    fail_plan(plan, "invalid join slot")
    return
  if join.slots[slot].isSome:
    fail_plan(plan, "duplicate join result")
    return

  join.slots[slot] = some(value)
  dec join.remaining

  if join.remaining == 0:
    finalize_join(context, plan, join_id)
```

The slots are pre-sized and indexed by declaration/result index. Do not use a
map whose absence and empty value can be confused. The isolated join probe
found that `Table[int, Option[A]]` needs explicit key validation; a sequence of
pre-sized `Option[A]` slots is simpler.

`finalize_join` materializes ordered results, calls the generated coalescer or
constructor, stores the parent output, deletes the join execution state, and
delivers the result through the join's `resume`.

Lift must preserve the original input. Empty lift is a valid immediate join and
must execute its constructor path explicitly.

## Model boundary

The model boundary is the first real suspension point.

```nim
proc suspend_model[A](
    context: RuntimeContext;
    plan: var WorkPlan[A];
    flow: Flow[A];
    input: A;
    parent: Option[WorkID];
    resume: Resume[A]
) =
  let node_id = new_work_node(plan, wk_model, parent, some(input))
  let spec = prepare_generated_model_call(flow, input)

  let request_id = allocate_request_id(context)
  var node = plan.nodes[node_id]
  node.request_id = some(request_id)
  node.state = ws_waiting
  plan.nodes[node_id] = node
  plan.pending_models[request_id_key(request_id)] = PendingModel[A](
    node_id: node_id,
    request_id: request_id,
    resume: prepend_continuation(flow.continuation, resume)
  )

  ## Generated per-model submit owns concrete input/output types. Hand-written
  ## Flow values may use context.submitter as a test override.
  let submitter = if not spec.submit.isNil:
    cast[ErasedModelSubmit](spec.submit)
  elif not context.submitter.isNil:
    context.submitter
  else:
    default_model_submit[A]
  if not spec.submit.isNil:
    submitter(cast[pointer](context), request_id, addr spec)
  else:
    submitter(context, request_id, spec)
```

The generated submit may invoke transport before `suspend_model` returns, but
the main loop cannot consume its completion Event until current dispatch
returns. Thus pending entry is installed before any completion can be handled.
Fake and future real transports share one deferred asynchronous contract. Their
runtime completion values enter the context channel as `gek_runtime` events.

The generated preparation callback owns only Artifact-level recipe data:

- preserving the real packed input Artifact;
- producing model profile and prompt;
- returning the real packed input Artifact in `ModelCallSpec`;
- recording the expected output Artifact kind;
- attaching generated response materialization for that output kind.

The full model submit function is generated per `fk_model` node. Runtime
dispatch stays generic, but generated submit code knows concrete input/output
types and builds the transport-facing `LlmCallSpec`:

```nim
proc generated_submit_model_X(
    context: pointer;
    request_id: RequestId;
    spec: pointer
) {.nimcall.} =
  let typed_spec = cast[ptr ModelCallSpec[VecherinkaArtifact]](spec)
  let typed_input: InputType = unpack_input_type(typed_spec[].input)
  let llm_spec = LlmCallSpec[VecherinkaArtifact](
    profile: typed_spec[].profile,
    prompt: typed_spec[].prompt,
    typed_context: generated_context_for_input(typed_input),
    tools: generated_tools_for_output(),
    output_kind: typed_spec[].output_kind,
    materialize: typed_spec[].debug_output)
  submit_llm(cast[RuntimeContext[VecherinkaArtifact]](context), request_id,
    llm_spec)
```

`Flow[fk_model].submit` stores this generated function. `RuntimeContext` stores
only generic transport. This permits one recipe to contain model nodes with
different concrete input/output types without a single runtime type switch.
Do not pass domain values through `pointer` fields. Generated submit may emit
typed prompt/context data, typed tool schemas, and typed response materializers.

### Generated LLM-output adapter

There are two related generated functions:

1. `generated_submit_model_X` converts the Artifact input into a
   type-specific `LlmCallSpec`.
2. A generated output adapter converts LLM output into the expected concrete
   domain type, then packs it into the correct `VecherinkaArtifact` variant.

The real output adapter is required later. It will consume structured LLM
output (for example, return-tool arguments or decoded JSON), validate that
output against the model node's expected concrete type, construct that type,
and pack it with the existing generated output packer. This exact decoder is
not part of merged Slice 4/5.

Merged Slice 4/5 generates only deterministic debug materialization fitting
same role:

```nim
proc generated_materialize_output(
    expected_kind: int;
    output: LlmOutput
): VecherinkaArtifact {.nimcall.} =
  case expected_kind
  of ord(vak_expected_output):
    let typed_output =
      construct_debug_value_for_expected_type(output.arguments)
    result = VecherinkaArtifact(
      kind: vak_expected_output,
      value_expected_output: typed_output)
  else:
    doAssert false, "generated model kind is not supported"
```

`LlmCallSpec.materialize` is interface seam both paths share. Fake transport
passes synthetic `LlmOutput`. Future generated decoder will receive real
structured output and use same Artifact construction/routing contract. Do not
let fake payload handling dictate future JSON/tool decoding shape.

### Generated Artifact-kind bridge

This is the nontrivial part of the merged Slice 4/5. `A` is the macro-generated
`VecherinkaArtifact`, whose `kind` discriminator and `value_N` branches are
generated per expansion. The generic runtime cannot name that gensym enum
directly. Keep the generic runtime intact by using the discriminator ordinal
in `ModelCallSpec.output_kind`, and generate the typed response materializer
stored in `ModelCallSpec.debug_output`.

Preferred generation route: use `ArtifactRegistry` as primary source. Its
`ArtifactTypeInfo` already contains concrete type, discriminator symbol, and
value-field symbol. Use `getTypeInst` as structural verification and as a
discovery aid only when node is semantically typed.

```nim
let artifact_inst = registry.artifact_name.getTypeInst
let artifact_object = normalize_artifact_object_type(artifact_inst)
let variant = find_artifact_rec_case(artifact_object)
let discriminator = find_case_discriminator(variant)

assert_same_type(discriminator.type, registry.kind_name)

# emit beside the generated Flow:
proc debug_artifact_output(
    expected_kind: int;
    output: LlmOutput
): VecherinkaArtifact =
  case expected_kind
  of ord(vak_output_type):
    VecherinkaArtifact(
      kind: vak_output_type,
      value_output_type: construct_debug_value(output_type, output.arguments))
  else:
    doAssert false, "unsupported generated model output kind"
```

The implementation uses `ArtifactRegistry` metadata directly for the generated
object variant: `kind_name`, `ArtifactTypeInfo.kind_name`, `artifact_name`, and
`value_name` are stable within each macro expansion. A future
`normalize_artifact_object_type` helper may validate that metadata through
`getTypeInst`; it is not needed for the current generated case and was not
added to this slice.

The registry is populated from typed flow endpoints before lowering, so no
runtime type switch or name-only fallback is needed here. Do not abandon the
generic runtime code: generated symbols remain local to the macro expansion.

`construct_debug_value` must be deterministic and typed. The current first
slice uses `debug:<tool-name>` for strings and a typed zero fallback for other
registered output types; this is sufficient to validate branch selection and
routing, but not semantic output. The next decoder slice replaces that
fallback with generated payload parsing or injected per-type factories.

The adapter is embedded as an erased callback in the prepared spec. Its
close-to-code shape is:

```nim
proc generated_submit(context: pointer; request_id: RequestId; spec: pointer) =
  let typed_spec = cast[ptr ModelCallSpec[VecherinkaArtifact]](spec)
  let typed_input = unpack_expected_input(typed_spec[].input)
  submit_llm(cast[RuntimeContext[VecherinkaArtifact]](context), request_id,
    LlmCallSpec[VecherinkaArtifact](
      typed_context: $typed_input,
      tools: generated_tools_for_output(),
      output_kind: typed_spec[].output_kind,
      materialize: typed_spec[].debug_output))
```

Keep the current packer and unpacker pointers inside the generated Flow. Never
point at a stack-local domain value. The generated preparation expression must set
`output_kind: ord(vak_output_type)` and
`debug_output: debug_artifact_output`. Generated submit passes that callback to
`LlmCallSpec.materialize`.

## Deterministic fake transport

The fake transport is mandatory before real Codex integration. It receives the
same generated, type-specific `LlmCallSpec` that future Codex transport will
receive.

```nim
type
  LlmTransport[A] = proc(
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
  ) {.nimcall.}

proc debug_transport[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  let output = LlmOutput(
    tool_name: "debug_return",
    arguments: debug_json_payload())
  var event: RuntimeEvent[A]
  event.kind = rev_model_artifact
  event.request_id = request_id
  event.output_kind = spec.output_kind
  event.output = output
  event.materialize = spec.materialize
  event.has_output = true
  enqueue_runtime_event(context, event) # serializes into context channel
```

`debug_transport` must never resume inline. It only exercises generated
type-specific LLM data and queues raw output plus its generated materializer.
The runtime thread materializes the Artifact while handling the Event. It must
not call Codex, send an agent message, parse a server response, or create reader
threads. A test may replace the generated materializer or transport to inject
more specific fixtures.

Model completion handling:

```nim
proc handle_model_artifact[A](
    context: RuntimeContext;
    plan: var WorkPlan[A];
    event: ModelArtifactEvent[A]
) =
  let key = request_id_key(event.request_id)
  if not plan.pending_models.hasKey(key):
    fail_plan(plan, "unknown model completion")
    return

  let pending = plan.pending_models[key]
  plan.pending_models.del(key)

  let artifact = event.materialize(event.output_kind, event.output)
  var node = plan.nodes[pending.node_id]
  node.output = some(artifact)
  node.state = ws_done
  plan.nodes[pending.node_id] = node

  deliver_resume(context, plan, pending.resume, artifact)
```

Request ID is the authoritative pending lookup key. Work ID remains provenance
metadata and should be checked when present, not used as a second independent
routing table.

## `so`

`fk_so` is a lazy recipe-expansion boundary:

```nim
let child = flow.execute(input)
let child_resume = prepend_continuation(
  flow.continuation,
  activation.resume
)
ready.add Activation[A](
  flow: child,
  input: input,
  parent: activation.parent,
  resume: child_resume
)
```

The callback runs only after a real input exists. The generated child runs
fully before the outer continuation runs. No recipe mutation occurs.

Record a `wk_so` WorkNode only if expansion provenance is needed. It is not
required for scheduling.

## Event and transport architecture

The structural app-server boundary is now present. Agent message submission and
real model-output decoding remain future work.

```nim
type
  EventKind = enum
    ev_stdout_line,
    ev_stderr_line,
    ev_model_artifact,
    ev_model_error,
    ev_stdout_closed,
    ev_stderr_closed,
    ev_reader_error,
    ev_process_exit,
    ev_shutdown
```

One reader thread blocks on the Codex stdout POSIX descriptor. One reader
thread blocks on stderr. Each owns a partial-line buffer and sends line Events
through the context-owned channel. Neither parses JSON or mutates runtime state.

The main thread, acting as messenger/coordinator, now:

1. drains ready activations for a bounded batch;
2. blocks on `recv_global_event(plan.context)` when ready work is empty;
3. dispatches `gek_runtime` completions into the Vecherinka executor;
4. parses stdout JSON;
5. calls existing `CodexRuntime.handle_message` / `accept_json`;
6. handles model results and resumes activations.

Callbacks enqueue Events. They never re-enter `handle_activation`. The main
thread is the sole owner of `CodexRuntime`; no separate messenger thread owns
or receives it.

Do not create an event for every immediate continuation. The main-owned ready
deque is simpler and avoids needless channel traffic. Runtime completions and
reader input remain channel events.

Shutdown order:

```text
stop scheduling
wake or close reader descriptors
join stdout reader
join stderr reader
stop/wait Codex process
close channel
release pending model callback state
```

## Static and runtime invariants

- `Flow` recipes are immutable after lowering.
- `A` is the generated `VecherinkaArtifact`.
- No `input_values` map exists.
- No `default(A)` is used as an input.
- Main thread is the sole owner of `WorkPlan` and `CodexRuntime`.
- Every WorkID is unique within one plan.
- Every request ID maps to at most one pending model node.
- Every join slot is written exactly once.
- Fanout results are coalesced in declaration order.
- Lift results are constructed using generated result indexes.
- Empty lift completes explicitly.
- Every suspended operation retains exactly one `Resume`.
- `so` child work completes before the outer continuation.
- Unknown, duplicate, or stale completion events fail safely.
- Reader threads never parse JSON.
- Generated submit plus fake/raw transport obey one deferred-completion
  contract.
- Global event channel remains open until both readers have joined.
- Reader threads borrow child descriptors; `CodexRuntime` remains their owner.
- Main thread is sole owner of `CodexRuntime` and handles stdout JSON.

## Implementation order

### Slice 1: lazy execution core

Files: `src/vecherinka_runtime.nim` and a focused runtime test.

Implement:

1. `WorkState`, `WorkKind`, `Resume`, `Activation`.
2. Work-node ledger keyed by `WorkID`.
3. root body lookup and entry validation.
4. iterative handling of top/ref/raw/it.
5. model suspension with retained `Resume`.
6. unified join state and indexed result acceptance.
7. lazy fanout and lift activation.
8. `so` child activation with composed return path.
9. main-owned ready deque.
10. deterministic submit callback seam so model suspension can be tested without
    a Codex process.

No Codex process, POSIX readers, or real JSON event transport yet.

### Slices 2 and 3: implemented

`ModelCallSpec[A]`, injected `ModelSubmitter[A]`, deferred model artifact
Events, pending request tracking, and deterministic fake path are present.
Generated model nodes emit concrete `prepare` callbacks. Those callbacks
unpack and validate the actual input Artifact, then return its packed value in
`ModelCallSpec`. Generated solve code packs its typed entry input and passes it
to `execute_flows`; it no longer discards the input.

The existing generated output packer remains attached to `Flow` for a future
Codex response adapter. JSON response decoding, tool schema transport, POSIX
readers, and process supervision remain outside this plan's merged debug
slice; they require the real Codex protocol boundary.

The focused execution test proves the complete fake model-to-continuation path
without launching Codex.

### Merged Slice 4/5: generated submit and debug transport boundary

This completed slice combines the useful pre-transport parts of the former
Codex and reader slices, then deliberately stops before real agent
communication.

#### Scope

1. Extend `ModelCallSpec[A]` with an erased generated per-node submit callback,
   `output_kind`, and generated typed response materialization.
3. Generate full submit function per model node. It unpacks concrete input,
   builds type-specific LLM context/tool registry, and calls generic transport.
4. Define transport-facing `LlmCallSpec[A]` carrying generated context, tools,
   expected kind, and materializer.
5. Use the typed `ArtifactRegistry` branch metadata to construct the generated
   Artifact; leave `getTypeInst` normalization as a future verification helper.
6. Emit debug-materializer case over expected kind. Each branch constructs valid
   Artifact with matching `kind` and `value_N`; this stands in for future real
   LLM-output conversion.
7. Make fake transport invoke generated materializer and queue ordinary
   deferred model-artifact Event.
8. Run generated flow end-to-end through pending lookup, WorkNode output,
   joins, `so`, and continuations.

#### Explicit non-scope

- Do not call `CodexRuntime`.
- Do not send an agent message.
- Do not register a real return tool or decode a real server response.
- Do not add POSIX stdout/stderr readers, process supervision, or shutdown
  plumbing.
- Do not add Cilk workers or CPU parallelism.

The transport boundary must remain replaceable: later Codex transport can
consume the same `LlmCallSpec` and obtain the same Artifact Event, without
changing generated submit adapters, lazy activation, pending requests, joins,
or continuations. Real transport gets a separate future plan after this slice,
not an implicit part of Slice 4/5.

#### Implemented file-level work

`src/vecherinka_runtime.nim`:

- add generated `submit` pointer, `output_kind`, and generated materializer to
  `ModelCallSpec[A]` (the submit pointer is kept on the prepared spec rather
  than on `fk_model`);
- add generic `LlmCallSpec[A]` and raw `LlmTransport[A]` seam;
- dispatch `spec.submit` before any context-level handwritten test override;
- make fake transport invoke materializer and enqueue an Event;
- reject a missing constructor as a model failure, not as an inline resume.

`src/vecherinka_comptime.nim`:

- extend `lower_model_call` to fill output kind, materializer, and submit;
- generate full submit function which unpacks concrete input and builds
  type-specific LLM context/tool data;
- use existing `ArtifactRegistry` metadata for static branch construction;
- emit one deterministic debug materializer per model output type, using
  registry discriminator/value identifiers;
- leave real structured-output decoder generation as a separate follow-up;
- keep the generated input unpacker and output packer type-checked against the
  actual Artifact object;
- keep the generic registry-based route; no runtime name-based fallback is
  needed in this slice.

`src/vecherinka_runtime_execution_test.nim`:

- exercise a generated model flow, not only hand-written `Flow[string]`;
- assert generated submit sees real typed input and produces type-specific LLM
  context/tools;
- assert generated `ModelCallSpec` carries expected kind;
- assert fake Event delivery completes the generated model path; the generated
  materializer constructs the matching Artifact discriminator/value branch;
- run the output through continuation, fanout/lift, and `so` paths.

#### Close-to-code pseudocode

```nim
type
  ModelCallSpec[A] = object
    profile: ProfileSpec
    prompt: string
    input: A
    submit: pointer
    output_kind: int
    debug_output: proc(output_kind: int; output: LlmOutput): A {.nimcall.}

  LlmOutput = object
    tool_name: string
    arguments: JsonNode

  LlmCallSpec[A] = object
    profile: ProfileSpec
    prompt: string
    typed_context: string
    tools: DynamicToolRegistry
    output_kind: int
    materialize: proc(output_kind: int; output: LlmOutput): A {.nimcall.}

proc generated_prepare(input: VecherinkaArtifact):
    ModelCallSpec[VecherinkaArtifact] {.nimcall.} =
  discard unpack_expected_input(input)
  ModelCallSpec[VecherinkaArtifact](
    profile: profile,
    prompt: prompt,
    input: input,
    submit: cast[pointer](generated_submit),
    output_kind: ord(vak_expected_output),
    debug_output: generated_materialize_output)

proc generated_materialize_output(
    expected_kind: int;
    output: LlmOutput
): VecherinkaArtifact {.nimcall.} =
  case expected_kind
  of ord(vak_expected_output):
    result = VecherinkaArtifact(
      kind: vak_expected_output,
      value_expected_output:
        construct_debug_value_for_expected_type(output.arguments))
  else:
    doAssert false, "generated model kind is not supported"

proc generated_submit_model_X(
    context: pointer;
    request_id: RequestId;
    spec: pointer
) {.nimcall.} =
  let typed_input = unpack_expected_input(spec.input)
  let llm_spec = LlmCallSpec[VecherinkaArtifact](
    profile: spec.profile,
    prompt: spec.prompt,
    typed_context: generated_context_for_input(typed_input),
    tools: generated_tools_for_output(),
    output_kind: spec.output_kind,
    materialize: generated_materialize_output)
  submit_llm(context, request_id, llm_spec)

proc debug_transport[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  let output = LlmOutput(
    tool_name: "debug_return",
    arguments: debug_json_payload())
  var event: RuntimeEvent[A]
  event.kind = rev_model_artifact
  event.request_id = request_id
  event.output_kind = spec.output_kind
  event.output = output
  event.materialize = spec.materialize
  event.has_output = true
  enqueue_runtime_event(context, event)
```

The current debug helper produces a legal typed value for every registered
output type, with visible `debug:<tool-name>` values for strings and typed zero
fallbacks for other types. The real decoder slice replaces those fallbacks
with generated/injected factories. Tests assert output kind, typed context,
tool registry, and completion routing rather than semantic model text.

#### Slice completion checks

- all current runtime tests still pass;
- generated model preparation contains the real input Artifact;
- generated `ModelCallSpec.output_kind` names the model's output branch;
- registry metadata generates the actual macro-generated variant branch (the
  optional `getTypeInst` normalization remains a future robustness helper);
- every generated case branch constructs the matching discriminator/value pair;
- generated submit builds type-specific `LlmCallSpec`;
- fake transport remains deferred and produces a normal Event;
- multiple outstanding model nodes complete in any order;
- WorkNode outputs, nested continuations, `so`, fanout, lift, and empty lift
  remain correct;
- no Codex process, message send, pipe reader, or thread-owned plan mutation
  appears in the diff.

### Structural POSIX IPC plumbing: implemented

`src/vecherinka_runtime.nim` now provides one `RuntimeContext`-owned
`Channel[GlobalEvent]`,
one reader thread per Codex output descriptor, independent JSONL framing, EOF
events, reader errors, and a private stop pipe. `execute_flows` initializes a
Codex runtime when one is not supplied, opens the channel, starts readers,
runs the blocking unified loop, then joins readers, closes the channel, and
deinitializes an owned Codex runtime.
`GlobalEventMessenger` and `drain_global_events` call existing Codex JSON
acceptance only from the `CodexRuntime` owner thread.

`src/vecherinka_runtime_ipc_test.nim` covers split/multiple lines, CRLF,
unterminated final lines, concurrent stdout/stderr drainage, EOF, and waking
blocked readers during shutdown. No Codex agent message path is included.

## Required tests

### Recipe handling

- top immediately enters body;
- ref resolves to root body;
- raw replaces the current artifact;
- it transforms the current artifact;
- recipes remain unchanged;
- repeated ref activation has independent WorkNodes;
- pure alias cycle is rejected or bounded by explicit policy.

### Resume semantics

- model continuation runs exactly once;
- nested `so` runs child, then local continuation, then parent destination;
- join result routes to the correct indexed slot;
- nested joins preserve their independent return destinations.

### Joins

- fanout receives identical input in every branch;
- out-of-order fanout completions coalesce in declaration order;
- fanout parent continuation runs once;
- lift preserves original input;
- lift result indexes remain stable;
- empty lift invokes its constructor path;
- duplicate and invalid slots fail safely.

### Fake model transport

- generated submit never resumes inline;
- fake transport never resumes inline;
- pending request exists before completion Event is processed;
- deterministic Artifact output reaches the continuation;
- unknown request ID fails safely;
- model failure marks the WorkNode and plan correctly.

### Merged debug event loop

- multiple fake model calls remain outstanding;
- generated output-kind cases construct valid Artifact variants;
- generated fake completions arrive as deferred Events;
- output Events resume the right model continuation and WorkNode;
- no Codex process, agent message, pipe reader, or reader-thread mutation
  exists in this slice.

## Decision summary

Use lazy structural recipes plus an event-driven activation machine.

Use one linked `Resume`, not `after` plus `CompletionTarget`.

Use one indexed `JoinState`, not separate fanout/lift execution mechanisms.

Use WorkNodes as provenance ledger entries, not as an eager copy of Flow.

Use generated type-specific submit adapters plus deterministic deferred fake
transport before real Codex transport.

Use the main thread for all orchestration state and reader threads only for
blocking pipe reads.

Keep Cilk out of the first implementation. The useful concurrency is concurrent
API requests already represented by pending model nodes.
