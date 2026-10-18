#import "state_machine_api_styles.typ": *

#set page(margin: 20mm)
#set text(size: 10pt)
#set par(leading: 0.62em)
#set heading(numbering: "1.")
#show heading.where(level: 1): set text(size: 16pt, weight: "bold")

#align(center)[
  #text(size: 21pt, weight: "bold")[Event-driven state machine]
  #linebreak()
  #text(size: 14pt, fill: rgb("52616D"))[Consistency laws — WIP]
]

#v(10pt)
#status-panel("Proposed", title: "Planning document, not implementation spec", number: "P1")[
  This is the active theory-planning file. Code blocks use the F\* language
  tag for code formatting; their equations remain mathematical pseudocode,
  not promised compiler-valid syntax. It replaces the earlier Markdown plan;
  the F\* source remains an earlier skeleton and has not been edited in this
  planning pass.
]

#status-panel("Decided", title: "Proof boundary", number: "D1")[
  The core proves consistency among the supplied DAG, LEG implementations,
  occurrence lookup, state queries, event transitions, and recovery. Recovery
  receives the caller's DAG/program context. The exclusions are collected in
  the non-goal decision in #link(<decision:non-goals>)[D6].
]

#text(size: 13pt, weight: "bold")[Status labels]

#grid(
  columns: (1fr, 1fr), gutter: 7pt,
  status-panel("Decided", [Direction already established in the discussion.]),
  status-panel("Proposed", [Smallest current contract set that appears to establish the intended observations.]),
  status-panel("Open", [Unfinished encoding or proof work; it need not mean the behavior is undecided.]),
  status-panel("Derived", [A theorem intended to follow from other laws, not another machine field.]),
)

= Setting and sources of truth <sec:sources-of-truth>

Fix one input `x`, one supplied DAG `d`, one machine implementation, one
equality-capable occurrence ID type, one state value `s`, and a valid event
history `H`. Let `s_H` be the state obtained by replaying `H` from
`initial_state`. Replay is notation for proofs; it is not the correctness
predicate. Unless an argument is shown, formulas below are scoped to the
single complete machine record and its selected `DagInstance`; `d` is that
record's `raw_dag`, and `root_id` is its root-ID field. `DeclaredOccurrence(d,H,id,o)` means the static DAG or a generator
result already in `H` permits descriptor `o` for `id`; see the
#link(<def:declared-occurrence>)[definition of `DeclaredOccurrence`].

#definition-card("Minimum source responsibilities", [
  - The DAG gives static work and the interpretation of generated graph results.
  - An occurrence ID names work; its occurrence descriptor gives ordered
    input sources and selects a LEG backing implementation.
  - A LEG implementation gives the input assembler and node-specific
    computation or validation rule.
  - `lookup_occurrence(state,id)` makes the current ID-to-occurrence mapping
    and optional typed completion value observable to the machine.
  - History supplies the independent expected declaration and completion map.
  - State queries expose actions; `accept_event` updates state after a valid
    completion.
]) <def:minimum-sources>

#definition-card("Machine parameters and type fields", [
  `MachineForInput(input_type,x)` is one complete record; `input_type` and
  `x` are parameters, not stored fields. The record below is the authoritative
  field inventory. Its abstract descriptor type packages a node ID, LEG
  backer, and ordered sources compatible with that backer's typed input
  telescope. Alternative graph branches may select different backers and
  dependent output families for the same ID.

  The local/external/generator action and event types are derived dependent
  aliases, not arbitrary machine-supplied value families. They preserve the
  selected occurrence and, for dependent outputs, the input index. `root_id`
  is a stored ID; `RootOutputType` is derived from its descriptor and keeps
  the root's input-indexed result.
]) <def:machine-inventory>

#definition-card("Machine meaning and operation fields", [
  The record separates graph meaning from current machine observations.
  The independent static/generated interpreters define descriptor meaning;
  lookup, action queries, event acceptance, and terminal output expose or
  change runtime state. Exact fields and signatures appear once in the record
  below. Their independence is explained in
  #link(<def:occurrence-interpreters>)[the interpreter definition]. Recovery uses the separately supplied,
  DAG-parameterized `StateJournaler` in
  #link(<def:state-journaler>)[its definition]; the DAG is not serialized.
]) <def:machine-operations>

#definition-card("Proof fields required to construct the machine", [
  The selected raw DAG is packaged with its exact-DAG proofs:
  `HistoryTerminalCoherence` and `DagProductivity`. Input assembly is a
  derived theorem from productivity and the event-validity rules, not another
  required DAG proof. The `initial_state` field directly requires the
  empty-history `StateRepresents` refinement; there is no separate proof field.
  The `accept_event` field takes a represented
  state and an erased, node-specific result certificate; its exact
  accept/reject law is specified in @sec:event-validity. The completion-aware
  lookup law rules out the previous conflicting-history counterexample; see
  @sec:completion-state-adequacy. The journaler
  supplies a raw-state round-trip law, but recovery of the erased
  `represented_state` witness remains open in @sec:formalization.

  Each inductive history step separately carries `EventValidAt` for its
  prefix; this is a history-constructor proof, not a machine field. Graph-ID
  freshness is part of that event-validity definition, so exclusive
  membership is derived by induction. `StateRepresents`, `EventValidAt`,
  readiness, and observations are definitions. Query visibility and
  terminality are derived using `HistoryObservationFaithful`. All listed
  proof fields are required to construct the complete machine; none are
  optional callbacks.
]) <def:machine-proofs>

The proof fields refer to the exact `raw_dag` inside the selected
#link(<def:dag-instance>)[`DagInstance` field], and therefore to the same
interpreters and DAG value used by machine operations. Requiring these laws
for every inhabitant of `dag_type x` would be stronger. Final F\* record
syntax may need a signature/helper to express the mutually dependent fields,
but it must preserve this construction-time obligation placement.

#pagebreak()
```fstar
MachineForInput(input_type:Type0, x:input_type) = {
  occurrence_id_type : eqtype;
  dag_type : input_type -> Type0;
  graph_spec_type : Type0;
  state_type : d:dag_type x -> Type0;
  occurrence_descriptor : d:dag_type x -> id:occurrence_id_type -> Type0;

  interpret_static_occurrence :
    d:dag_type x -> id:occurrence_id_type ->
    option (occurrence_descriptor d id);
  interpret_generated_occurrence :
    d:dag_type x -> graph_spec_type -> id:occurrence_id_type ->
    option (occurrence_descriptor d id);
  root_id : occurrence_id_type;

  dag_instance : DagInstance(dag_type x, DagLawsForMachine);

  local_action_type = LocalActionType(dag_instance.raw_dag);
  external_action_type = ExternalActionType(dag_instance.raw_dag);
  generator_action_type = GeneratorActionType(dag_instance.raw_dag);
  local_event_type = LocalEventType(dag_instance.raw_dag);
  external_event_type = ExternalEventType(dag_instance.raw_dag);
  generator_event_type = GeneratorEventType(dag_instance.raw_dag);
  event_type = LocalCompletion(local_event_type)
             | ExternalCompletion(external_event_type)
             | GeneratorCompletion(generator_event_type);

  initial_state : s:state_type(dag_instance.raw_dag) {
    StateRepresents(
      dag_instance.raw_dag,s,EmptyHistory)
  };
  lookup_occurrence :
    state_type dag_instance.raw_dag -> id:occurrence_id_type ->
    OccurrenceLookupResult(dag_instance.raw_dag,id);
  query_local_actions :
    state_type dag_instance.raw_dag -> list local_action_type;
  query_external_actions :
    state_type dag_instance.raw_dag -> list external_action_type;
  query_generator_actions :
    state_type dag_instance.raw_dag -> list generator_action_type;
  accept_event :
    s:represented_state(dag_instance.raw_dag) ->
    e:event_type ->
    #result_correct:ResultCertificate(dag_instance.raw_dag,s,e) ->
    Tot (result:option (state_type dag_instance.raw_dag) {
      AcceptEventResultContract(
        dag_instance.raw_dag,s,e,result)
    });
  terminal_output : state_type dag_instance.raw_dag ->
    option (RootOutputType(dag_instance.raw_dag, root_id));

  // Recovery uses the separate StateJournaler contract below.
}
```

This is a field inventory, not compiler-ready F\* syntax: omitted binders and
projections are schematic, but the signatures show the intended dependencies.
The action/event types are the indexed packages below, not unrelated caller
types or arbitrary per-ID value families. The caller supplies only the runtime
state, event, and erased result certificate; it does not supply a history or
an event-validity proof. `represented_state` is a proof refinement over the
runtime state, witnessed by some ghost history. It does not add a history
field to `state_type` or journal bytes. The exact admission law and candidate
transition condition are fields on this same `accept_event` operation; see
@sec:event-validity.

The field decides from state-visible observations: a matching action must be
present in the appropriate query. The erased result certificate ties the
event to that action and establishes the LEG result equation. The ghost
history witness cannot select the runtime `Some`/`None` branch. The enriched
lookup is part of the state observation, so histories represented by the same
runtime state must agree on every completed typed result. This removes the
false/true external-result conflict; @sec:completion-state-adequacy proves the
needed agreement and append congruence. The transition field still has to
implement its stated preservation law for the chosen machine.
The exact DAG in `dag_instance.raw_dag` remains shared by operations and
laws; its proof fields and the `initial_state` refinement are required to
construct the public record.

#observable-behavior([
  Correctness compares independently supplied behavior with an event-derived
  model; the replay-only contrast is explained in @sec:event-validity.
])

#pagebreak()
#dependency-diagram((
  ("DAG + graph result", "interpret", "occurrence descriptor"),
  ("occurrence descriptor", "selects", "LEG backing + ordered sources"),
  ("valid history", "provides", "typed prerequisite values"),
  ("typed values", "enter", "LEG input assembler"),
  ("occurrence lookup + history", "constrain", "query action and input"),
  ("query action + LEG law", "validate", "completion event"),
  ("valid event", "updates", "state for extended history"),
), caption: "Proposed consistency path")

