module WorkflowV2.GenerationExample

open FStar.List.Tot
open WorkflowV2.Kernel
open WorkflowV2.Graph
open WorkflowV2.GraphCodec
open WorkflowV2.Identity

// A fully first-order, runtime-shaped example: input n creates n local nodes
// in a chain. The topology and plan are ordinary F* values returned by the
// same generator callback used by the kernel.
// These numeric sequences happen to spell ASCII labels under a host
// convention; proofs treat them only as raw identity tokens and assume no
// text conversion law.
let example_nat_name : identity_token =
  [118; 50; 46; 101; 120; 97; 109; 112; 108; 101; 46; 110; 97; 116]

let example_nat_indexed_name : identity_token =
  [118; 50; 46; 101; 120; 97; 109; 112; 108; 101; 46; 110; 97; 116; 45;
   105; 110; 100; 101; 120; 101; 100]

let example_increment_name : identity_token =
  [118; 50; 46; 101; 120; 97; 109; 112; 108; 101; 46; 105; 110; 99; 114;
   101; 109; 101; 110; 116]

let example_graph_name : identity_token =
  [118; 50; 46; 101; 120; 97; 109; 112; 108; 101; 46; 103; 114; 97; 112; 104]

let example_generator_name : identity_token =
  [118; 50; 46; 101; 120; 97; 109; 112; 108; 101; 46; 114; 101; 112; 101;
   97; 116; 45; 105; 110; 99; 114; 101; 109; 101; 110; 116]

let example_metric_name : identity_token =
  [101; 120; 97; 109; 112; 108; 101; 46; 109; 101; 116; 114; 105; 99]

let nat_codec_id : codec_identity = {
  codec_name = example_nat_name;
  codec_version = 1;
  codec_build = [1]
}

let nat_encode (n:nat) : bytes = [n]

let nat_decode (wire:bytes) : option nat =
  match wire with
  | [n] -> Some n
  | _ -> None

let nat_codec : codec nat = {
  codec_id = nat_codec_id;
  encode = nat_encode;
  decode = nat_decode;
  roundtrip = (fun n -> ());
  canonical = (fun _ _ -> ())
}

let nat_indexed_codec_id : codec_identity = {
  codec_name = example_nat_indexed_name;
  codec_version = 1;
  codec_build = [1]
}

let nat_indexed_codec : indexed_codec nat (fun _ -> nat) = {
  indexed_codec_id = nat_indexed_codec_id;
  encode_indexed = (fun _ n -> nat_encode n);
  decode_indexed = (fun _ wire -> nat_decode wire);
  roundtrip_indexed = (fun _ n -> ());
  canonical_indexed = (fun _ _ _ -> ())
}

let increment_code : code_ref nat (fun _ -> nat) = {
  code_ref_id = {code_name=example_increment_name;
                 code_version=1; code_build=[1]};
  input_codec = nat_codec;
  output_codec = nat_indexed_codec;
  run = (fun n -> n + 1)
}

let increment_work : work nat (fun _ -> nat) = LocalWork increment_code

let increment_ref : durable_work_ref = durable_ref_of_work increment_work

let chain_codec_registry_unique (key:codec_identity)
  : Lemma (codec_identity_occurrences key
      [PlainCodec nat_codec; IndexedCodec nat_indexed_codec] <= 1) =
  if codec_identity_eq key nat_codec_id then
    (if codec_identity_eq key nat_indexed_codec_id then
       (codec_identity_eq_sound key nat_codec_id;
        codec_identity_eq_sound key nat_indexed_codec_id;
        assert (nat_codec_id <> nat_indexed_codec_id);
        ())
     else ())
  else ()

let chain_codec_registry : global_codec_registry = {
  global_codec_entries = [PlainCodec nat_codec; IndexedCodec nat_indexed_codec];
  global_codec_unique = chain_codec_registry_unique
}

let example_graph_codec : graph_codec nat (fun _ -> nat) = {
  graph_codec_id = {graph_codec_name=example_graph_name;
                   graph_codec_version=1; graph_codec_build=[1]};
  encode_graph = encode_graph_syntax;
  decode_graph = decode_graph_syntax;
  graph_roundtrip = graph_decode_encoding;
  graph_canonical = graph_decode_canonical
}

let chain_node (#x:nat) (key:nat) : graph_node nat x = {
  graph_node_key = key;
  graph_node_work = increment_ref;
  graph_node_input = if key = 0 then RootWire else OutputWire (key - 1)
}

