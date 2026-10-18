module WorkflowV2.StateMachineTypes

open FStar.List.Tot

// Input source references and typed input values {{{1
// A node's input is assembled from a typed heterogeneous list. The source
// list has the same type-level shape, with each slot identifying either the
// root input or an occurrence whose output supplies that slot.
type node_input_source (occurrence_id_type:eqtype) =
  | InputFromRoot
  | InputFromOccurrence of occurrence_id_type

noeq type node_input_values : list Type0 -> Type =
  | NoNodeInputs : node_input_values []
  | NodeInputCons : #head:Type0 -> #tail:list Type0 ->
      head -> node_input_values tail -> node_input_values (head :: tail)

noeq type node_input_sources (occurrence_id_type:eqtype)
    : list Type0 -> Type =
  | NoNodeInputSources : node_input_sources occurrence_id_type []
  | NodeInputSourceCons : #head:Type0 -> #tail:list Type0 ->
      node_input_source occurrence_id_type ->
      node_input_sources occurrence_id_type tail ->
      node_input_sources occurrence_id_type (head :: tail)
// }}}

// Caller-supplied LEG node packages {{{1
// Input slots are typed here; the caller's DAG contract connects each source
// to a value of its declared component type.
noeq type local_node (occurrence_id_type:eqtype)
    (input_component_types:list Type0) (input_type:Type0)
    (output_type:input_type -> Type0) = {
  local_input_sources:
    node_input_sources occurrence_id_type input_component_types;
  resolve_local_input:
    node_input_values input_component_types -> input_type;
  run_local: i:input_type -> output_type i
}

noeq type external_node (occurrence_id_type:eqtype)
    (input_component_types:list Type0) (input_type:Type0)
    (output_type:input_type -> Type0) = {
  external_input_sources:
    node_input_sources occurrence_id_type input_component_types;
  resolve_external_input:
    node_input_values input_component_types -> input_type;
  request_type: input_type -> Type0;
  reply_type: i:input_type -> request_type i -> Type0;
  prepare_external: i:input_type -> request_type i;
  validate_reply:
    i:input_type -> r:request_type i -> reply_type i r -> option (output_type i)
}

noeq type generator_node (occurrence_id_type:eqtype)
    (input_component_types:list Type0) (input_type:Type0)
    (graph_spec_type:input_type -> Type0) = {
  generator_input_sources:
    node_input_sources occurrence_id_type input_component_types;
  resolve_generator_input:
    node_input_values input_component_types -> input_type;
  generate_graph: i:input_type -> graph_spec_type i
}
// }}}

// Actions, events, and histories {{{1
// Actions identify ready occurrences; code and inputs stay in the DAG.
type local_action (occurrence_id_type:eqtype) =
  | LocalAction of occurrence_id_type
type external_action (occurrence_id_type:eqtype) =
  | ExternalAction of occurrence_id_type
type generator_action (occurrence_id_type:eqtype) =
  | GeneratorAction of occurrence_id_type

// Each event names its completed occurrence and carries its caller-defined
// payload. Prerequisites come from node inputs; result contracts relate
// payloads to their operations.
noeq type local_event (occurrence_id_type:eqtype)
    (value_type:occurrence_id_type -> Type0) = {
  local_occurrence_id: occurrence_id_type;
  local_value: value_type local_occurrence_id
}

noeq type external_event (occurrence_id_type:eqtype)
    (value_type:occurrence_id_type -> Type0) = {
  external_occurrence_id: occurrence_id_type;
  external_value: value_type external_occurrence_id
}

noeq type generator_event (occurrence_id_type:eqtype)
    (value_type:occurrence_id_type -> Type0) = {
  generator_occurrence_id: occurrence_id_type;
  generator_value: value_type generator_occurrence_id
}

// One sum type gives histories a single event element type while retaining
// separate, caller-chosen value families for each LEG case.
noeq type event (occurrence_id_type:eqtype)
    (local_value_type:occurrence_id_type -> Type0)
    (external_value_type:occurrence_id_type -> Type0)
    (generator_value_type:occurrence_id_type -> Type0) =
  | LocalCompletion of local_event occurrence_id_type local_value_type
  | ExternalCompletion of external_event occurrence_id_type external_value_type
  | GeneratorCompletion of generator_event occurrence_id_type generator_value_type

type event_sequence (occurrence_id_type:eqtype)
    (local_value_type:occurrence_id_type -> Type0)
    (external_value_type:occurrence_id_type -> Type0)
    (generator_value_type:occurrence_id_type -> Type0) =
  list (event occurrence_id_type local_value_type external_value_type generator_value_type)
// }}}