= Occurrences and the LEG implementations <sec:occurrences>

#status-panel("Decided", title: "Wiring belongs to an occurrence", number: "D2")[
  An occurrence carries its ID and ordered prerequisite sources. The shared
  backing node does not own invocation-specific wiring. A source is the root
  input or another occurrence ID. Repeated IDs are allowed when two slots
  use one result; preserve the slot order and repetition.
]

#definition-card("LEG backers own their source-value input assembler", [
  Each backing object owns the pure function that turns its ordered,
  heterogeneous prerequisite values into the input used by its implementation.
  `InputValues(backer)` is an ordered dependent product (a telescope): a later
  slot's type may depend on earlier slot values. Its representation is
  supplied by the implementation. The assembler sees neither history nor
  state. The occurrence owns the references that select those values.
]) <def:leg-backers>

```fstar
LocalNode = {
  input_slots : InputSlotDescription;
  input_type : Type0;
  output_type : input_type -> Type0;
  assemble_input : InputValues(input_slots) -> option input_type;
  run_local : i:input_type -> output_type i
}

ExternalNode = {
  input_slots : InputSlotDescription;
  input_type : Type0;
  output_type : input_type -> Type0;
  assemble_input : InputValues(input_slots) -> option input_type;
  prepare_external : i:input_type -> Request(i);
  validate_reply : i:input_type -> Request(i) -> Reply(i) -> option output_type(i)
}

GeneratorNode = {
  input_slots : InputSlotDescription;
  input_type : Type0;
  assemble_input : InputValues(input_slots) -> option input_type;
  generate_graph : i:input_type -> graph_spec_type
}
```

```fstar
InputSource(id) = RootInput | InputFromOccurrence(id)

NodeOccurrence(id) = {
  occurrence_id : id;
  backing : LocalNode | ExternalNode | GeneratorNode;
  input_sources : OrderedSources(backing.input_slots, id)
}
```

= Dependent result types stay on the backer <sec:dependent-results>

#definition-card("Completion payload preserves the input index", [
  Local and external result types depend on the input used for that
  occurrence. Do not erase them into an arbitrary per-ID value type. Since an
  event is selected by an occurrence ID rather than statically indexed by a
  particular backer, its payload must existentially package (or otherwise
  reconstruct) the input index together with the result. The history lookup
  preserves that package, so a downstream source receives the actual value
  at its actual producer index.
]) <def:dependent-completion>

```fstar
CompletionValue(H,id) =
  the unique (o,payload) from a completion event for id in H

EventPayloadTypedFor(e,o) =
  SameOccurrenceMeaning(e.ghost_descriptor,o)

EventInput(e) = the input witness i projected from that dependent payload

NodeResultValue(o) =
  match o.backing with
  | LocalNode local -> i:local.input_type & local.output_type(i)
  | ExternalNode external -> i:external.input_type & external.output_type(i)
  | GeneratorNode generator -> i:generator.input_type & graph_spec_type

typed_root_value(o,payload) =
  (#o, project_node_result_value(o,payload))

RootOutputType(d,root_id) =
  #o:occurrence_descriptor(d,root_id) & NodeResultValue(o)

LocalActionType(d) =
  id:occurrence_id_type & #o:occurrence_descriptor(d,id)
  & LocalBacking(o) & i:InputType(o.backing)

ExternalActionType(d) =
  id:occurrence_id_type & #o:occurrence_descriptor(d,id)
  & ExternalBacking(o) & i:InputType(o.backing)

GeneratorActionType(d) =
  id:occurrence_id_type & #o:occurrence_descriptor(d,id)
  & GeneratorBacking(o) & i:InputType(o.backing)

LocalEventType(d) =
  id:occurrence_id_type & #o:occurrence_descriptor(d,id)
  & LocalBacking(o) & i:InputType(o.backing) & OutputType(o.backing,i)

ExternalEventType(d) =
  id:occurrence_id_type & #o:occurrence_descriptor(d,id)
  & ExternalBacking(o) & i:InputType(o.backing)
  & Request(o.backing,i) & Reply(o.backing,i) & OutputType(o.backing,i)

GeneratorEventType(d) =
  id:occurrence_id_type & #o:occurrence_descriptor(d,id)
  & GeneratorBacking(o) & i:InputType(o.backing) & graph_spec_type
```

The event aliases themselves enforce the matching LEG constructor, dependent
payload type, and occurrence-ID index. `EventPayloadTypedFor(e,o)` therefore
only aligns the event's ghost descriptor with the descriptor independently
selected by the history; that equality transports the payload to the selected
dependent result type. `EventValidAt` below additionally requires the packaged
`i` to equal the canonical `NodeInputAt(d,H,o)` and checks the LEG-specific
result equation. Thus the existential package is not a way to choose a
different input: the history fixes it. In `SourceValuesAt`, a local/external completion contributes its
`OutputType(backing,i)` at that same `i`; the typed source refinement proves
that this is the consumer slot's expected type. The current WIP describes
this intended transport, but its event records and `CompletionValue` still
need these dependent signatures made explicit in the eventual F\* file.
In the event type aliases, `#o` is a ghost descriptor witness resolved from
the ID and supplied DAG/history. It is not a serialized backer field:
recovery receives the same caller-supplied code context; the state journaler
round-trips the state without serializing backer closures or the DAG. Action aliases carry a
typed input; `StateRepresents` relates it to the canonical input assembled
from history. These aliases are semantic shapes, not a second family of
machine-supplied arbitrary `Type0` values.

`RootOutputType` is also a dependent package, not a free `root_output_type`
that could erase an input-indexed result. `root_id` may be static or first
declared by a generated graph. In each valid history, its descriptor and
input-indexed result are selected by that history's static or generated
interpretation. `RootResult` projects the dependent result from the unique
completion of that ID, preserving the input witness. Alternative valid
histories may select different root backers and output families; the sigma
package keeps each branch well-typed. The user-facing output may project the
value while the proof-level package retains its index.

The generator codomain is deliberately different: it is the fixed supplied
`graph_spec_type`, not a family indexed by generator input. This still allows
runtime-dependent topology. An external completion can supply a value to a
generator; the generator can compute a graph-spec value from it; and the
generated interpreter can inspect that value to choose the introduced
occurrences. The author must prove the DAG laws for every valid history
branch. What is not supported by this chosen interface is changing the
*type* of the graph-spec value with the input; a dependent graph family would
be a separate design change.

#definition-card("Dependent-output audit: no competing value family", [
  This plan keeps a single source for each result type. A local or external
  backer owns `output_type : input_type -> Type0`; its event stores the input
  witness and a result of exactly `output_type(input)`. The history keeps that
  witness so a later input telescope can use the result at its actual index.
  `RootOutputType` likewise retains the root descriptor and input-indexed
  value. No query, graph-membership, productivity, terminality, or state law
  replaces these types with a second result family.

  Generator output is the intentional exception: every generator returns the
  machine's one fixed `graph_spec_type`. The graph *value* may depend on a
  dependent generator input and choose topology, while the graph-spec *type*
  stays fixed. That matches the chosen boundary; making the graph-spec type
  itself input-dependent would be a separate change.

  The remaining formalization risk is edge typing: F\* must represent the
  equality transports that let a producer's `output_type(producer_input)` fill
  a consumer slot. Those transports belong to the typed occurrence sources;
  they do not erase or compete with the backer's dependent output family.
  Whether a node can assemble its input in a ready history is forced by
  `DagProductivity` and `EventValidAt`, as shown in @sec:source-values.
  Encoding the source-type telescope and its transports in F\* remains open
  work O1 in @sec:formalization.
]) <audit:dependent-output-types>

Concrete lawful shape: an external node `e` validates a `Bool`; a static
generator `g0` consumes that result and returns a constructor of the fixed
sum `GraphSpec = StartFast | StartSafe | FinishFast | FinishSafe`. `StartFast`
declares a root-input local node `p` and a generator gate `gfast` that depends
on `p`; `StartSafe` analogously declares `q` and `gsafe`. `FinishFast`
interprets the fixed root ID `r` as a root-input local backer returning
`Bool`; `FinishSafe` interprets the same ID as a root-input local backer
returning `String`. The designated `root_id` is `r`, which is absent until
the selected branch's gate completes.

For the fast branch, the valid sequence is `e(true)`, `g0(StartFast)`,
`p`, `gfast(FinishFast)`, `r(true)`. At every prefix there is a ready next
event and the root result appears only after `r` completes. The safe branch
uses `q`, `gsafe(FinishSafe)`, and an `r` event carrying a `String`. Each
history satisfies freshness, finite productivity for its declared unfinished
occurrences, and terminal coherence after `r`. Thus external data can select
runtime topology and the dependent output family attached to `r`, while the
machine keeps one fixed `graph_spec_type` and root ID. Per-history
compatibility and unique membership hold; requiring the same descriptor for
`r` across alternative histories would add a global constraint that these
observations do not need.

The `Bool` keeps the witness small. It can be replaced by a dependent output
such as `vector n`: the history package preserves the producer's input index
`n`, and the generator's typed source telescope can consume that exact value
before choosing a constructor of the same fixed `GraphSpec` type. Changing
the generator's result *type* with `n` is still outside the chosen interface.

```fstar
// One fixed type; runtime constructors select both graph and typed backer.
graph_spec_type = StartFast | StartSafe | FinishFast | FinishSafe
external_result : Bool
generator_input : Bool = value assembled from external_result in history
graph_value : graph_spec_type = g0.generate_graph(generator_input)
generated_occurrences = interpret_generated_occurrence(d,graph_value)
```

`OrderedSources(backing.input_slots,id)` has one source per input slot, in
declared order. Repeated IDs are allowed when two slots use the same result.
The typed values are assembled from history in @sec:source-values.

`graph_spec_type` is the caller-supplied type field on the machine, not a
machine-defined graph encoding or a family indexed by generator input. Its interpretation must
still explain which occurrences it contributes; see
@sec:occurrence-graph-law.

