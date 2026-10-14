module WorkflowV2.Journal
open FStar.List.Tot
open WorkflowV2.Kernel
open WorkflowV2.Identity

// Event identity is the pair (run, contiguous sequence); payload records {{{1
type run_identity = {
  run_name:string;
  run_instance:nat
}

type event_header = {
  event_sequence:nat;
  event_run:run_identity;
  event_schema_version:nat
}

type graph_occurrence = {
  graph_run:run_identity;
  graph_path:list nat
}

type node_occurrence = {
  node_graph:graph_occurrence;
  node_key:nat
}

type call_key = node_occurrence

// One allocation record per graph node. The journal stores the graph-level
// plan once; replay derives the fuel and charge ledgers from these records.
type occurrence_allocation = {
  allocation_at:node_occurrence;
  allocation_values:generation_allocation
}

type allocation_plan = list occurrence_allocation

type artifact_ref = {
  artifact_identity:string;
  artifact_version:nat;
  artifact_digest:digest;
  artifact_codec:codec_identity;
  artifact_location:bytes
}

type run_started = {
  started_registry:registry_identity;
  started_root_input_codec:codec_identity;
  started_root_input:bytes;
  started_root_graph_codec:graph_codec_identity;
  started_root_graph:bytes;
  started_budget:run_budget;
  started_allocations:allocation_plan
}

type graph_committed = {
  committed_generator:node_occurrence;
  committed_graph_bytes:bytes;
  committed_allocations:allocation_plan
}

type node_completed = {
  completed_at:node_occurrence;
  completed_output:bytes;
  completed_artifacts:list artifact_ref
}

type call_intent = {
  intent_key:call_key;
  intent_resume_data:bytes
}

type call_outcome = {
  outcome_key:call_key;
  outcome_output:bytes;
  outcome_evidence:bytes;
  outcome_charge:nat;
  outcome_artifacts:list artifact_ref
}

// Event/action vocabulary and open replay boundary {{{1
type event_body =
  | RunStarted:run_started -> event_body
  | GraphCommitted:graph_committed -> event_body
  | NodeCompleted:node_completed -> event_body
  | CallIntent:call_intent -> event_body
  | CallOutcome:call_outcome -> event_body

type event = {
  event_metadata:event_header;
  event_contents:event_body
}

type action =
  | AppendEvent:event -> action
  | ExecuteLocal:node_occurrence -> action
  | GenerateGraph:node_occurrence -> action
  | DispatchOrResume:call_intent -> action

// Graph generation is pure and recomputable from committed input and the
// pinned generator plus its ledger-derived allocation, so there is no
// GenerationPrepared event or separate intent action.
// Expected domain failure is represented in the indexed output value, not as
// an event or node state.

// V2-04 will define replay and prove that journal history is the state. This
// vocabulary intentionally grants no transition authority by itself.
type journal = list event

noeq type abstract_state = {
  state_history:journal
}