// Replay and event-validity helpers {{{1
// Helpers take callbacks directly so the machine's proof field can refer to
// earlier operations without making history depend on the whole machine.
val fold_updates:
  #input_type:Type0 ->
  #dag_type:(input_type -> Type0) ->
  #occurrence_id_type:eqtype ->
  #local_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #external_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #generator_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #rep_type:(x:input_type -> dag:dag_type x -> Type0) ->
  accept_event:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag ->
    event occurrence_id_type (local_value_type x dag)
      (external_value_type x dag) (generator_value_type x dag) ->
    rep_type x dag) ->
  x:input_type -> dag:dag_type x -> s:rep_type x dag ->
  events:event_sequence occurrence_id_type
    (local_value_type x dag) (external_value_type x dag)
    (generator_value_type x dag) ->
  Tot (rep_type x dag)
// }}}

// Event validity and proof-carrying histories {{{1
val event_occurrence_id:
  #occurrence_id_type:eqtype ->
  #local_value_type:(occurrence_id_type -> Type0) ->
  #external_value_type:(occurrence_id_type -> Type0) ->
  #generator_value_type:(occurrence_id_type -> Type0) ->
  event occurrence_id_type local_value_type external_value_type
    generator_value_type -> Tot occurrence_id_type

val completed:
  #occurrence_id_type:eqtype ->
  #local_value_type:(occurrence_id_type -> Type0) ->
  #external_value_type:(occurrence_id_type -> Type0) ->
  #generator_value_type:(occurrence_id_type -> Type0) ->
  event_sequence occurrence_id_type local_value_type external_value_type
    generator_value_type -> occurrence_id_type -> Tot prop

val prerequisites_present:
  #occurrence_id_type:eqtype ->
  #local_value_type:(occurrence_id_type -> Type0) ->
  #external_value_type:(occurrence_id_type -> Type0) ->
  #generator_value_type:(occurrence_id_type -> Type0) ->
  event_sequence occurrence_id_type local_value_type external_value_type
    generator_value_type -> list occurrence_id_type -> Tot prop

val uncommitted:
  #occurrence_id_type:eqtype ->
  #local_value_type:(occurrence_id_type -> Type0) ->
  #external_value_type:(occurrence_id_type -> Type0) ->
  #generator_value_type:(occurrence_id_type -> Type0) ->
  event_sequence occurrence_id_type local_value_type external_value_type
    generator_value_type -> occurrence_id_type -> Tot prop

val event_action_available:
  #input_type:Type0 ->
  #dag_type:(input_type -> Type0) ->
  #occurrence_id_type:eqtype ->
  #local_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #external_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #generator_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #rep_type:(x:input_type -> dag:dag_type x -> Type0) ->
  initial_state:(x:input_type -> dag:dag_type x -> rep_type x dag) ->
  accept_event:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag ->
    event occurrence_id_type (local_value_type x dag)
      (external_value_type x dag) (generator_value_type x dag) ->
    rep_type x dag) ->
  query_local_actions:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> list (local_action occurrence_id_type)) ->
  query_external_actions:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> list (external_action occurrence_id_type)) ->
  query_generator_actions:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> list (generator_action occurrence_id_type)) ->
  x:input_type -> dag:dag_type x ->
  events:event_sequence occurrence_id_type
    (local_value_type x dag) (external_value_type x dag)
    (generator_value_type x dag) ->
  e:event occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
  Tot prop

val event_valid_at:
  #input_type:Type0 ->
  #dag_type:(input_type -> Type0) ->
  #occurrence_id_type:eqtype ->
  #local_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #external_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #generator_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #rep_type:(x:input_type -> dag:dag_type x -> Type0) ->
  initial_state:(x:input_type -> dag:dag_type x -> rep_type x dag) ->
  accept_event:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag ->
    event occurrence_id_type (local_value_type x dag)
      (external_value_type x dag) (generator_value_type x dag) ->
    rep_type x dag) ->
  query_local_actions:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> list (local_action occurrence_id_type)) ->
  query_external_actions:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> list (external_action occurrence_id_type)) ->
  query_generator_actions:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> list (generator_action occurrence_id_type)) ->
  x:input_type -> dag:dag_type x ->
  node_prerequisites:(
    event_sequence occurrence_id_type (local_value_type x dag)
      (external_value_type x dag) (generator_value_type x dag) ->
    occurrence_id_type -> list occurrence_id_type) ->
  node_result_contract:(
    event_sequence occurrence_id_type (local_value_type x dag)
      (external_value_type x dag) (generator_value_type x dag) ->
    event occurrence_id_type (local_value_type x dag)
      (external_value_type x dag) (generator_value_type x dag) -> prop) ->
  events:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
  e:event occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) -> Tot prop