= Typed input assembly from history <sec:source-values>

#definition-card("Typed input assembly is derived from productivity", [
  The target law is that declared, ready occurrences have a successful
  canonical input assembly. The equation and derivation below show this follows
  from productivity and valid event construction; it is not another DAG proof
  field. Productivity is stronger: it requires an actual finite valid path to
  completion, not just type compatibility.
]) <def:dag-input-law-definition>

#definition-card("History determines one canonical source-value package", [
  `SourceValuesAt(d,H,o)` is computed slot-by-slot from `o.input_sources` in
  order. At each slot, its expected type is computed using the values already
  collected for earlier slots. `RootInput` contributes `x`; an occurrence
  source looks up the unique completion event for that ID and contributes its
  typed result, including the input index when the result type depends on it.
  The occurrence's typed source telescope transports that value to the
  current slot type. Repeated source IDs repeat the same history value in
  their respective slots. If a required event is absent, the result is
  `None`; valid event construction ensures at most one completion value per
  ID.

  Thus `vs` is not an independently chosen witness: when present it is exactly
  the values already in history, in the occurrence's declared slot order.
  The `source_slot_type_evidence` notation below is intended to come from the
  typed `OrderedSources` refinement. If F\* cannot express the dependent
  source relationship there, the remaining design question is how to package
  that proof-only evidence in the occurrence/DAG types; it is not a runtime
  callback. A value of `InputValues(o.backing.input_slots)` is already a
  dependent telescope with the exact type required at each slot. A mismatched
  source cannot produce that typed package without the required equality
  transport proof. Equality transports are proof-only; any runtime conversion
  would need its own specified behavior. `NodeInputAt` then runs the backer's
  input assembler.
]) <def:source-values-at>

```fstar
SourceValueAt(d,H,o,slot,prefix_values,RootInput) =
  Some(transport(x, source_slot_type_evidence(d,o,slot,prefix_values)))

SourceValueAt(d,H,o,slot,prefix_values,InputFromOccurrence(p)) =
  match completion_value_if_present(H,p) with
  | None -> None
  | Some value ->
      Some(transport(value, source_slot_type_evidence(d,o,slot,prefix_values)))

SourceValuesAt(d,H,o) : option InputValues(o.backing.input_slots) =
  collect_dependent_slots_in_order(
    o.input_sources,
    expected_type = InputSlotType(o.backing, slot, prior_values),
    source_value = SourceValueAt(d,H,o,slot,prior_values,source))

NodeInputAt(d,H,o) =
  match SourceValuesAt(d,H,o) with
  | None -> None
  | Some values -> o.backing.assemble_input(values)

DagInputAssemblyLaw(d) =
  forall H:History(d),id,o.
    DeclaredOccurrence(d,H,id,o)
    /\ PrerequisitesDone(H,o)
    ==>
    exists input. NodeInputAt(d,H,o) = Some input
```

`DagInputAssemblyLaw` follows from productivity as a theorem. For an
uncommitted occurrence, productivity gives a valid suffix completing it;
that completion's `EventValidAt` proof supplies `NodeInputAt = Some input`.
Because the occurrence descriptor and its already-completed prerequisite
values cannot change in a valid extension, the same assembly succeeds at the
starting history. For an already-completed occurrence, apply the same argument
to its completion event's prefix and use the same stability. The proof needs
frame lemmas for append-only history, unique completions, and fresh graph
membership, but these are derivation steps, not caller-supplied law fields.
Alternative valid branches may still select different descriptors or
dependent output families; the argument is pointwise within each history.

For example, an external backer may have `output_type(n) = vector n`, with
`n` supplied by the root input. A downstream node can declare two ordered
slots, first `n` from `RootInput`, then `vector n` from that external
occurrence. The history package retains the external completion's input
index and vector; its typed source value can fill the second slot only at the
matching `n`. If the consumer instead requires `vector 3` while the root
value may be another length, the per-DAG source typing proof cannot be built
unless the relevant histories establish `n = 3`. This is a type-level
compatibility obligation, not a competing output type or a run-time cast.
<def:source-compatibility>

#observable-behavior([
  Once non-root prerequisites have completed, their actual ordered values
  can be transported to the node's input types and its assembler accepts
  them. A `(vector n -> ...) -> (vector 3 -> ...)` edge is invalid if a valid
  prefix cannot establish `n = 3` or another valid transport.
])

#definition-card("A DAG instance packages one DAG with its laws", [
  Pair each used raw DAG with its proofs. This lets the machine keep
  `dag_type` abstract and does not require unused inhabitants to satisfy the
  laws. `DagInstance` is a field of the one public machine record, not another
  machine or context.
]) <def:dag-instance>

```fstar
DagLawsForMachine(d) =
  {
    #terminal_coherence : HistoryTerminalCoherence(d,root_id);
    #productivity : DagProductivity(d)
  }

DagInstance(dag_value_type, DagLawsForMachine) = {
  raw_dag : dag_value_type;
  #laws : DagLawsForMachine(raw_dag)
}
```

The law family closes over the graph interpreters, node backers, and selected
root ID from the enclosing machine record. Every operation and proof uses the
same `raw_dag` projection.

= Occurrence lookup/history consistency and graph interpretation <sec:occurrence-graph-law>

Generated membership must be defined independently of the machine's
`lookup_occurrence`; otherwise that function's answer would define its own
correctness. The definition is part of the exact `DagInstance` package from
@sec:source-values.

#definition-card("Independent occurrence interpreters", [
  The signatures occur once in the `MachineForInput` record at
  #link(<def:machine-operations>)[the machine operation fields]. The static DAG and generated graph payload have
  different supplied types, so each has a typed interpreter returning the
  same descriptor type. These independent definitions give graph meaning;
  runtime `lookup_occurrence` remains the state-dependent accessor. The
  interpreters may be ghost fields when proof projections suffice.
]) <def:occurrence-interpreters>

#definition-card("History declarations are the union of those meanings", [
  `StaticInterpretation(d,id,o)` abbreviates that the static interpreter
  returns `Some o`. `GraphInterpretation(d,g,id,o)` abbreviates that the
  generated-graph interpreter returns `Some o`. `DeclaredOccurrence(d,H,id,o)`
  holds when the static DAG contributes `o` or a generator completion already
  in `H` carries a graph value that contributes `o`. Declarations accumulate
  with history: an appended event can add descriptors but cannot remove an
  earlier declaration.

  `DeclaredOccurrence` is intentionally just this definition; it is not an
  extra field or a correctness theorem. Its content is non-circular because
  both interpreters are defined independently of `lookup_occurrence`, queries,
  and replayed state.
]) <def:declared-occurrence>

```fstar
StaticInterpretation(d,id,o) =
  interpret_static_occurrence(d,id) = Some o

GraphInterpretation(d,g,id,o) =
  interpret_generated_occurrence(d,g,id) = Some o

DeclaredOccurrence(d,H,id,o) =
  StaticInterpretation(d,id,o)
  \/ exists e,g.
       e in H
       /\ GeneratorGraphPayload(e) = Some g
       /\ GraphInterpretation(d,g,id,o)
```
<def:declared-occurrence-equation>

#definition-card("Occurrence state and lookup agreement", [
  `SameOccurrenceMeaning` is not another machine field. Define it as
  propositional equality of canonical occurrence descriptors (`r == o`):
  this is a ghost proposition, never a runtime closure comparison. It says the
  ID, LEG kind, ordered sources, and selected backing implementation all
  denote the same occurrence. A lookup entry pairs this descriptor with
  `None` for an incomplete occurrence or `Some value` for its completed
  `NodeResultValue`. Descriptor equality transports the dependent value type
  before comparing results. The history-side value is projected from the
  unique completion event; it is not read from the machine lookup. This law
  therefore relates independent sources, rather than comparing a value with
  itself or comparing functions at runtime.
]) <def:same-occurrence>

```fstar
OccurrenceLookupResult(d,id) =
  option (o:occurrence_descriptor(d,id) & option (NodeResultValue(o)))

HistoryCompletedResult(d,H,id,o) =
  if Completed(H,id)
  then Some(project_node_result_value(CompletionValue(H,id)))
  else None

HistoryOccurrenceStateAt(d,H,id) =
  match unique o satisfying DeclaredOccurrence(d,H,id,o) with
  | None -> None
  | Some o -> Some (#o, HistoryCompletedResult(d,H,id,o))

SameOccurrenceState(actual,expected) =
  SameOccurrenceMeaning(actual.occurrence,expected.occurrence)
  /\ transport_result(
       actual.occurrence == expected.occurrence,
       actual.completed_result)
       == expected.completed_result

```
<law:occurrence-lookup-history>

#definition-card("Occurrence interface: fields versus laws", [
  The independent inputs are the static and generated interpreters above.
  `lookup_occurrence(state,id)` is one existing machine field, now returning
  both occurrence meaning and completion status/value. The remaining names in
  this section are definitions or proof obligations, not additional callbacks:

  - `DeclaredOccurrence` folds the two interpreters over static DAG data and
    generator payloads in history.
  - `SameOccurrenceMeaning` is ghost equality of canonical descriptors.
  - `EventValidAt` includes generated-ID freshness. Its consequence for
    per-history uniqueness is proved once in
    #link(<def:exclusive-membership>)[D3].
  - `StateRepresents` contains the sole lookup consistency law: its occurrence
    map compares each runtime lookup, including pending/completed status and
    the dependent result value, with the independently interpreted history
    map. The sequence-indexed pointwise view follows using
    `HistoryObservationFaithful`.

  The same ID may still have a different descriptor in alternative valid
  histories when their graph values differ. No global creator accessor or
  cross-history descriptor equality is required.
]) <def:occurrence-interface-inventory>

