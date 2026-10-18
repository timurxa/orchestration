module WorkflowV2.StateMachineTypes

open FStar.List.Tot

// Callback type aliases {{{1
type initial_state_type
  (input_type:Type0)
  (dag_type:input_type -> Type0)
  (rep_type:(x:input_type -> dag:dag_type x -> Type0)) =
  x:input_type -> dag:dag_type x -> rep_type x dag

type event_transition_type
  (input_type:Type0)
  (dag_type:input_type -> Type0)
  (occurrence_id_type:eqtype)
  (local_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0))
  (external_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0))
  (generator_value_type:(x:input_type -> dag:dag_type x -> occurrence_id_type -> Type0))
  (rep_type:(x:input_type -> dag:dag_type x -> Type0)) =
  #x:input_type -> #dag:dag_type x -> rep_type x dag ->
  event occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) -> rep_type x dag

type local_action_query_type
  (input_type:Type0)
  (dag_type:input_type -> Type0)
  (occurrence_id_type:eqtype)
  (rep_type:(x:input_type -> dag:dag_type x -> Type0)) =
  #x:input_type -> #dag:dag_type x -> rep_type x dag ->
  list (local_action occurrence_id_type)

type external_action_query_type
  (input_type:Type0)
  (dag_type:input_type -> Type0)
  (occurrence_id_type:eqtype)
  (rep_type:(x:input_type -> dag:dag_type x -> Type0)) =
  #x:input_type -> #dag:dag_type x -> rep_type x dag ->
  list (external_action occurrence_id_type)

type generator_action_query_type
  (input_type:Type0)
  (dag_type:input_type -> Type0)
  (occurrence_id_type:eqtype)
  (rep_type:(x:input_type -> dag:dag_type x -> Type0)) =
  #x:input_type -> #dag:dag_type x -> rep_type x dag ->
  list (generator_action occurrence_id_type)

// }}}