// History is indexed by its event sequence and can only be extended with a
// proof that the new event is valid at the preceding sequence.
noeq type history
    (#occurrence_id_type:eqtype)
    (#local_value_type:(occurrence_id_type -> Type0))
    (#external_value_type:(occurrence_id_type -> Type0))
    (#generator_value_type:(occurrence_id_type -> Type0))
    (valid_at:
      event_sequence occurrence_id_type local_value_type external_value_type
        generator_value_type ->
      event occurrence_id_type local_value_type external_value_type
        generator_value_type -> prop)
    : event_sequence occurrence_id_type local_value_type external_value_type
        generator_value_type -> Type =
  | EmptyHistory:
      history valid_at []
  | LocalStep: #previous_events:event_sequence occurrence_id_type
      local_value_type external_value_type generator_value_type ->
      history valid_at previous_events ->
      local_completion:local_event occurrence_id_type local_value_type ->
      proof_event_valid_at_previous:
        squash (valid_at previous_events (LocalCompletion local_completion)) ->
      history valid_at
        (previous_events @ [LocalCompletion local_completion])
  | ExternalStep: #previous_events:event_sequence occurrence_id_type
      local_value_type external_value_type generator_value_type ->
      history valid_at previous_events ->
      external_completion:external_event occurrence_id_type external_value_type ->
      proof_event_valid_at_previous:
        squash (valid_at previous_events (ExternalCompletion external_completion)) ->
      history valid_at
        (previous_events @ [ExternalCompletion external_completion])
  | GeneratorStep: #previous_events:event_sequence occurrence_id_type
      local_value_type external_value_type generator_value_type ->
      history valid_at previous_events ->
      generator_completion:generator_event occurrence_id_type generator_value_type ->
      proof_event_valid_at_previous:
        squash (valid_at previous_events (GeneratorCompletion generator_completion)) ->
      history valid_at
        (previous_events @ [GeneratorCompletion generator_completion])
// }}}

// Ghost history replay and initial-state law {{{1
// Replay from the initial state defines the canonical state for a history.
val state_after_history:
  #input_type:Type0 ->
  #dag_type:(input_type -> Type0) ->
  #occurrence_id_type:eqtype ->
  #local_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #external_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #generator_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #rep_type:(x:input_type -> dag:dag_type x -> Type0) ->
  initial_state:(x:input_type -> dag:dag_type x -> rep_type x dag) ->
  accept_event:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> event occurrence_id_type (local_value_type x dag)
      (external_value_type x dag) (generator_value_type x dag) -> rep_type x dag) ->
  x:input_type -> dag:dag_type x ->
  valid_at:(event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> prop) ->
  events:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
  h:history valid_at events -> GTot (rep_type x dag)

// Append an event to a valid history using its proof of validity at the
// preceding prefix.
val extend_history:
  #occurrence_id_type:eqtype ->
  #local_value_type:(occurrence_id_type -> Type0) ->
  #external_value_type:(occurrence_id_type -> Type0) ->
  #generator_value_type:(occurrence_id_type -> Type0) ->
  valid_at:(event_sequence occurrence_id_type local_value_type external_value_type
    generator_value_type -> event occurrence_id_type local_value_type
      external_value_type generator_value_type -> prop) ->
  #events:event_sequence occurrence_id_type local_value_type external_value_type
    generator_value_type ->
  h:history valid_at events ->
  e:event occurrence_id_type local_value_type external_value_type generator_value_type ->
  proof_event_valid_at_previous:squash (valid_at events e) ->
  Tot (history valid_at (events @ [e]))

// Relates an actual representation value to the canonical replay of a
// proof-carrying history. This is a ghost proposition, not stored state.
val state_at:
  #input_type:Type0 ->
  #dag_type:(input_type -> Type0) ->
  #occurrence_id_type:eqtype ->
  #local_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #external_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #generator_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #rep_type:(x:input_type -> dag:dag_type x -> Type0) ->
  initial_state:(x:input_type -> dag:dag_type x -> rep_type x dag) ->
  accept_event:(#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> event occurrence_id_type (local_value_type x dag)
      (external_value_type x dag) (generator_value_type x dag) -> rep_type x dag) ->
  x:input_type -> dag:dag_type x ->
  valid_at:(event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> prop) ->
  s:rep_type x dag ->
  events:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
  h:history valid_at events -> GTot prop

// Base case: replaying the empty history returns the initial state.
val initial_state_empty_history:
  #input_type:Type0 -> #dag_type:(input_type -> Type0) ->
  #occurrence_id_type:eqtype ->
  #local_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #external_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #generator_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #rep_type:(x:input_type -> dag:dag_type x -> Type0) ->
  initial_state:(x:input_type -> dag:dag_type x -> rep_type x dag) ->
  accept_event:(#x:input_type -> #dag:dag_type x -> rep_type x dag ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> rep_type x dag) ->
  x:input_type -> dag:dag_type x ->
  valid_at:(event_sequence occurrence_id_type
    (local_value_type x dag) (external_value_type x dag)
    (generator_value_type x dag) -> event occurrence_id_type
      (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> prop) ->
  Lemma (state_after_history initial_state accept_event x dag valid_at []
    (EmptyHistory <: history valid_at []) ==
    initial_state x dag)

// Direct base case for the state/history relation.
val initial_state_at_empty_history:
  #input_type:Type0 -> #dag_type:(input_type -> Type0) ->
  #occurrence_id_type:eqtype ->
  #local_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #external_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #generator_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0) ->
  #rep_type:(x:input_type -> dag:dag_type x -> Type0) ->
  initial_state:(x:input_type -> dag:dag_type x -> rep_type x dag) ->
  accept_event:(#x:input_type -> #dag:dag_type x -> rep_type x dag ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> rep_type x dag) ->
  x:input_type -> dag:dag_type x ->
  valid_at:(event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> prop) ->
  Lemma (state_at initial_state accept_event x dag valid_at (initial_state x dag)
    [] (EmptyHistory <: history valid_at []))
// }}}

// Machine object {{{1
noeq type machine = {
  input_type:Type0;
  dag_type:input_type -> Type0;
  occurrence_id_type:eqtype;

  local_value_type:
    x:input_type -> dag_type x -> occurrence_id_type -> Type0;
  external_value_type:
    x:input_type -> dag_type x -> occurrence_id_type -> Type0;
  generator_value_type:
    x:input_type -> dag_type x -> occurrence_id_type -> Type0;
  rep_type:x:input_type -> dag_type x -> Type0;
  root_output_type:x:input_type -> dag_type x -> Type0;
  journal_type:x:input_type -> dag_type x -> Type0;

  initial_state:x:input_type -> dag:dag_type x -> rep_type x dag;
  query_local_actions:#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> list (local_action occurrence_id_type);
  query_external_actions:#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> list (external_action occurrence_id_type);
  query_generator_actions:#x:input_type -> #dag:dag_type x ->
    rep_type x dag -> list (generator_action occurrence_id_type);
  accept_event:#x:input_type -> #dag:dag_type x -> rep_type x dag ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> rep_type x dag;
  terminal_output:#x:input_type -> #dag:dag_type x -> rep_type x dag ->
    option (root_output_type x dag);
  recover:x:input_type -> dag:dag_type x -> journal_type x dag ->
    option (rep_type x dag);

  // Law for the one `accept_event` transition above: under a matching history
  // and a valid event, the transition preserves StateAt.
  accept_event_consistency:
    #x:input_type -> #dag:dag_type x ->
    // Caller-supplied graph observations used by EventValidAt.
    node_prerequisites:(event_sequence occurrence_id_type
      (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> occurrence_id_type -> list occurrence_id_type) ->
    node_result_contract:(event_sequence occurrence_id_type
      (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> event occurrence_id_type
        (local_value_type x dag) (external_value_type x dag)
        (generator_value_type x dag) -> prop) ->
    // `h` proves that this exact event prefix is valid.
    #events:event_sequence occurrence_id_type (local_value_type x dag)
      (external_value_type x dag) (generator_value_type x dag) ->
    h:history
      (fun prefix candidate -> event_valid_at initial_state accept_event
        query_local_actions query_external_actions query_generator_actions
        x dag node_prerequisites node_result_contract prefix candidate)
      events ->
    // Require s to equal replay from the initial state through this prefix.
    s:rep_type x dag{state_at initial_state accept_event x dag
      (fun prefix candidate -> event_valid_at initial_state accept_event
        query_local_actions query_external_actions query_generator_actions
        x dag node_prerequisites node_result_contract prefix candidate)
      s events h} ->
    e:event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) ->
    // e is valid here: prerequisites are complete, it is uncommitted, its
    // result meets the supplied contract, and its action is queryable.
    proof_event_valid_at_previous:squash (event_valid_at initial_state
      accept_event query_local_actions query_external_actions
      query_generator_actions x dag node_prerequisites node_result_contract events e) ->
    // Guarantee: this transition yields the state for the extended history.
    Lemma (state_at initial_state accept_event x dag
      (fun prefix candidate -> event_valid_at initial_state accept_event
        query_local_actions query_external_actions query_generator_actions
        x dag node_prerequisites node_result_contract prefix candidate)
      (accept_event #x #dag s e)
      (events @ [e])
      (extend_history
        (fun prefix candidate -> event_valid_at initial_state accept_event
          query_local_actions query_external_actions query_generator_actions
          x dag node_prerequisites node_result_contract prefix candidate)
        h e proof_event_valid_at_previous))
}
// }}}