#status-panel("Decided", title: "Lookup exposes typed completion state")[
  Keep one `lookup_occurrence` field. Its outer `None` means the ID has not
  been declared; `Some (descriptor, None)` means it is declared but pending;
  `Some (descriptor, Some value)` means it is complete. `value` has exactly
  `NodeResultValue(descriptor)`, including the producer input index and its
  dependent output (or the generator's graph spec). `StateRepresents` requires
  this result to equal the value projected from the corresponding history
  event. This is one state observation and one consistency law, not a second
  result accessor or a runtime copy of the entire history.
]

#status-panel("Decided", title: "Freshness gives unique membership per history", number: "D3")[
  `FreshGeneratedIds` requires each generator result to contribute only IDs
  absent from the preceding history. It excludes both repeated generated
  membership and collisions with static declarations. Since declarations
  accumulate and each interpreter is functional, induction makes the
  descriptor for an ID unique within one valid history. This is a consequence
  used by the history map, not another field or law.
] <def:exclusive-membership>

Simplification: do not add separate “no phantom ID” theorems. “No
interpreter contributes this ID implies `DeclaredOccurrence` is false” is
just unfolding its definition, and “a valid event cannot complete an
undeclared ID” is just unfolding `EventValidAt`'s declared-occurrence
premise. Neither is an extra machine guarantee. The non-definitional
guarantee is `StateRepresents`: actual machine lookup, including completed
typed results, and queries agree with the independently interpreted history
meaning.

#observable-behavior([
  A generated ID becomes visible only when a graph value in history
  independently interprets as contributing it. Alternative valid histories
  may select different implementations and typed outputs for the same ID.
  Within one history, freshness gives exclusive membership by
  #link(<def:exclusive-membership>)[D3].
])

No equality is required between descriptors from different history branches.

= History predicates and `StateRepresents` <sec:state-represents>

History is an inductive sequence of LEG completion events. Each step carries
a proof that its event is valid at the preceding prefix. Thus every inhabitant
is a valid history; raw journal records still need validation before they
become one. The history-side event predicate is defined in
@sec:event-validity. `StateRepresents` is the independent observation
invariant: it does not define a state by replaying the same `accept_event`.

#definition-card("History contains only valid extensions", [
  `History` and `EventValidAt` are mutually specified: the event predicate
  checks a candidate against a prior history, and each nonempty history
  constructor stores that proof. No constructor accepts an unchecked event.
  This is a proof object over event data; it is not the serializable machine
  state.
]) <def:valid-history>

```fstar
type history(d) =
  | EmptyHistory : history(d)
  | LocalStep :
      previous:history(d) ->
      event:LocalEventType(d) ->
      #validity:EventValidAt(d,previous,LocalCompletion(event)) ->
      history(d)
  | ExternalStep :
      previous:history(d) ->
      event:ExternalEventType(d) ->
      #validity:EventValidAt(d,previous,ExternalCompletion(event)) ->
      history(d)
  | GeneratorStep :
      previous:history(d) ->
      event:GeneratorEventType(d) ->
      #validity:EventValidAt(d,previous,GeneratorCompletion(event)) ->
      history(d)

events(EmptyHistory) = []
events(LocalStep(previous,event,_)) = events(previous) ++ [LocalCompletion(event)]
events(ExternalStep(previous,event,_)) = events(previous) ++ [ExternalCompletion(event)]
events(GeneratorStep(previous,event,_)) = events(previous) ++ [GeneratorCompletion(event)]
```

#definition-card("Completion and readiness come from prior events", [
  `Completed` means the history has a completion for an ID;
  `Uncommitted` means it has none. `PrerequisitesDone` checks every
  occurrence-valued source, while `RootInput` is available from the start.
  `Ready_k` combines a declared occurrence of kind `k`, completed
  prerequisites, and no prior result. The history model also computes the
  unique executable input for a ready occurrence from those exact event
  values using `NodeInputAt` from @sec:source-values.
]) <def:readiness>

```fstar
Completed(H,id) = some event in H has occurrence_id = id
Uncommitted(H,id) = not Completed(H,id)

PrerequisitesDone(H,o) =
  every InputFromOccurrence(p) in o.input_sources has Completed(H,p)
  // RootInput is available by definition.

Ready_k(d,H,id) =
  exists o.
    DeclaredOccurrence(d,H,id,o)
    /\ kind(o) = k
    /\ Uncommitted(H,id)
    /\ PrerequisitesDone(H,o)

HistoryAction_k(d,H,id,input) =
  exists o.
    DeclaredOccurrence(d,H,id,o)
    /\ kind(o) = k
    /\ Uncommitted(H,id)
    /\ NodeInputAt(d,H,o) = Some input

HasAction_k(s,id) =
  exists action. action in query_k(s) /\ action.id = id
```

`NodeInputAt = Some input` already implies `PrerequisitesDone`: the ordered
source collector returns `None` if any occurrence-valued source is absent.
That is why the action relation does not repeat the prerequisite test that
appears in `Ready_k`.

The exact machine-side observation tuple and its history-derived counterpart
are defined in @sec:observable-surface. There, the action lists are compared
as bags of executable action observations: list order is ignored, while
multiplicity is retained.

#definition-card("Observable state invariant `StateRepresents`", [
  The invariant equates the machine's actual quiescent observations with the
  independently computed model of the event history, and aligns each query
  action's erased occurrence descriptor with the history-selected descriptor.
  Its sources are independent: the left calls machine fields; the right uses
  the fixed DAG interpretation and history events only. The descriptor clause
  is proof-level consistency needed to type result certificates, not another
  runtime observation or closure comparison. This is the master
  state/history consistency condition, not equality to replay.
]) <def:state-represents>

```fstar
QueryDescriptorAgreement(d,s,H) =
  forall k,a.
    a in query_k(s)
    ==>
      exists o.
        DeclaredOccurrence(d,H,a.occurrence_id,o)
        /\ kind(o) = k
        /\ SameOccurrenceMeaning(a.ghost_descriptor,o)

StateRepresents(d,s,H:History(d)) =
  ObservationAgreement(
    QuiescentObservation(s),
    HistoryQuiescentModel(d,HistoryObservation(H)))
  /\ QueryDescriptorAgreement(d,s,H)
```

The occurrence-map component of this agreement is the lookup consistency
contract: it compares the actual `lookup_occurrence` result, including pending
status and each completed dependent value, with the map independently derived
from history. `HistoryObservationFaithful` connects the event-bag model here
to the sequence-indexed definitions above. For example, a history with a
valid external result `false` is inconsistent with a lookup that reports
`true`, even before any consumer is ready.

Because `History(d)` is inductive and each step stores its
`EventValidAt` proof, `H:History(d)` already carries `ValidHistory`; repeating
it as a conjunct here is redundant. If the eventual representation instead
uses a raw event list, restore the `ValidHistory(d,H)` conjunct. This choice
does not make observation agreement redundant: history validity constrains
events, while agreement constrains the independent machine state reads.

Unfolding the agreement gives occurrence lookup equal to the history-derived
map, query bags equal to their ready-action models, and terminal output equal
to the root result in history. Since the history side has one action
observation per ready occurrence, bag equality also rules out duplicate
actions. `QueryDescriptorAgreement` separately aligns each action's erased
descriptor: executable action observations contain only `(id,input)`, so bag
equality alone cannot constrain the ghost backer used to type a result
certificate. These are projections or components of the master relation, not
separate machine callbacks.

#observable-behavior([
  Every quiescent state exposes exactly the occurrences, executable actions,
  and optional root result determined by the valid completed history. A
  ready node cannot disappear from a query, an unready node cannot appear,
  and an action cannot carry an input assembled from different results.
])

= Event validity and one-step preservation <sec:event-validity>

#definition-card("Event validity is history-indexed causality plus result correctness", [
  `EventValidAt(d,H,e)` is defined from the preceding history and the fixed
  DAG/program only. The occurrence must be declared there and uncommitted.
  `NodeInputAt = Some(EventInput(e))` says both that all source values are
  present and that the event carries exactly the input assembled from them.
  The payload must satisfy the selected LEG result equation. For a generator
  event, its generated graph value must introduce only IDs absent from the
  preceding declared graph; this makes graph membership exclusive within each
  valid history.

  Event validity does not call a machine query; the query-visibility theorem
  below derives that observable from `StateRepresents`.
]) <def:event-valid-at>

No separate issuance token is needed if independent events preserve the
action's readiness. A delayed completion remains acceptable after independent
updates while its action remains queryable; after its own completion,
`Uncommitted` rejects another completion.

#definition-card("Each LEG event must satisfy its backing result equation", [
  A local event stores exactly the `run_local` output for the action input.
  An external event stores a request prepared from that input and a result
  accepted by `validate_reply` for that request/reply. A generator event stores
  exactly the graph specification returned by its generator function.
  These claims concern the supplied functions' results; external effects are
  not observable to this law.
]) <def:node-result-correct>

```fstar
EventValidAt(d,H:History(d),e) =
  exists o.
    DeclaredOccurrence(d,H,e.id,o)
    /\ EventPayloadTypedFor(e,o)
    /\ Uncommitted(H,e.id)
    /\ NodeInputAt(d,H,o) = Some(EventInput(e))
    /\ NodeResultCorrect(o,EventInput(e),e)
    /\ (match o.backing with
        | GeneratorNode generator ->
            FreshGeneratedIds(
              d,H,generator.generate_graph(EventInput(e)))
        | _ -> True)

FreshGeneratedIds(d,H:History(d),g) =
  forall id,o.
    GraphInterpretation(d,g,id,o)
    ==> no old_meaning.
          DeclaredOccurrence(d,H,id,old_meaning)

NodeResultCorrect(o,i,e) =
  match o.backing with
  | LocalNode local -> LocalResultPayload(e) = local.run_local(i)
  | ExternalNode external ->
      e.request = external.prepare_external(i)
      /\ external.validate_reply(i,e.request,e.reply) = Some ExternalResultPayload(e)
  | GeneratorNode generator ->
      GeneratorGraphPayload(e) = Some(generator.generate_graph(i))

extend_history(H,e:{e:event_type(d) | EventValidAt(d,H,e)}) =
  append e, using the validity proof carried by its refinement

ValidExtension(d,H:History(d),events) =
  forall i. 0 <= i < length(events) ==>
    EventValidAt(d,H ++ take(events,i),events[i])
```

