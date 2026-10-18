module WorkflowV1.Expansion
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.Work


type child_manifest_entry = {
  ordinal:nat;
  source_id:plan_id;
  resolved_id:plan_id;
  resolved_digest:digest;
  argument_bytes:bytes;
  argument_digest:digest
}

type expand_prepared = {
  prepared_at:occurrence;
  prepared_input:bytes;
  prepared_input_digest:digest;
  prepared_snapshot:bytes;
  prepared_snapshot_digest:digest;
  prepared_expand_id:code_id;
  prepared_expand_version:nat;
  prepared_expand_build:digest;
  prepared_decoder_id:code_id;
  prepared_decoder_version:nat;
  prepared_decoder_build:digest;
  prepared_checker_id:code_id;
  prepared_checker_version:nat;
  prepared_checker_build:digest;
  prepared_registry_id:code_id;
  prepared_registry_version:nat;
  prepared_registry_build:digest;
  prepared_join_id:code_id;
  prepared_join_version:nat;
  prepared_join_build:digest;
  prepared_maximum_children:nat;
  prepared_depth:nat;
  prepared_nodes:nat
}

type expand_committed = {
  committed_at:occurrence;
  committed_input:bytes;
  committed_input_digest:digest;
  committed_snapshot:bytes;
  committed_snapshot_digest:digest;
  committed_decision:bytes;
  committed_decision_digest:digest;
  committed_direct_result:option bytes;
  committed_direct_result_digest:option digest;
  committed_manifest:list child_manifest_entry;
  committed_child_depth:nat;
  committed_nodes_after:nat
}

type expansion_completed = {
  expansion_completed_at:occurrence;
  expansion_result:bytes
}

// The journal codec projects a typed ExpandChoice to these durable facts.
// A concrete registry/decision codec supplies and proves this contract.
type generated_child = {
  generated_source_id:plan_id;
  generated_argument_bytes:bytes
}

type generated_decision =
  | GeneratedReturn : bytes -> generated_decision
  | GeneratedChildren : list generated_child -> generated_decision

type resolved_child_identity = {
  resolved_source_id:plan_id;
  resolved_plan_id:plan_id;
  resolved_plan_bytes:bytes;
  resolved_plan_digest:digest
}

noeq type generation_contract = {
  expand_id:code_id;
  expand_version:nat;
  expand_build:digest;
  decoder_id:code_id;
  decoder_version:nat;
  decoder_build:digest;
  registry_id:code_id;
  registry_version:nat;
  registry_build:digest;
  checker_id:code_id;
  checker_version:nat;
  checker_build:digest;
  join_id:code_id;
  join_version:nat;
  join_build:digest;
  hash_bytes:bytes -> Tot digest;
  decode_decision:expand_prepared -> bytes -> Tot (option generated_decision);
  encode_decision:expand_prepared -> generated_decision -> Tot bytes;
  decode_canonical:(p:expand_prepared) -> (wire:bytes)
    -> (d:generated_decision) -> Lemma
       (decode_decision p wire == Some d ==> encode_decision p d == wire);
  choice_origin:expand_prepared -> generated_decision -> prop;
  decode_origin_sound:(p:expand_prepared) -> (wire:bytes)
    -> (d:generated_decision)
    -> Lemma (decode_decision p wire == Some d ==> choice_origin p d);
  check_direct_result:expand_prepared -> bytes -> Tot bool;
  direct_result_valid:expand_prepared -> bytes -> prop;
  direct_result_sound:(p:expand_prepared) -> (wire:bytes)
    -> Lemma (check_direct_result p wire == true ==>
       direct_result_valid p wire);
  check_allowed:expand_prepared -> list generated_child -> Tot bool;
  allowed:expand_prepared -> list generated_child -> prop;
  checker_sound:(p:expand_prepared) -> (children:list generated_child)
    -> Lemma (check_allowed p children == true ==> allowed p children);
  check_argument:expand_prepared -> plan_id -> bytes -> Tot bool;
  argument_valid:expand_prepared -> plan_id -> bytes -> prop;
  argument_sound:(p:expand_prepared) -> (source:plan_id) -> (wire:bytes)
    -> Lemma (check_argument p source wire == true ==> argument_valid p source wire);
  resolve:expand_prepared -> plan_id -> Tot (option resolved_child_identity);
  resolve_sound:(p:expand_prepared) -> (source:plan_id)
    -> (resolved:resolved_child_identity)
    -> Lemma (resolve p source == Some resolved ==>
       resolved.resolved_source_id == source /\
       resolved.resolved_plan_id == hash_bytes resolved.resolved_plan_bytes /\
       resolved.resolved_plan_digest == hash_bytes resolved.resolved_plan_bytes);
  resolved_work_identity:expand_prepared -> resolved_child_identity -> prop;
  resolved_work_sound:(p:expand_prepared) -> (source:plan_id)
    -> (resolved:resolved_child_identity)
    -> Lemma (resolve p source == Some resolved ==>
       resolved_work_identity p resolved)
}


let rec manifest_ordinals_from (next:nat) (entries:list child_manifest_entry)
  : Tot bool (decreases entries) =
  match entries with
  | [] -> true
  | entry::rest -> entry.ordinal = next &&
      manifest_ordinals_from (next + 1) rest