// Replay one event sequence {{{1
let rec fold_updates
  (#input_type:Type0)
  (#dag_type:(input_type -> Type0))
  (#occurrence_id_type:eqtype)
  (#local_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#external_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#generator_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#rep_type:(x:input_type -> dag_type x -> Type0))
  (accept_event:event_transition_type input_type dag_type occurrence_id_type
    local_value_type external_value_type generator_value_type rep_type)
  (x:input_type)
  (dag:dag_type x)
  (s:rep_type x dag)
  (events:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag))
  : Tot (rep_type x dag) (decreases events)
  =
  match events with
  | [] -> s
  | e :: rest ->
      fold_updates accept_event x dag
        (accept_event s e) rest
// }}}

// Event and readiness predicates {{{1
let event_occurrence_id
  (#occurrence_id_type:eqtype)
  (#local_value_type:occurrence_id_type -> Type0)
  (#external_value_type:occurrence_id_type -> Type0)
  (#generator_value_type:occurrence_id_type -> Type0)
  (e:event occurrence_id_type local_value_type external_value_type
      generator_value_type)
  : Tot occurrence_id_type
  =
  match e with
  | LocalCompletion local -> local.local_occurrence_id
  | ExternalCompletion external -> external.external_occurrence_id
  | GeneratorCompletion generator -> generator.generator_occurrence_id

let rec completed
  (#occurrence_id_type:eqtype)
  (#local_value_type:occurrence_id_type -> Type0)
  (#external_value_type:occurrence_id_type -> Type0)
  (#generator_value_type:occurrence_id_type -> Type0)
  (events:event_sequence occurrence_id_type local_value_type
      external_value_type generator_value_type)
  (occurrence_id:occurrence_id_type)
  : Tot prop (decreases events)
  =
  match events with
  | [] -> False
  | e :: rest ->
      event_occurrence_id e = occurrence_id \/ completed rest occurrence_id

let rec prerequisites_present
  (#occurrence_id_type:eqtype)
  (#local_value_type:occurrence_id_type -> Type0)
  (#external_value_type:occurrence_id_type -> Type0)
  (#generator_value_type:occurrence_id_type -> Type0)
  (events:event_sequence occurrence_id_type local_value_type
      external_value_type generator_value_type)
  (prerequisites:list occurrence_id_type)
  : Tot prop (decreases prerequisites)
  =
  match prerequisites with
  | [] -> True
  | prerequisite :: rest ->
      completed events prerequisite /\ prerequisites_present events rest

let uncommitted
  (#occurrence_id_type:eqtype)
  (#local_value_type:occurrence_id_type -> Type0)
  (#external_value_type:occurrence_id_type -> Type0)
  (#generator_value_type:occurrence_id_type -> Type0)
  (events:event_sequence occurrence_id_type local_value_type
      external_value_type generator_value_type)
  (occurrence_id:occurrence_id_type)
  : Tot prop
  =
  completed events occurrence_id ==> False

let rec local_action_contains
  (#occurrence_id_type:eqtype)
  (occurrence_id:occurrence_id_type)
  (actions:list (local_action occurrence_id_type))
  : Tot prop (decreases actions)
  =
  match actions with
  | [] -> False
  | LocalAction candidate :: rest ->
      candidate = occurrence_id \/ local_action_contains occurrence_id rest

let rec external_action_contains
  (#occurrence_id_type:eqtype)
  (occurrence_id:occurrence_id_type)
  (actions:list (external_action occurrence_id_type))
  : Tot prop (decreases actions)
  =
  match actions with
  | [] -> False
  | ExternalAction candidate :: rest ->
      candidate = occurrence_id \/ external_action_contains occurrence_id rest

let rec generator_action_contains
  (#occurrence_id_type:eqtype)
  (occurrence_id:occurrence_id_type)
  (actions:list (generator_action occurrence_id_type))
  : Tot prop (decreases actions)
  =
  match actions with
  | [] -> False
  | GeneratorAction candidate :: rest ->
      candidate = occurrence_id \/ generator_action_contains occurrence_id rest
// }}}

// Event validity and history/state relations {{{1
let event_action_available
  (#input_type:Type0)
  (#dag_type:(input_type -> Type0))
  (#occurrence_id_type:eqtype)
  (#local_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#external_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#generator_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#rep_type:(x:input_type -> dag_type x -> Type0))
  (initial_state:initial_state_type input_type dag_type rep_type)
  (accept_event:event_transition_type input_type dag_type occurrence_id_type
    local_value_type external_value_type generator_value_type rep_type)
  (query_local_actions:local_action_query_type input_type dag_type
    occurrence_id_type rep_type)
  (query_external_actions:external_action_query_type input_type dag_type
    occurrence_id_type rep_type)
  (query_generator_actions:generator_action_query_type input_type dag_type
    occurrence_id_type rep_type)
  (x:input_type)
  (dag:dag_type x)
  (events:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag))
  (e:event occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag))
  : Tot prop
  =
  let s = fold_updates accept_event x dag
    (initial_state x dag) events in
  match e with
  | LocalCompletion local ->
      local_action_contains local.local_occurrence_id (query_local_actions s)
  | ExternalCompletion external ->
      external_action_contains external.external_occurrence_id
        (query_external_actions s)
  | GeneratorCompletion generator ->
      generator_action_contains generator.generator_occurrence_id
        (query_generator_actions s)

let event_valid_at
  (#input_type:Type0)
  (#dag_type:(input_type -> Type0))
  (#occurrence_id_type:eqtype)
  (#local_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#external_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#generator_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#rep_type:(x:input_type -> dag_type x -> Type0))
  (initial_state:initial_state_type input_type dag_type rep_type)
  (accept_event:event_transition_type input_type dag_type occurrence_id_type
    local_value_type external_value_type generator_value_type rep_type)
  (query_local_actions:local_action_query_type input_type dag_type
    occurrence_id_type rep_type)
  (query_external_actions:external_action_query_type input_type dag_type
    occurrence_id_type rep_type)
  (query_generator_actions:generator_action_query_type input_type dag_type
    occurrence_id_type rep_type)
  (x:input_type)
  (dag:dag_type x)
  (node_prerequisites:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
    occurrence_id_type -> list occurrence_id_type)
  (node_result_contract:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> prop)
  (events:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag))
  (e:event occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag))
  : Tot prop
  =
  let occurrence_id = event_occurrence_id e in
  prerequisites_present events (node_prerequisites events occurrence_id) /\
  uncommitted events occurrence_id /\
  node_result_contract events e /\
  event_action_available initial_state accept_event
    query_local_actions query_external_actions query_generator_actions
    x dag events e

let state_after_history
  (#input_type:Type0)
  (#dag_type:(input_type -> Type0))
  (#occurrence_id_type:eqtype)
  (#local_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#external_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#generator_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#rep_type:(x:input_type -> dag_type x -> Type0))
  (initial_state:initial_state_type input_type dag_type rep_type)
  (accept_event:event_transition_type input_type dag_type occurrence_id_type
    local_value_type external_value_type generator_value_type rep_type)
  (x:input_type)
  (dag:dag_type x)
  (valid_at:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> prop)
  (events:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag))
  (h:history valid_at events)
  : GTot (rep_type x dag)
  =
  fold_updates accept_event x dag
    (initial_state x dag) events

let extend_history
  (#occurrence_id_type:eqtype)
  (#local_value_type:occurrence_id_type -> Type0)
  (#external_value_type:occurrence_id_type -> Type0)
  (#generator_value_type:occurrence_id_type -> Type0)
  (valid_at:event_sequence occurrence_id_type local_value_type
    external_value_type generator_value_type ->
    event occurrence_id_type local_value_type external_value_type
      generator_value_type -> prop)
  (#events:event_sequence occurrence_id_type local_value_type
    external_value_type generator_value_type)
  (h:history valid_at events)
  (e:event occurrence_id_type local_value_type external_value_type generator_value_type)
  (proof_event_valid_at_previous:squash (valid_at events e))
  : Tot (history valid_at (events @ [e]))
  =
  match e with
  | LocalCompletion local -> LocalStep h local proof_event_valid_at_previous
  | ExternalCompletion external -> ExternalStep h external proof_event_valid_at_previous
  | GeneratorCompletion generator ->
      GeneratorStep h generator proof_event_valid_at_previous

let state_at
  (#input_type:Type0)
  (#dag_type:(input_type -> Type0))
  (#occurrence_id_type:eqtype)
  (#local_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#external_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#generator_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#rep_type:(x:input_type -> dag_type x -> Type0))
  (initial_state:initial_state_type input_type dag_type rep_type)
  (accept_event:event_transition_type input_type dag_type occurrence_id_type
    local_value_type external_value_type generator_value_type rep_type)
  (x:input_type)
  (dag:dag_type x)
  (valid_at:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> prop)
  (s:rep_type x dag)
  (events:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag))
  (h:history valid_at events)
  : GTot prop
  =
  s == state_after_history initial_state accept_event x dag valid_at events h

let initial_state_empty_history
  (#input_type:Type0)
  (#dag_type:(input_type -> Type0))
  (#occurrence_id_type:eqtype)
  (#local_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#external_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#generator_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#rep_type:(x:input_type -> dag_type x -> Type0))
  (initial_state:initial_state_type input_type dag_type rep_type)
  (accept_event:event_transition_type input_type dag_type occurrence_id_type
    local_value_type external_value_type generator_value_type rep_type)
  (x:input_type)
  (dag:dag_type x)
  (valid_at:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> prop)
  : Lemma (state_after_history initial_state accept_event x dag valid_at []
      (EmptyHistory <: history valid_at [])
      == initial_state x dag)
  =
  FStar.Pervasives.reveal_opaque (`%state_after_history)
    (state_after_history #input_type #dag_type #occurrence_id_type
      #local_value_type #external_value_type #generator_value_type #rep_type
      initial_state accept_event x dag valid_at);
  FStar.Pervasives.reveal_opaque (`%fold_updates)
    (fold_updates #input_type #dag_type #occurrence_id_type #local_value_type
      #external_value_type #generator_value_type #rep_type accept_event);
  ()

let initial_state_at_empty_history
  (#input_type:Type0)
  (#dag_type:(input_type -> Type0))
  (#occurrence_id_type:eqtype)
  (#local_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#external_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#generator_value_type:(x:input_type -> dag_type x -> occurrence_id_type -> Type0))
  (#rep_type:(x:input_type -> dag_type x -> Type0))
  (initial_state:initial_state_type input_type dag_type rep_type)
  (accept_event:event_transition_type input_type dag_type occurrence_id_type
    local_value_type external_value_type generator_value_type rep_type)
  (x:input_type)
  (dag:dag_type x)
  (valid_at:event_sequence occurrence_id_type (local_value_type x dag)
    (external_value_type x dag) (generator_value_type x dag) ->
    event occurrence_id_type (local_value_type x dag) (external_value_type x dag)
      (generator_value_type x dag) -> prop)
  : Lemma (state_at initial_state accept_event x dag valid_at
      (initial_state x dag)
      [] (EmptyHistory <: history valid_at []))
  =
  FStar.Pervasives.reveal_opaque (`%state_at)
    (state_at #input_type #dag_type #occurrence_id_type #local_value_type
      #external_value_type #generator_value_type #rep_type initial_state
      accept_event x dag valid_at);
  initial_state_empty_history initial_state accept_event x dag valid_at
// }}}