```fstar
ActionOffered(d,s,e) =
  exists a.
    a in query_kind_of(e)(s)
    /\ a.occurrence_id = e.occurrence_id

ResultCertificate(d,s,e) =
  forall a.
    a in query_kind_of(e)(s)
    /\ a.occurrence_id = e.occurrence_id
    ==>
      SameOccurrenceMeaning(e.ghost_descriptor,a.ghost_descriptor)
      /\ e.input == a.input
      /\ NodeResultCorrect(a.ghost_descriptor,a.input,e)

AdmissibleNow(d,s,e) =
  ActionOffered(d,s,e)
```

#theorem-card("An offered generator result is fresh against represented state", [
  For every `h` represented by `s`, a matching queried generator action has a
  declared, uncommitted occurrence and its canonical input is assembled from
  completed prerequisites. `ResultCertificate` fixes the event to that
  occurrence, input, and generated graph. `DagProductivity` supplies a valid
  suffix completing the occurrence. Its descriptor cannot be rebound along
  the suffix: declarations are append-only and every later graph result is
  fresh against declarations already present. Its completed prerequisites
  cannot change, so the suffix completion uses the same input and produces
  the same graph. Freshness at the completion prefix therefore implies
  freshness against `h`; lookup agreement then gives `None` for every ID in
  that graph in `lookup_occurrence(s, id)`.

  Thus the state-level freshness premise can be removed from event admission
  without weakening the observable guarantee. This implication depends on the
  required `DagProductivity` law and the history-observation/frame lemmas still
  to be proved; it adds no machine field.
]) <thm:offered-generator-freshness>

```fstar
forall s:state_type(d), h:History(d), ge:GeneratorEventType(d).
  DagProductivity(d)
  /\ StateRepresents(d,s,h)
  /\ ActionOffered(d,s,GeneratorCompletion(ge))
  /\ ResultCertificate(d,s,GeneratorCompletion(ge))
  ==>
  forall g,id,o.
    GeneratorGraphPayload(GeneratorCompletion(ge)) = Some g
    /\ GraphInterpretation(d,g,id,o)
    ==>
    lookup_occurrence(s,id) = None
```

#definition-card("The caller certifies the result against a queried action", [
  `ResultCertificate` is an erased proof argument to `accept_event`, not a
  history argument and not a runtime equality check. For every matching
  action currently returned by the query for this event kind, it proves that
  the event carries the same occurrence meaning and assembled input, and that
  its payload satisfies the selected LEG result equation. If no matching
  action is offered, the implication is vacuous; exact admission below then
  rejects the event. The caller proves how the result was obtained, while the
  machine checks current causal availability.
]) <def:result-certificate>

#status-panel("Decided", title: "State-checked event admission", number: "D4")[
  The `accept_event` field itself takes a represented state, a dependent
  event, and an erased node-specific result certificate. It takes no history
  and no `EventValidAt` proof. Its nonredundant admission condition is
  completeness: if a matching action is offered, the call must return `Some`.
  Generator freshness follows from the derived theorem at
  #link(<thm:offered-generator-freshness>)[the offered-generator freshness theorem].
  The success condition requires the returned state to represent the one-event
  extension of every history represented by the input state. Completion-aware
  occurrence lookup makes those extensions observationally compatible; the
  derivation is in @sec:completion-state-adequacy. Conditional on this success
  clause, `Some ==> AdmissibleNow` follows from the existing history/query/
  lookup laws, so it is not repeated as a field clause.
]

```fstar
represented_state(d) =
  s:state_type(d) {
    exists #h:History(d). StateRepresents(d,s,h)
  }

HistoryExtendsWith(d,h:History(d),e:event_type(d),h':History(d)) =
  events(h') = events(h) ++ [e]

AcceptEventResultContract(d,s,e,result) =
  (AdmissibleNow(d,s,e) ==> is_Some(result))
  /\ (forall s'. result = Some s' ==>
        forall h:History(d).
          StateRepresents(d,s,h)
          ==>
            exists h':History(d).
              HistoryExtendsWith(d,h,e,h')
              /\ StateRepresents(d,s',h'))
```

This `AcceptEventResultContract` is the return refinement already attached to
the `accept_event` record field in
#link(<def:machine-inventory>)[the machine type]; the field signature is not
repeated here.

The second conjunct is the universal preservation law: every valid history
represented by the input state must have a valid one-event extension
represented by the one returned state. The completion-aware lookup law in
`StateRepresents` ensures that histories represented by the same state agree
on the values needed by future inputs. The proof that this closes the prior
realizability counterexample is in
@sec:completion-state-adequacy.

For a `Some` result, choose any represented history `h`. The success contract
supplies a valid history
whose event sequence is exactly `events(h) ++ [e]`; inversion of its final
inductive constructor, together with event-sequence extensionality (the
validity predicate does not depend on history proof terms), gives
    `EventValidAt(d,h,e)`. The query-visibility theorem then gives
`ActionOffered`. Hence exact acceptance follows without writing both
directions into the machine field.
This extensionality lemma is a proof obligation for the final F\*
development, not an additional machine field.

The output type is `option state_type`, not
`option represented_state`: a successful-extension proof supplies a
represented-history witness for the output. This removes a redundant output
refinement while preserving the input refinement, which prevents the
history-based postcondition from becoming vacuous on an unrepresented state.

The result certificate is intentionally caller-provided: local and generator
payloads use propositional equality with the node computation; external
payloads prove the supplied validator accepts the request/reply. The machine
does not attempt runtime equality on arbitrary dependent values or closures.
The caller does not prove causality or supply history. A wrong result for an
offered action has no certificate; a stale or unrelated event has no offered
action and is rejected. If one state represents several histories, the
success postcondition still applies to every one. The enriched lookup makes
their completed occurrence maps and resulting next-step observations agree.

Here `H ++ take(events,i)` is shorthand for the inductively constructed
prefix history, using validity proofs for earlier events; it is not raw-list
append to a proof-carrying `History` value.

#theorem-card("Every valid event is query-visible at a represented prefix", [
  This is derived from history-only `EventValidAt`,
  `HistoryObservationFaithful`, and the query-bag projection of
  `StateRepresents`. It establishes causal emission without making history
  validity depend on a machine query.
])

```fstar
HistoryObservationFaithful(d,H)
  /\ StateRepresents(d,s,H)
  /\ EventValidAt(d,H,e)
  ==>
  exists action.
    action in query_kind_of(e)(s)
    /\ action.id = e.id
    /\ action.input = EventInput(e)
```

#status-panel("Derived", title: "Replay equality was insufficient", number: "T2")[
  Existing `state_at` / `accept_event_consistency` constrains a state to the
  fold of the same `accept_event` function. The step follows from fold
  algebra; it does not require query actions to change after completion,
  dependents to appear, or occurrence lookup answers to track generator results.
  The master `StateRepresents` invariant instead compares independent machine
  observations with the history-derived model. Initial correctness is the
  `initial_state` field refinement; one-step preservation is the
  `accept_event` field postcondition. The former realizability obstruction is
  resolved by the completed-result lookup agreement in
  @sec:completion-state-adequacy.
]

= The seven annotated points and their observables <sec:annotation-audit>

#table(
  columns: (0.38fr, 1.75fr, 2.15fr), inset: 5pt,
  stroke: 0.5pt + rgb("C7CED4"),
  [*Item*], [*Answer*], [*Observable behavior protected*],
  [1], [`assemble_input` is on each selected LEG backing object; source IDs remain on the occurrence.], [Ordered prerequisite values form the exact input consumed by that node.],
  [2], [`DagProductivity` plus valid-event input checks derive input assembly; freshness gives unique occurrence meaning within each history.], [Every ready occurrence has correctly typed history values accepted by its assembler, including generated work.],
  [3], [No action-local proof field is needed; the quiescent/history agreement includes the canonical input in each action observation.], [Every emitted action uses values from this history.],
  [4], [History-only event validity, the master observation invariant, initial correctness, and one-step preservation replace replay-only equality.], [Reachable machine observations agree with the independent event model.],
  [5], [`EventValidAt` includes generator-ID freshness; exclusive membership and first appearance then follow by induction.], [No repeated graph owner or static/generated collision within a valid history; no separate creator-ID accessor.],
  [6], [`StateRepresents` is independent agreement between machine-only quiescent observations and the event-derived model.], [Occurrence lookup, ready action bags and terminal output agree with completed history.],
  [7], [Future-action theorem follows conditionally from initial law, realizable event-preservation, and the action-bag projection.], [After prerequisites complete, an uncompleted compatible consumer is queryable.],
)

#pagebreak()
= Future-action theorem <sec:future-actions>

#status-panel("Derived", title: "Selection 7: conditional on a realizable transition law", number: "T3")[
  Given a realizable one-step preservation law, this is a derived theorem,
  not a tautology. `StateRepresents` in
  @sec:state-represents compares machine observations against a model computed
  independently from event history and the fixed DAG. It does not define the
  next state to be “whatever `accept_event` returns.”

  The induction would use the postcondition built into the `accept_event` field.
  At the base, the starting state is represented. For an empty-history start,
  use the `initial_state` field refinement. At each step, the event is valid
  at that prefix and the field's result refinement proves the returned state
  represents the extended prefix. At the end,
  `DagInputAssemblyLaw` turns readiness into a sequence-model action, and
  `HistoryObservationFaithful` transfers it to the bag model compared by
  `StateRepresents`. Without the field postcondition, the state could ignore
  an accepted prerequisite result and fail to expose its consumer.
]