let rec chain_nodes_from (#x:nat) (key count:nat)
  : Tot (list (graph_node nat x)) (decreases count) =
  match count with
  | 0 -> []
  | _ -> chain_node key :: chain_nodes_from (key + 1) (count - 1)

let rec chain_plan_from (key count:nat)
  : Tot graph_allocation_plan (decreases count) =
  match count with
  | 0 -> []
  | _ ->
      {allocated_key=key;
       allocated_values={expansion_fuel=0; charge_allocation=0}} ::
      chain_plan_from (key + 1) (count - 1)

let rec wire_refs_before (#i:Type0) (#x:i)
    (wire:wire i x) (key:node_key) : bool =
  match wire with
  | RootWire -> true
  | OutputWire dependency -> dependency < key
  | ConstantWire _ _ -> true
  | PairWire left right ->
      wire_refs_before left key && wire_refs_before right key
  | FstWire pair -> wire_refs_before pair key
  | SndWire pair -> wire_refs_before pair key

let rec all_node_refs_before (#i:Type0) (#x:i)
    (nodes:list (graph_node i x)) : bool =
  match nodes with
  | [] -> true
  | node::tail ->
      wire_refs_before node.graph_node_input node.graph_node_key &&
      all_node_refs_before tail

let chain_node_reference_is_prior (#x:nat) (key:nat)
  : Lemma (wire_refs_before (chain_node #x key).graph_node_input key == true) =
  if key = 0 then () else assert (key - 1 < key)

let rec chain_edges_point_back (#x:nat) (key count:nat)
  : Lemma (ensures
      (all_node_refs_before (chain_nodes_from #x key count) == true))
  (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_node_reference_is_prior #x key;
      chain_edges_point_back #x (key + 1) (count - 1)

let chain_descriptor (x count:nat) : graph_desc nat (fun _ -> nat) x = {
  graph_nodes = chain_nodes_from #x 0 count;
  graph_output_wire = if count = 0 then RootWire else OutputWire (count - 1)
}

let chain_root : nat = 0

let chain_generator : generator_ref nat (fun _ -> nat) = {
  generator_ref_id = {generator_name=example_generator_name;
                      generator_version=1; generator_build=[1]};
  generator_input_codec = nat_codec;
  generator_output_codec = example_graph_codec;
  generate_graph = (fun count _metric _parent -> {
    generated_descriptor = chain_descriptor count count;
    generated_child_plan = chain_plan_from 0 count
  })
}

let chain_generator_work : work nat (fun _ -> nat) =
  GenerateWork chain_generator

let chain_increment_generator_refs_distinct ()
  : Lemma (durable_work_ref_eq (durable_ref_of_work increment_work)
      (durable_ref_of_work chain_generator_work) == false) =
  assert (work_identity_eq
    (durable_ref_of_work increment_work).durable_kind
    (durable_ref_of_work chain_generator_work).durable_kind == false);
  ()

let chain_work_registry_unique (key:durable_work_ref)
  : Lemma (durable_ref_occurrences key
      [PackedWork increment_work; PackedWork chain_generator_work] <= 1) =
  if durable_work_ref_eq key (durable_ref_of_work increment_work) then
    (if durable_work_ref_eq key (durable_ref_of_work chain_generator_work) then
       (durable_work_ref_eq_sound key (durable_ref_of_work increment_work);
        durable_work_ref_eq_sound key (durable_ref_of_work chain_generator_work);
        chain_increment_generator_refs_distinct ();
        assert False;
        ())
     else ())
  else ()

// Pin both the local node and the exact graph generator in the example.
let chain_work_registry : global_work_registry = {
  global_work_entries =
    [PackedWork increment_work; PackedWork chain_generator_work];
  global_registry_unique = chain_work_registry_unique
}

let chain_registry : pinned_registry_bundle = {
  // Placeholder only: the legacy example has not yet been projected to the
  // A03 canonical manifest. P0 must use its exact manifest bytes.
  bundle_identity = registry_identity_of_bytes [0];
  bundle_work_registry = chain_work_registry;
  bundle_codec_registry = chain_codec_registry
}

let chain_increment_member : packed_work_membership
    (PackedWork increment_work) chain_work_registry.global_work_entries =
  PackedWorkMemberHead

let chain_generator_member : packed_work_membership
    (PackedWork chain_generator_work) chain_work_registry.global_work_entries =
  PackedWorkMemberTail (PackedWorkMemberHead)

let chain_work_resolves_exactly ()
  : Lemma (resolve_global_work chain_work_registry increment_ref ==
           Some (PackedWork increment_work)) = ()

let rec chain_node_count (#x:nat) (key count:nat)
  : Lemma (ensures (length (chain_nodes_from #x key count) == count))
  (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_node_count #x (key + 1) (count - 1);
      assert (count - 1 + 1 == count)

let rec chain_plan_count (key count:nat)
  : Lemma (ensures (length (chain_plan_from key count) == count))
  (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_plan_count (key + 1) (count - 1);
      assert (count - 1 + 1 == count)

let rec chain_keys_match (#x:nat) (key count:nat)
  : Lemma (ensures (node_keys (chain_nodes_from #x key count) ==
                    allocation_keys (chain_plan_from key count)))
  (decreases count) =
  match count with
  | 0 -> ()
  | _ -> chain_keys_match #x (key + 1) (count - 1)

let chain_plan_keys_equal_node_keys (#x:nat) (count:nat)
  : Lemma (node_keys (chain_nodes_from #x 0 count) ==
           allocation_keys (chain_plan_from 0 count)) =
  chain_keys_match #x 0 count

let rec chain_range_excludes (#x:nat) (key start count:nat)
  : Lemma (requires (key < start))
      (ensures (nat_mem
        (node_keys (chain_nodes_from #x start count)) key == false))
  (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      assert (key <> start);
      chain_range_excludes #x key (start + 1) (count - 1);
      assert (nat_mem
        (start :: node_keys
          (chain_nodes_from #x (start + 1) (count - 1))) key ==
        (key = start ||
         nat_mem (node_keys
           (chain_nodes_from #x (start + 1) (count - 1))) key));
      ()

let rec chain_graph_keys_unique (#x:nat) (start count:nat)
  : Lemma (ensures
      (nat_list_unique (node_keys (chain_nodes_from #x start count)) == true))
  (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_graph_keys_unique #x (start + 1) (count - 1);
      chain_range_excludes #x start (start + 1) (count - 1);
      ()

let rec chain_allocation_nodes_valid (#x:nat) (start count:nat)
  : Lemma (ensures (allocation_node_valid chain_registry
      (chain_nodes_from #x start count) (chain_plan_from start count) == true))
  (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_work_resolves_exactly ();
      chain_allocation_nodes_valid #x (start + 1) (count - 1)

let rec chain_child_fuel_zero (#x:nat) (start count:nat)
  : Lemma (ensures (child_generator_fuel chain_registry
      (chain_nodes_from #x start count) (chain_plan_from start count) == 0))
  (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_work_resolves_exactly ();
      chain_child_fuel_zero #x (start + 1) (count - 1)

let rec chain_charge_pool_zero (#x:nat) (start count:nat)
  : Lemma (ensures (graph_charge_pool chain_registry
      (chain_nodes_from #x start count) (chain_plan_from start count) == 0))
  (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_work_resolves_exactly ();
      chain_charge_pool_zero #x (start + 1) (count - 1)

let chain_allocation_plan_wf (#x:nat) (count:nat)
    (parent:generation_allocation)
  : Lemma (allocation_plan_wf chain_registry parent.expansion_fuel
      parent.charge_allocation (chain_descriptor x count)
      (chain_plan_from 0 count)) =
  chain_plan_keys_equal_node_keys #x count;
  chain_graph_keys_unique #x 0 count;
  chain_allocation_nodes_valid #x 0 count;
  chain_child_fuel_zero #x 0 count;
  chain_charge_pool_zero #x 0 count

let chain_graph_roundtrip (count:nat)
  : Lemma (decode_graph_syntax chain_root
      (encode_graph_syntax chain_root (chain_descriptor chain_root count)) ==
      Some (chain_descriptor chain_root count)) =
  graph_decode_encoding chain_root (chain_descriptor chain_root count)

let chain_generator_is_input_shaped (count:nat)
  : Lemma (length
      ((chain_generator.generate_graph count
        {charge_metric_name=example_metric_name; charge_metric_version=1;
         charge_metric_build=[1]}
        {expansion_fuel=0; charge_allocation=0}).generated_descriptor.graph_nodes)
      == count) =
  chain_node_count #count 0 count
