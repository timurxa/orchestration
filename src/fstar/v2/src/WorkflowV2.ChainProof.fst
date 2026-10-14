module WorkflowV2.ChainProof

open FStar.List.Tot
open WorkflowV2.Kernel
open WorkflowV2.Graph
open WorkflowV2.Identity
open WorkflowV2.GenerationExample
open FStar.Classical

let chain_expected_output_wire (#x:nat) (n:nat) : wire nat x =
  if n = 0 then RootWire else OutputWire (n - 1)

noeq type chain_evidence (x:nat) (n:nat) = {
  chain_ports:port_context nat x;
  chain_sequence:typed_node_sequence chain_registry nat x
    chain_ports (chain_nodes_from #x 0 n);
  chain_output:wiring chain_registry nat x chain_ports (fun _ -> nat);
  chain_output_shape:squash
    (chain_output.wiring_syntax == chain_expected_output_wire #x n)
}

let chain_last_output (#x:nat) (#ports:port_context nat x) (key:nat)
  : wiring chain_registry nat x
      (extend ports key (fun _ -> nat)) (fun _ -> nat) =
  let r:port_ref nat x (extend ports key (fun _ -> nat)) (fun _ -> nat) =
    PortRef key (HerePort #(port_env nat x ports)
      #ports.port_context_shape #key #(fun _ -> nat)) in
  port_wiring r

let chain_last_output_is_output (#x:nat) (#ports:port_context nat x)
    (key:nat)
  : Lemma ((chain_last_output #x #ports key).wiring_syntax == OutputWire key) = ()

let rec chain_nodes_snoc (#x:nat) (start count:nat)
  : Lemma (ensures
      (chain_nodes_from #x start (count + 1) ==
       append_one (chain_nodes_from #x start count)
         (chain_node #x (start + count))))
      (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
    chain_nodes_snoc #x (start + 1) (count - 1)

let rec chain_key_after_prefix (#x:nat) (start count:nat)
  : Lemma (ensures
      (nat_mem (node_keys (chain_nodes_from #x start count))
        (start + count) == false))
      (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      assert (start <> start + count);
      chain_key_after_prefix #x (start + 1) (count - 1)

let chain_key_fresh (#x:nat) (n:nat)
  : Lemma (ensures
      (not (nat_mem (node_keys (chain_nodes_from #x 0 n)) n) == true)) =
  chain_key_after_prefix #x 0 n

let chain_key_fresh_proof (#x:nat) (n:nat)
  : squash (not (nat_mem (node_keys (chain_nodes_from #x 0 n)) n)) =
  chain_key_fresh #x n;
  ()

let rec build_chain (x:nat) (n:nat)
  : Tot (chain_evidence x n) (decreases n) =
  match n with
  | 0 -> {
      chain_ports=root_port nat x;
      chain_sequence=TypedNodesEmpty;
      chain_output=root_wiring x;
      chain_output_shape=()
    }
  | _ ->
    let prior = build_chain x (n - 1) in
    let key = n - 1 in
    chain_nodes_snoc #x 0 (n - 1);
    assert (n - 1 + 1 == n);
    chain_key_fresh #x key;
    assert (n > 0);
    assert (prior.chain_output.wiring_syntax ==
      (if key = 0 then RootWire else OutputWire (key - 1)));
    chain_last_output_is_output #x #prior.chain_ports key;
    assert (chain_node #x key == {
      graph_node_key=key;
      graph_node_work=durable_ref_of_work increment_work;
      graph_node_input=prior.chain_output.wiring_syntax
    });
    {
      chain_ports=extend prior.chain_ports key (fun _ -> nat);
      chain_sequence=TypedNodesSnoc prior.chain_ports
        (chain_nodes_from #x 0 key) prior.chain_sequence key
        (chain_key_fresh_proof #x key)
        increment_work chain_increment_member prior.chain_output;
      chain_output=chain_last_output #x #prior.chain_ports key;
      chain_output_shape=()
    }

let chain_output_syntax (x n:nat)
  : Lemma ((build_chain x n).chain_output.wiring_syntax ==
      chain_expected_output_wire #x n) =
  (build_chain x n).chain_output_shape

let chain_typed_graph_witness (x:nat)
  : typed_graph_witness chain_registry nat (fun _ -> nat) x
      (interpret_graph x (chain_descriptor x x)) =
  let evidence = build_chain x x in
  interpret_graph_vertices x (chain_descriptor x x);
  interpret_graph_order x (chain_descriptor x x);
  interpret_graph_label x (chain_descriptor x x);
  interpret_graph_input x (chain_descriptor x x);
  chain_output_syntax x x;
  TypedGraphWitness evidence.chain_sequence evidence.chain_output
    () () () () ()

let rec chain_find_node_from (#x:nat) (start count key:nat)
  : Lemma (requires (start <= key /\ key < start + count))
      (ensures (find_node (chain_nodes_from #x start count) key ==
                Some (chain_node #x key)))
      (decreases count) =
  match count with
  | 0 -> assert False
  | _ ->
      if key = start then ()
      else (
        assert (start < key);
        chain_find_node_from #x (start + 1) (count - 1) key)

let rec chain_member_last_from (#x:nat) (start count:nat)
  : Lemma (requires count > 0)
      (ensures (nat_mem
        (node_keys (chain_nodes_from #x start count))
        (start + count - 1) == true))
      (decreases count) =
  match count with
  | 0 -> assert False
  | _ ->
      if count = 1 then ()
      else (
        assert (count > 1);
        assert (count - 1 > 0);
        chain_member_last_from #x (start + 1) (count - 1))

let chain_member_last (#x:nat) (count:nat)
  : Lemma (requires count > 0)
      (ensures (nat_mem (node_keys (chain_nodes_from #x 0 count))
                (count - 1) == true)) =
  chain_member_last_from #x 0 count

let rec chain_topology_from (#x:nat) (graph_count start count:nat)
    (prior:list node_key)
  : Lemma (requires (start + count == graph_count /\
                     prior == node_keys (chain_nodes_from #x 0 start)))
      (ensures (dag_inputs_are_topological
        (node_keys (chain_nodes_from #x start count))
        (interpret_graph x (chain_descriptor x graph_count)) prior))
      (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_find_node_from #x 0 graph_count start;
      if start = 0 then () else chain_member_last #x start;
      chain_nodes_snoc #x 0 start;
      node_keys_append_one (chain_nodes_from #x 0 start) (chain_node #x start);
      chain_topology_from #x graph_count (start + 1) (count - 1)
        (prior @ [start])

let chain_graph_topological (x:nat)
  : Lemma (dag_inputs_are_topological
      (interpret_graph x (chain_descriptor x x)).topological_order
      (interpret_graph x (chain_descriptor x x)) []) =
  chain_topology_from #x x 0 x []

let rec find_node_membership (#i:Type0) (#x:i)
    (nodes:list (graph_node i x)) (key:node_key)
  : Lemma (ensures (nat_mem (node_keys nodes) key ==
      (match find_node nodes key with | None -> false | Some _ -> true)))
      (decreases nodes) =
  match nodes with
  | [] -> ()
  | head::tail ->
      if key = head.graph_node_key then ()
      else find_node_membership tail key

let nat_mem_add_head (keys:list node_key) (head key:node_key)
  : Lemma (requires (nat_mem keys key == true))
      (ensures (nat_mem (head::keys) key == true)) = ()

let rec all_members_weaken_head (keys superset:list node_key)
    (head:node_key)
  : Lemma (requires (all_members keys superset == true))
      (ensures (all_members keys (head::superset) == true))
      (decreases keys) =
  match keys with
  | [] -> ()
  | key::tail ->
      assert (nat_mem superset key == true);
      nat_mem_add_head superset head key;
      all_members_weaken_head tail superset head

let rec all_members_refl (keys:list node_key)
  : Lemma (ensures (all_members keys keys == true)) (decreases keys) =
  match keys with
  | [] -> ()
  | head::tail ->
      assert (nat_mem (head::tail) head == true);
      all_members_refl tail;
      all_members_weaken_head tail tail head;
      assert (all_members tail (head::tail) == true)

let same_nat_set_refl (keys:list node_key)
  : Lemma (same_nat_set keys keys == true) =
  all_members_refl keys

let chain_output_refs_member (x:nat)
  : Lemma (refs_are_members
      (wire_output_refs (chain_descriptor x x).graph_output_wire)
      (node_keys (chain_nodes_from #x 0 x)) == true) =
  if x = 0 then () else chain_member_last #x x

let chain_domain_label_at (x key:nat)
  : Lemma (nat_mem (node_keys (chain_nodes_from #x 0 x)) key ==
      (match (interpret_graph x (chain_descriptor x x)).label key
       with | None -> false | Some _ -> true)) =
  find_node_membership (chain_nodes_from #x 0 x) key;
  interpret_graph_label x (chain_descriptor x x);
  ()

let chain_domain_label (x:nat)
  : Lemma (forall key.
      nat_mem (node_keys (chain_nodes_from #x 0 x)) key ==
      (match (interpret_graph x (chain_descriptor x x)).label key
       with | None -> false | Some _ -> true)) =
  FStar.Classical.forall_intro (chain_domain_label_at x)

let chain_domain_input_at (x key:nat)
  : Lemma (nat_mem (node_keys (chain_nodes_from #x 0 x)) key ==
      (match (interpret_graph x (chain_descriptor x x)).input_wire key
       with | None -> false | Some _ -> true)) =
  find_node_membership (chain_nodes_from #x 0 x) key;
  interpret_graph_input x (chain_descriptor x x);
  ()

let chain_domain_input (x:nat)
  : Lemma (forall key.
      nat_mem (node_keys (chain_nodes_from #x 0 x)) key ==
      (match (interpret_graph x (chain_descriptor x x)).input_wire key
       with | None -> false | Some _ -> true)) =
  FStar.Classical.forall_intro (chain_domain_input_at x)

let chain_graph_wf (x:nat)
  : Lemma (graph_wf chain_registry x (chain_descriptor x x)) =
  let d = interpret_graph x (chain_descriptor x x) in
  chain_graph_keys_unique #x 0 x;
  assert (nat_list_unique d.vertices == true);
  same_nat_set_refl d.vertices;
  assert (same_nat_set d.vertices d.topological_order == true);
  chain_domain_label x;
  assert (forall key.
    nat_mem d.vertices key ==
      (match d.label key with | None -> false | Some _ -> true));
  chain_domain_input x;
  assert (forall key.
    nat_mem d.vertices key ==
      (match d.input_wire key with | None -> false | Some _ -> true));
  chain_graph_topological x;
  assert (dag_inputs_are_topological d.topological_order d [] == true);
  chain_output_refs_member x;
  assert (refs_are_members (wire_output_refs d.output_wire) d.vertices == true);
  let witness = chain_typed_graph_witness x in
  FStar.Classical.exists_intro
    (fun (_:typed_graph_witness chain_registry nat (fun _ -> nat) x d) -> True)
    witness;
  ()

let rec allocation_nodes_valid_at (#x:nat) (start count:nat)
  : Lemma (ensures (allocation_node_valid chain_registry
      (chain_nodes_from #x start count) (chain_plan_from start count) == true))
      (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_work_resolves_exactly ();
      allocation_nodes_valid_at #x (start + 1) (count - 1)

let rec child_generator_fuel_zero_at (#x:nat) (start count:nat)
  : Lemma (ensures (child_generator_fuel chain_registry
      (chain_nodes_from #x start count) (chain_plan_from start count) == 0))
      (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_work_resolves_exactly ();
      child_generator_fuel_zero_at #x (start + 1) (count - 1)

let rec graph_charge_pool_zero_at (#x:nat) (start count:nat)
  : Lemma (ensures (graph_charge_pool chain_registry
      (chain_nodes_from #x start count) (chain_plan_from start count) == 0))
      (decreases count) =
  match count with
  | 0 -> ()
  | _ ->
      chain_work_resolves_exactly ();
      graph_charge_pool_zero_at #x (start + 1) (count - 1)

let chain_allocation_plan_wf_at (x:nat) (parent:generation_allocation)
  : Lemma (allocation_plan_wf chain_registry
      parent.expansion_fuel parent.charge_allocation
      (chain_descriptor x x) (chain_plan_from 0 x)) =
  chain_keys_match #x 0 x;
  chain_graph_keys_unique #x 0 x;
  allocation_nodes_valid_at #x 0 x;
  child_generator_fuel_zero_at #x 0 x;
  graph_charge_pool_zero_at #x 0 x

let chain_generator_admission :
    generator_admission chain_registry chain_generator = {
  generator_work_member = chain_generator_member;
  generator_result_valid = (fun x parent ->
    chain_graph_wf x;
    chain_allocation_plan_wf_at x parent)
}