```fstar
s_0 = s_start  // StateRepresents(d,s_start,H)
s_(i+1) = accept_event(
  (s_i : represented_state(d)),
  es[i],
  #result_certificate_from_event_validity(
    d, s_i, H ++ take(es,i), es[i]))

StateRepresents(d,s_start,H)
  /\ ValidExtension(d,H,es)
  /\ DagInputAssemblyLaw(d)
  /\ HistoryObservationFaithful(d,H ++ es)
  /\ Ready_k(d,H ++ es,consumer_id)
  ==>
  StateRepresents(d,s_length(es),H ++ es)
  /\ HasAction_k(s_length(es),consumer_id)
```

The target proof is induction over `i`: the base is
`StateRepresents(d,s_0,H)`; for the step, use prefix validity from
`ValidExtension` to construct the erased result certificate, then use
acceptance completeness and the `accept_event` preservation clause. The
history appears only in this theorem proof, not in the caller-facing
`accept_event` arguments. The completion-aware lookup resolves the former O5
obstruction; implementation still owes the stated preservation proof.
After the last step, use `DagInputAssemblyLaw` to obtain the consumer's
canonical input, then use `HistoryObservationFaithful` and the query-bag
component of `StateRepresents` to obtain its action. For a run starting at
`[]`, initialize with the `initial_state` field refinement.

For prerequisites `A` and `B`, their completion order is immaterial for the
final action set if each event is valid at its own prefix and neither
completes the consumer. Once both are in history, query completeness exposes
the consumer. This conclusion depends on the consumer being declared,
input-compatible, and not already completed.

= Forward references <sec:forward-references>

#status-panel("Decided", title: "Forward references enable additive graph grafting", number: "D5")[
  A static node may name a prerequisite ID that is not declared until a later
  generator result. Its occurrence meaning is fixed in the static DAG from
  the start, but it is not ready while that prerequisite lacks a completion
  event. A valid generator event adds its interpreted descriptors to the
  effective graph; after the new prerequisite completes, the existing static
  dependent appears in its query with values assembled from that result.

  For example, static `c` may depend on `p`, while generator `g` later
  contributes `p` with only a root-input source. The histories `[]`, `[g]`,
  and `[g,p]` respectively show `c` waiting for `p`, `p` becoming queryable,
  and `c` becoming queryable after `p` completes. This is an intended way for
  generators to graft nodes between pre-existing static work. No
  prerequisite-closure law should forbid it.

  The supported operation is additive: declarations accumulate, so a
  generator can add branches or chains that connect to already declared
  nodes through forward references. Freshness prevents rebinding within one
  valid history; see #link(<def:exclusive-membership>)[D3]. Across alternative histories,
  an ID may have a different interpretation, as defined in
  @sec:occurrence-graph-law. These declarations remain subject to the input
  law in @sec:source-values and the productivity and terminality laws in
  @sec:formalization. No separate
  acyclicity theorem is required; runtime progress and termination are
  addressed by the non-goal decision below.
]

#status-panel("Decided", title: "Non-goals: runner, journaler, and program identity", number: "D6")[
  Core consistency does not establish query timing, dispatch attempts,
  duplicate launches, retries, scheduler fairness, eventual execution,
  service availability, or exactly-once external effects. It also does not
  establish code identity across builds, a canonical byte format across
  journaler implementations, durability, or I/O guarantees. The selected
  journaler must satisfy the state round-trip law in
  #link(<def:state-journaler>)[its definition]; format and storage behavior belong to the adapter.
  The caller supplies the DAG/program context, so F\* closures are not
  serialized as state.
] <decision:non-goals>

= Terminal output, recovery, and open formalization work <sec:formalization>

#definition-card("Every declared occurrence has a finite valid completion path", [
  `DagProductivity` is the required per-DAG reachability contract. Starting
  from any valid history, every already-declared, not-yet-completed
  occurrence must have some finite extension made entirely of valid events
  that eventually completes that occurrence. The extension can include
  prerequisites and generator results; all external results in it must pass
  their validators.

This is existential graph/history productivity, not a runtime liveness
guarantee. It says a legal completion path exists and rejects declared work
blocked under every valid continuation. Runtime execution, external service
  behavior, and termination are excluded by #link(<decision:non-goals>)[D6].
]) <def:dag-productivity>

```fstar
DagProductivity(d) =
  forall H:History(d),id,o.
    DeclaredOccurrence(d,H,id,o)
    /\ Uncommitted(H,id)
    ==>
    exists suffix.
      ValidExtension(d,H,suffix)
      /\ Completed(H ++ suffix,id)
```

An empty suffix cannot satisfy the conclusion: `Uncommitted(H,id)` contradicts
`Completed(H ++ [],id)`. So a separate positive-length conjunct would be
redundant. `DagProductivity` is one of the proof fields required in the exact
`DagInstance` package in #link(<def:dag-instance>)[the package definition].
  Together with the initial-state refinement and a realizable postcondition on
  `accept_event`, induction lifts the suffix to a sequence
whose next event is visible in the corresponding query at each represented
prefix. This makes the law a real finite-path existence guarantee for the
abstract machine. It still does not execute that path. For external nodes it
also requires that some finite sequence of replies accepted by the supplied
validators can complete each declared occurrence.

#definition-card("Terminality is determined on the history side", [
  `HistoryTerminalCoherence(d,root_id)` requires, for every `H:History(d)`, that there are
  no ready local, external, or generator actions exactly when the designated
  root result is present. It is independent of machine functions. The
  condition is part of the law package for a used DAG. By itself it does not
  say whether unrelated declared work has completed; together with
  `DagProductivity` and query/history agreement, it implies that a terminal
  root state cannot leave a declared occurrence unfinished.
]) <def:history-terminal-coherence>

```fstar
NoHistoryActions(d,H) =
  no k,id,input. HistoryAction_k(d,H,id,input)

RootResult(d,root_id,H) =
  match CompletionValue(H,root_id) with
  | None -> None
  | Some(o,payload) -> Some(typed_root_value(o,payload))

HistoryTerminalCoherence(d,root_id) =
  forall H:History(d).
    NoHistoryActions(d,H) <==> RootResult(d,root_id,H) != None
```

Given `StateRepresents`, `HistoryObservationFaithful`, and
`HistoryTerminalCoherence`, machine terminality is a projection: the action
bags give `NoActions(s) <==> NoHistoryActions(d,H)`, and the terminal
component gives `terminal_output(s) = RootResult(d,root_id,H)`. There is no
separate machine terminality field. The independent history law is necessary:
observation agreement relates each machine observation to its history
counterpart but does not itself relate readiness to root-result presence.

This is a safety statement about quiescent observations, not eventual
progress. History-terminal coherence excludes deadlock with no root result.
With productivity, a root result cannot coexist with unfinished declared
work: otherwise productivity gives a nonempty valid continuation, whose
first event must be query-visible, contradicting terminal coherence. Runtime
progress and termination remain outside the core contract in
#link(<decision:non-goals>)[D6].

This law also deliberately excludes a valid history in which the root has
completed while unrelated ready work remains. That is the observable meaning
of “the root is terminal” chosen here; it is stronger than merely saying the
root result can be read when available.

#definition-card("State journaler round-trip", [
  A journaler is parameterized by the already supplied DAG. It encodes and
  decodes machine state under that DAG; it never encodes or reconstructs the
  DAG or its F\* closures. The required law is a left inverse: decoding a
  value produced by this encoder returns the exact state. No reverse law for
  arbitrary byte strings is needed for this recovery guarantee.
]) <def:state-journaler>

```fstar
StateJournaler(d) = {
  journal_bytes_type : Type0;
  encode_state : state_type(d) -> journal_bytes_type;
  decode_state : journal_bytes_type -> option (state_type(d));
  round_trip : forall s:state_type(d).
    decode_state(encode_state(s)) == Some(s)
}

recover(d,journal) = StateJournaler(d).decode_state(journal)
```

If `s` represents history `H`, the round-trip equation restores exactly `s`,
so the proof can reuse `StateRepresents(d,s,H)`. A recovery theorem needs the
premise that journal bytes were produced by this journaler from a state
represented at write time. The history itself need not be encoded; it remains
an erased witness in the proof of that provenance. Bare bytes without the
producer premise are outside the guarantee. The state-checked `accept_event`
API does not require the caller to pass the witness as an argument.

The event-admission interface is selected, and completion-aware lookup
removes the former realizability obstruction for its strong preservation
clause; the actual machine field still needs an implementation and proof.
Remaining work includes F\* encoding and proofs. There is no strict
topological declaration order: event validity depends on history-side
graph/readiness semantics, while `StateRepresents` compares those semantics
with machine functions. Define these predicates together, then prove
initialization and one-step preservation. History terminality and the
provenance-scoped state round-trip recovery theorem remain separate laws.

#dependency-diagram((
  ("DAG + graph result", "interpret", "history occurrence map"),
  ("history events", "determine", "completed values + ready action bags"),
  ("history model", "defines", "EventValidAt + expected observations"),
  ("machine read fields", "compared by", "QuiescentObservation"),
  ("initial + accept_event", "prove", "StateRepresents by induction"),
  ("history terminal coherence", "projects through", "derived machine terminality"),
  ("StateJournaler encode/decode", "satisfies", "state round-trip"),
), caption: "Consistency dependencies, not a strict declaration order")

#status-panel("Open", title: "Encode dependent source and result types", number: "O1")[
  Represent ordered source telescopes, source-value collection, and
  the derived `DagInputAssemblyLaw` theorem in F\*. Preserve each producer's
  input-index witness through completion values and consumer slots. Do not add
  a separate DAG proof field for assembly. The intended relation is in
  @sec:source-values and #link(<audit:dependent-output-types>)[the dependent-output audit].
] <open:dependent-encoding>

#status-panel("Open", title: "Encode graph and history observations", number: "O2")[
  Implement the independent static/generated occurrence interpreters and
  encode occurrence maps, action bags, and `HistoryQuiescentModel`. Prove
  `HistoryObservationFaithful` for the event data retained by the history;
  @sec:observable-surface gives the semantic target.
] <open:observation-encoding>