let valid_manifest_shape (maximum depth nodes:nat)
    (entries:list child_manifest_entry) : bool =
  length entries <= maximum && length entries <= nodes &&
  (match entries with | [] -> true | _::_ -> depth > 0) &&
  manifest_ordinals_from 0 entries

let rec generated_manifest_matches (g:generation_contract)
    (p:expand_prepared) (next:nat) (choices:list generated_child)
    (entries:list child_manifest_entry) : Tot bool (decreases choices) =
  match choices, entries with
  | [], [] -> true
  | choice::choice_tail, entry::entry_tail ->
      let resolved = g.resolve p choice.generated_source_id in
      choice.generated_source_id = entry.source_id &&
      choice.generated_argument_bytes = entry.argument_bytes &&
      entry.ordinal = next &&
      g.check_argument p choice.generated_source_id
        choice.generated_argument_bytes &&
      entry.argument_digest = g.hash_bytes choice.generated_argument_bytes &&
      (match resolved with
       | None -> false
       | Some identity ->
           identity.resolved_source_id = choice.generated_source_id &&
           identity.resolved_plan_id = entry.resolved_id &&
           identity.resolved_plan_digest = entry.resolved_digest &&
           identity.resolved_plan_digest = g.hash_bytes identity.resolved_plan_bytes &&
           generated_manifest_matches g p (next + 1) choice_tail entry_tail)
  | _, _ -> false

let rec resolved_manifest_identity (g:generation_contract)
    (p:expand_prepared) (choices:list generated_child)
    (entries:list child_manifest_entry) : prop =
  match choices, entries with
  | [], [] -> True
  | choice::choice_tail, entry::entry_tail ->
      (match g.resolve p choice.generated_source_id with
       | None -> False
       | Some identity ->
           identity.resolved_source_id == choice.generated_source_id /\
           identity.resolved_plan_id == entry.resolved_id /\
           identity.resolved_plan_digest == entry.resolved_digest /\
           g.resolved_work_identity p identity /\
           resolved_manifest_identity g p choice_tail entry_tail)
  | _, _ -> False

let generation_is_pinned (g:generation_contract) (p:expand_prepared) : bool =
  p.prepared_expand_id = g.expand_id &&
  p.prepared_expand_version = g.expand_version &&
  p.prepared_expand_build = g.expand_build &&
  p.prepared_decoder_id = g.decoder_id &&
  p.prepared_decoder_version = g.decoder_version &&
  p.prepared_decoder_build = g.decoder_build &&
  p.prepared_registry_id = g.registry_id &&
  p.prepared_registry_version = g.registry_version &&
  p.prepared_registry_build = g.registry_build &&
  p.prepared_checker_id = g.checker_id &&
  p.prepared_checker_version = g.checker_version &&
  p.prepared_checker_build = g.checker_build &&
  p.prepared_join_id = g.join_id &&
  p.prepared_join_version = g.join_version &&
  p.prepared_join_build = g.join_build &&
  p.prepared_input_digest = g.hash_bytes p.prepared_input &&
  p.prepared_snapshot_digest = g.hash_bytes p.prepared_snapshot

let valid_generation (g:generation_contract) (p:expand_prepared)
    (c:expand_committed) : bool =
  if not (generation_is_pinned g p) ||
     c.committed_input <> p.prepared_input ||
     c.committed_input_digest <> p.prepared_input_digest ||
     c.committed_snapshot <> p.prepared_snapshot ||
     c.committed_snapshot_digest <> p.prepared_snapshot_digest ||
     c.committed_decision_digest <> g.hash_bytes c.committed_decision
  then false else
  match g.decode_decision p c.committed_decision with
  | None -> false
  | Some decision ->
      g.encode_decision p decision = c.committed_decision &&
      (match decision with
       | GeneratedReturn output ->
           c.committed_direct_result = Some output &&
           c.committed_direct_result_digest = Some (g.hash_bytes output) &&
           g.check_direct_result p output &&
           c.committed_manifest = []
       | GeneratedChildren choices ->
           c.committed_direct_result = None &&
           c.committed_direct_result_digest = None &&
           g.check_allowed p choices &&
           generated_manifest_matches g p 0 choices c.committed_manifest)

let generation_semantics (g:generation_contract) (p:expand_prepared)
    (c:expand_committed) : prop =
  generation_is_pinned g p /\
  c.committed_input == p.prepared_input /\
  c.committed_input_digest == p.prepared_input_digest /\
  c.committed_snapshot == p.prepared_snapshot /\
  c.committed_snapshot_digest == p.prepared_snapshot_digest /\
  c.committed_decision_digest == g.hash_bytes c.committed_decision /\
  (exists decision. g.decode_decision p c.committed_decision == Some decision /\
    g.encode_decision p decision == c.committed_decision /\
    g.choice_origin p decision /\
    (match decision with
     | GeneratedReturn output ->
         c.committed_direct_result == Some output /\
         c.committed_direct_result_digest == Some (g.hash_bytes output) /\
         g.direct_result_valid p output /\
         c.committed_manifest == []
     | GeneratedChildren children ->
         c.committed_direct_result == None /\
         c.committed_direct_result_digest == None /\
         g.allowed p children /\
         resolved_manifest_identity g p children c.committed_manifest /\
         generated_manifest_matches g p 0 children c.committed_manifest))