#status-panel("Open", title: "Prove the core consistency fields", number: "O3")[
  For the actual machine and selected DAG, provide the two DAG laws
  (`HistoryTerminalCoherence` and `DagProductivity`), discharge the
  `initial_state` field's `StateRepresents(..., EmptyHistory)` refinement,
  and implement the refined `accept_event` field against the full
  lookup/query/terminal observation relation. Prove the derived input-assembly
  and future-action lemmas; machine terminality follows from the history law
  and observation agreement.
] <open:core-proofs>

#status-panel("Open", title: "Prove represented-state recovery from journal provenance", number: "O4")[
  Derive the provenance-scoped recovery theorem from the
  #link(<def:state-journaler>)[journaler's round-trip law]: bytes came from
  encoding a represented state, so decoding restores that state and reuses its
  erased history witness. History, DAGs, and closures are not serialized;
  arbitrary-byte validation and storage guarantees remain adapter concerns
  under #link(<decision:non-goals>)[D6].
] <open:recovery>

== Completion-aware state resolves the prior realizability gap <sec:completion-state-adequacy>

#theorem-card("One represented state determines all completed node values", [
  Enriching `lookup_occurrence` supplies the missing future-relevant state
  observation. For each ID it returns either no declaration, or the canonical
  descriptor paired with `None` while pending and `Some NodeResultValue` when
  complete. `StateRepresents` equates this runtime map to an independently
  computed map from valid history. Consequently one runtime state cannot
  represent histories that disagree on a completed local/external result or
  generator graph value.
]) <thm:completed-values-unique>

```fstar
HistoryOccurrenceStateMapAt(d,H) =
  extensional_map(id, HistoryOccurrenceStateAt(d,H,id))

HistoryStateEquivalent(d,H1:History(d),H2:History(d)) =
  HistoryOccurrenceStateMapAt(d,H1) == HistoryOccurrenceStateMapAt(d,H2)

HistoryModelExtensionality(d) =
  forall H1,H2:History(d).
    HistoryStateEquivalent(d,H1,H2)
    ==> HistoryQuiescentModel(d,HistoryObservation(H1))
        == HistoryQuiescentModel(d,HistoryObservation(H2))

SameStateForcesHistoryStateEquivalent(d,s,H1,H2) =
  forall s:state_type(d),H1,H2:History(d).
    StateRepresents(d,s,H1)
    /\ StateRepresents(d,s,H2)
    ==> HistoryStateEquivalent(d,H1,H2)

EventValidityCongruence(d) =
  forall H1,H2:History(d),e:event_type(d).
    HistoryStateEquivalent(d,H1,H2)
    ==> EventValidAt(d,H1,e) <==> EventValidAt(d,H2,e)

HistoryAppendCongruence(d) =
  forall H1,H2:History(d),e:event_type(d).
    HistoryStateEquivalent(d,H1,H2)
    /\ EventValidAt(d,H1,e)
    ==> HistoryStateEquivalent(
          d,extend_history(H1,e),extend_history(H2,e))
```

The first implication follows because `HistoryObservationFaithful` transfers
each state's observation agreement to the sequence-based map, and the same
functional `lookup_occurrence(s,id)` must agree with both histories. Its
descriptor equality aligns the dependent result types, and its result equality
forces the completion payloads to agree. This is a substantive consistency
contract: for external node `a`, a history storing `false` requires lookup
`Some(a,Some(false))`, while a history storing `true` requires
`Some(a,Some(true))`. One runtime lookup cannot satisfy both, so those two
histories cannot both represent the same state. The runtime need not retain
the entire `History`; it exposes the partial map of declarations and the
future-relevant typed result for each completed occurrence.

The event-validity congruence follows by unfolding its clauses. Declaration,
completion, prerequisite values, and generated-ID freshness are all determined
by this map. `NodeResultCorrect` additionally depends on the supplied event
and its resolved backing/input, which are identical on both sides. Appending
the same valid event updates the same occurrence entry and, for a generator,
adds descriptors from the same graph payload; hence the two extended maps
remain equal. The history model is determined by these entries: declaration
and completion status determine which occurrences are ready; the stored
dependent results supply every prerequisite value for input assembly; and
the root result is projected from the root entry. Thus the model-extensionality
lemma gives the same action bags and root result for both extended histories,
so one returned state can satisfy both preservation obligations.

#status-panel("Derived", title: "The former O5 counterexample is excluded", number: "T4")[
  In the earlier example, `H_false = [a(false)]` and `H_true = [a(true)]`
  required incompatible future inputs for `c` after `b` completed. The
  enriched law makes their occurrence-state maps differ at `a`. Therefore
  `SameStateForcesHistoryStateEquivalent` proves that no state can satisfy
  both `StateRepresents(d,s,H_false)` and `StateRepresents(d,s,H_true)`. The
  input pair that made universal transition preservation contradictory is
  impossible under the strengthened invariant. This closes O5 without adding
  a history argument to `accept_event` or requiring state to predict future
  external outcomes.
]

This resolves the identified specification contradiction, not the proof of a
particular `accept_event` implementation. Its field must still construct a
state whose lookup, queries, and terminal result match each valid extension;
that is the machine-construction proof stated in @sec:event-validity. The
enrichment adds only the observation needed to distinguish histories with
different future-relevant completion values. It does not require equality of
histories that differ only in event order or irrelevant external request/reply
details, and it does not assert that different histories must have different
runtime states.

= Observable surface and history equivalence <sec:observable-surface>

The intended machine-level snapshot is precisely its occurrence lookup,
three action queries, and optional terminal output. The history side records
events independently, then interprets those events using the fixed DAG and
LEG code. It never calls a machine read field.

#definition-card("Quiescent observation: what the machine exposes", [
  `QuiescentObservation(s)` uses only the machine's actual read functions.
  Its occurrence-state map retains the selected backing object and ordered
  source IDs, plus whether the occurrence is complete and, if so, its
  dependent result value. Agreement with the history-side meaning uses
  `SameOccurrenceState`; this is a proof relation, not a runtime comparison
  of arbitrary closures. For readers, the directly observable descriptor is
  ID, LEG kind, and ordered sources. Each query contributes a bag of
  executable action data (currently planned as ID plus assembled input); bags
  ignore list order but retain multiplicity. The last component is the
  optional terminal output.
]) <def:quiescent-observation>

```fstar
QuiescentObservation(s) =
  ( occurrence_state_lookup_projection(s),
    bag(map executable_action_observation (query_local_actions(s))),
    bag(map executable_action_observation (query_external_actions(s))),
    bag(map executable_action_observation (query_generator_actions(s))),
    terminal_output(s) )

occurrence_state_lookup_projection(s) =
  extensional_map(id, lookup_occurrence(s,id))

executable_action_observation(action) = (action.id, action.input)
```

The last projection is a planning choice that must match the final action
records: any extra field that the runner consumes belongs in the observation;
ghost proofs do not. If `occurrence_id_type` is infinite, occurrence lookup
agreement is extensional over IDs rather than an enumerated finite map.

#definition-card("History observation: only completed event data", [
  `HistoryObservation(H)` is the multiset of completion data in `H`:
  the LEG tag, occurrence ID, external request/reply data when applicable,
  and the result or graph payload. This is a proof-side projection, not the
  journal format. `StateJournaler` round-trips the machine's state snapshot;
  it need not serialize this event multiset or the erased `History` value.
  The snapshot must preserve whatever concrete values its `state_type` needs.
  The observation projection drops ghost descriptor witnesses and proofs;
  arbitrary backing closures are not journal data. It ignores list order but
  retains event multiplicity. Two valid histories with the same observation
  have the same observable completions up to a permutation that preserves
  validity and prerequisite/generator causality; they may differ in erased
  ghost witnesses or proof terms.
  This is an abstract typed event observation, not a claim that graph values
  or code closures have a particular byte encoding.
  It does not inspect a state, call a query, or invoke `terminal_output`.
  The fixed DAG/program context is supplied separately when interpreting this
  event observation.
]) <def:history-observation>

```fstar
EventData = the dependent sum of durable local, external, and generator event data
EventDataBag = multiset EventData

EventObservableData(e) =
  (kind(e), e.id, durable_payload_data(e))

HistoryObservation(H:History(d)) : EventDataBag =
  bag(map EventObservableData (events(H)))

HistoryObservationDomain(d) =
  { ho:EventDataBag | exists H:History(d). HistoryObservation(H) = ho }

```

`HistoryObservationDomain(d)` contains only bags that are the event-data
observation of some `H:History(d)`. `HistoryQuiescentModel` is defined on this
domain, whose per-ID descriptor is single-valued by the proof at
#link(<def:exclusive-membership>)[D3]. Its body uses only `ho`; the witness that `ho`
comes from a valid history restricts the domain and is erased. The model makes
no claim about arbitrary bags containing conflicting graph declarations.

Define a history-only model of the current abstract state observations. Its
inputs are the fixed DAG/program and `HistoryObservation`; its computation
uses only static declarations, graph values carried by generator events,
completion values, the LEG input assemblers, and the designated root result.
It does not use `lookup_occurrence`, `query_*_actions`, `terminal_output`,
`accept_event`, replay, or `QuiescentObservation`.

The history map is the canonical union of static declarations and every
descriptor contributed by a generator completion in the event bag. Freshness
and functional interpreters make this map single-valued within each valid
history; descriptors may vary across alternative histories. Completion lookup
and `RootResult` read payloads from this same bag, and the action bags filter
the map by prerequisite completion and canonical input assembly. These bag
queries are order-insensitive counterparts of the prefix-indexed sequence
predicates used while validating a history.

```fstar
CompletedInObservation(ho,id) =
  some event datum in ho has occurrence_id = id

CompletionValueInObservation(d,ho,id,o) : option NodeResultValue(o) =
  the unique event datum in ho with occurrence_id = id, projected to
  NodeResultValue(o), if present

DeclaredInObservation(d,ho,id,o) =
  StaticInterpretation(d,id,o)
  \/ exists generator_datum,graph.
       generator_datum in ho
       /\ generator_graph_payload(generator_datum) = Some graph
       /\ GraphInterpretation(d,graph,id,o)

SourceValuesInObservation(d,ho,o) : option InputValues(o.backing.input_slots) =
  map RootInput sources to the root input x; for each
  InputFromOccurrence(p), obtain p's selected descriptor and its
  CompletionValueInObservation(d,ho,p,descriptor); collect in source order,
  preserving dependent input indices;
  return None if any occurrence source has no completion

HistoryActionFromObservation_k(d,ho,id,input) =
  exists o.
    DeclaredInObservation(d,ho,id,o)
    /\ kind(o) = k
    /\ not CompletedInObservation(ho,id)
    /\ match SourceValuesInObservation(d,ho,o) with
       | None -> False
       | Some values -> o.backing.assemble_input(values) = Some input

HistoryOccurrenceStateFromObservation(d,ho,id) =
  match unique o satisfying DeclaredInObservation(d,ho,id,o) with
  | None -> None
  | Some o ->
      Some (#o, CompletionValueInObservation(d,ho,id,o))

HistoryOccurrenceStateMapFromObservation(d,ho) =
  extensional_map(id, HistoryOccurrenceStateFromObservation(d,ho,id))

HistoryQuiescentModel(d,ho:HistoryObservationDomain(d)) =
  ( HistoryOccurrenceStateMapFromObservation(d,ho),
    bag { (id,input) | HistoryActionFromObservation_local(d,ho,id,input) },
    bag { (id,input) | HistoryActionFromObservation_external(d,ho,id,input) },
    bag { (id,input) | HistoryActionFromObservation_generator(d,ho,id,input) },
    RootResult(d,root_id,ho) )

HistoryModelFromSequence(d,H:History(d)) =
  ( HistoryOccurrenceStateMapAt(d,H),
    bag { (id,input) | HistoryAction_local(d,H,id,input) },
    bag { (id,input) | HistoryAction_external(d,H,id,input) },
    bag { (id,input) | HistoryAction_generator(d,H,id,input) },
    RootResult(d,root_id,H) )

HistoryObservationFaithful(d,H:History(d)) =
  HistoryQuiescentModel(d,HistoryObservation(H))
    = HistoryModelFromSequence(d,H)

OccurrenceStateMapsAgree(actual,expected) =
  forall id.
    match actual(id), expected(id) with
    | None, None -> true
    | Some actual_state, Some expected_state ->
        SameOccurrenceState(actual_state,expected_state)
    | _, _ -> false

ObservationAgreement(actual,expected) =
  OccurrenceStateMapsAgree(
    actual.occurrence_states,expected.occurrence_states)
  /\ actual.local_actions = expected.local_actions
  /\ actual.external_actions = expected.external_actions
  /\ actual.generator_actions = expected.generator_actions
  /\ actual.terminal_output = expected.root_result

```

The occurrence map retains each selected descriptor and optional
`NodeResultValue`, including its producer input index. Its sequence counterpart
is defined in @sec:state-represents; the equation above is the bridge between
them. `RootResult(d,root_id,ho)` is the optional dependent result of the
selected root completion.

`HistoryObservationFaithful` is a derived projection lemma, not a machine
contract: for `H:History(d)`, the event-data bag contains enough information
to compute the same occurrence-state map (including completion status and
typed result), ready-action bags, and root result as the ordered history. It
depends on retaining each result and graph payload, plus the dependent input
witness when it cannot be reconstructed. It never reads
the machine state or its query results. This is the bridge that makes the
history side independent of `QuiescentObservation` without making it
under-specified.

#observable-behavior([
  For a represented state, the exact occurrences, action inputs and terminal
  result visible to the caller are fixed by the completed events and supplied
  DAG/program. Query-list order is not guaranteed: the correctness relation
  treats each list as a bag, so callers must not use list position as a
  scheduling priority unless they impose their own policy. A caller that
  dispatches the first item may choose different work when list order changes.
  Multiplicity is retained; duplicate executable actions are ruled out by
  equality with the one-entry-per-ready-occurrence history model.
])

#theorem-card("The master observation law is meaningful, but not the whole theorem", [
  The left side calls machine functions. The right side is independently
  derived from graph semantics and event payloads. Their semantic agreement
  is not definitional and can fail if `accept_event` corrupts a query, drops a
  generated occurrence, returns the wrong backing meaning, or exposes a wrong
  input. It is therefore a meaningful invariant to prove for the actual
  machine.

  History validity constrains events, not arbitrary machine-state reads.
  For a concrete countermodel, let the DAG contain one static local root `r`
  whose `RootInput` assembler accepts `x` and whose implementation returns
  `y`. At the empty history the independent model contains lookup `r` and
  local action `(r,x)`. A machine with the single state `bad`, empty lookup,
  empty queries, and no terminal output disagrees with that model. The input,
  freshness, productivity, and terminal-coherence laws can all hold for this
  DAG. If `StateRepresents` were weakened to history validity alone, choosing
  `initial_state = bad` and `accept_event(bad,e) = bad` would satisfy the
  weakened initial/preservation propositions while losing `r` and its action.
  `ObservationAgreement` rules out that concrete bad behavior, so it is the
  substantive part of the machine invariant.

  By contrast, a separate theorem saying “`StateRepresents` implies the same
  observation equality used to define it” is only a projection and adds
  nothing. Because histories are proof-carrying, the document defines
  `StateRepresents` as independent observation agreement over `History(d)`;
  it omits the redundant `ValidHistory` conjunct and the projection theorem.
  The substantive proofs are that the initial machine state satisfies this
  equality and that `accept_event` preserves it for every history-valid event.
  The completed-value component of lookup agreement rules out the former cross-history conflict;
  @sec:completion-state-adequacy gives the argument. Induction over history
  construction then establishes the corresponding preservation result for a
  machine whose fields satisfy their refinements. These are non-vacuous
  obligations on the actual machine fields.

  This is one part of the correctness statement, not a reason to omit the
  other obligations. Each remaining obligation also has an observable role:

  - Graph interpretation defines which occurrences the static DAG and each
    generated graph value mean. `StateRepresents` checks that machine lookup
    exposes exactly that history-derived occurrence map. Because these types
    are caller-supplied and opaque, the interpretation is their declared
    meaning; the machine can prove consistency with it, not an external notion
    of what the caller intended.
  - Typed input compatibility affects the action observations. The history
    model includes `(id,input)` exactly when the occurrence is ready and its
    canonical assembler succeeds. `DagProductivity` plus valid-event input
    checks derive `DagInputAssemblyLaw`, ruling out a declared, ready
    occurrence whose prerequisites cannot form an input; observation
    agreement then proves the machine query returns that input.
  - Event result correctness constrains which histories may be observed.
    `EventValidAt` requires the local result equation, external validator, or
    generator result equation, as appropriate. Without it, a wrong payload
    could be recorded and then propagated consistently into later actions.
  - State transition correctness is the observable preservation theorem:
    the `initial_state` refinement establishes the empty-history observation, and
    the refined `accept_event` field is intended to say each valid event
    changes the machine observation to the one specified by the extended
    history. The enriched lookup makes the all-represented-histories
    postcondition observationally compatible; see
    @sec:completion-state-adequacy.
  - State recovery has its own codec law: decoding an encoded state returns
    that exact state. Under the premise that the bytes came from encoding a
    represented state, the ghost proof can reuse that state's history witness;
    the witness itself is not serialized. This is not a guarantee for
    arbitrary bytes without producer provenance.

  Thus the intended end-to-end account is observational throughout: event
  validity defines admissible history steps; the history model defines their
  expected observations; initialization and transitions preserve that
  observation; recovery restores it from the journal. `StateRepresents` is
  the central snapshot equality within that chain, not a substitute for the
  chain's other laws.
]) <thm:observation-nonvacuity>

#pagebreak()
= Source audit and mismatch <sec:source-audit>

The current F\* files are an earlier skeleton, not an implementation of the
observation design above. This comparison records the precise gap; no source
changes are part of this document update.

#table(
  columns: (1.6fr, 2.2fr, 2.1fr), inset: 5pt,
  stroke: 0.5pt + rgb("C7CED4"),
  [*Current F\* skeleton*], [*Mismatch with this WIP*], [*Planned formalization target*],
  [LEG records have typed source lists and input resolvers; each resolver returns an input directly.], [Wiring is currently stored on the backing node and resolution does not represent failure.], [Store ordered sources on `NodeOccurrence`; each LEG assembler consumes the typed values for those sources and returns `option input`.],
  [Generator output type is indexed by the generator input; there is no independent machine-level `graph_spec_type` in the skeleton.], [This is stronger/indexed differently from the selected abstract boundary.], [Supply one `graph_spec_type` on the machine and require each generator result to be that type; define graph interpretation separately.],
  [Actions carry only occurrence IDs; events use arbitrary per-ID value-type families.], [The action does not expose its assembled input and events are not tied to the selected backer's result type.], [Define the executable action observation with its input; make event payload correctness depend on the resolved occurrence and canonical input.],
  [`event_valid_at` calls machine queries and accepts caller-supplied prerequisite/result callbacks.], [History construction is coupled to machine reads, and callback consistency is not independently constrained.], [Define `EventValidAt` from graph interpretation, prior events, assembled inputs, and LEG result equations; derive actual query visibility from `StateRepresents`.],
  [`accept_event_consistency` proves replay-state equality for a history-indexed transition.], [This is fold consistency, not the quiescent/history agreement of @sec:observable-surface.], [Prove initial observation and one-step preservation of the master observation agreement.],
  [`terminal_output` and recovery are operation fields without semantic laws.], [No terminal/history relation or state-codec round-trip law is specified.], [Add history terminal coherence and the `StateJournaler` round-trip contract.],
)

The previous `system_spec.md` and `state/work_dag.md` retain older designs and
remain historical context.
