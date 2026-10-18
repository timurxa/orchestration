module WorkflowV2.Graph
open FStar.List.Tot
open WorkflowV2.Kernel
open WorkflowV2.Identity

// Graph model and finite-DAG interpretation {{{1
// A finite graph is represented by total vertex membership plus partial label
// and input-wire maps. The topological order is an explicit permutation of the
// vertices; its strict rank relation is the acyclicity witness.
noeq type finite_typed_dag (input:Type0) (output:input -> Type0) (x:input) = {
  vertices:list node_key;
  label:node_key -> option durable_work_ref;
  input_wire:node_key -> option (wire input x);
  output_wire:wire input x;
  topological_order:list node_key
}

let rec nat_mem (keys:list node_key) (key:node_key) : bool =
  match keys with
  | [] -> false
  | head::tail -> key = head || nat_mem tail key

let rec all_members (left right:list node_key) : bool =
  match left with
  | [] -> true
  | key::tail -> nat_mem right key && all_members tail right

let same_nat_set (left right:list node_key) : bool =
  all_members left right && all_members right left &&
  length left = length right

let rec nat_list_unique (keys:list node_key) : bool =
  match keys with
  | [] -> true
  | key::tail -> not (nat_mem tail key) && nat_list_unique tail

let rec node_keys (#i:Type0) (#x:i)
    (nodes:list (graph_node i x)) : list node_key =
  match nodes with
  | [] -> []
  | node::tail -> node.graph_node_key :: node_keys tail

let rec wire_output_refs (#i:Type0) (#x:i) (w:wire i x) : list node_key =
  match w with
  | RootWire -> []
  | OutputWire key -> [key]
  | ConstantWire _ _ -> []
  | PairWire left right -> wire_output_refs left @ wire_output_refs right
  | FstWire pair -> wire_output_refs pair
  | SndWire pair -> wire_output_refs pair

let rec refs_are_members (refs keys:list node_key) : bool =
  match refs with
  | [] -> true
  | key::tail -> nat_mem keys key && refs_are_members tail keys

let rec find_node (#i:Type0) (#x:i) (nodes:list (graph_node i x))
    (key:node_key) : option (graph_node i x) =
  match nodes with
  | [] -> None
  | node::tail ->
      if key = node.graph_node_key then Some node else find_node tail key

let interpret_graph (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x) : finite_typed_dag i o x = {
  vertices = node_keys g.graph_nodes;
  label = (fun key ->
    match find_node g.graph_nodes key with
    | None -> None
    | Some node -> Some node.graph_node_work);
  input_wire = (fun key ->
    match find_node g.graph_nodes key with
    | None -> None
    | Some node -> Some node.graph_node_input);
  output_wire = g.graph_output_wire;
  topological_order = node_keys g.graph_nodes
}

let interpret_graph_vertices (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x)
  : Lemma ((interpret_graph x g).vertices == node_keys g.graph_nodes) = ()

let interpret_graph_order (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x)
  : Lemma ((interpret_graph x g).topological_order ==
           node_keys g.graph_nodes) = ()

let interpret_graph_output (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x)
  : Lemma ((interpret_graph x g).output_wire == g.graph_output_wire) = ()

let dependent_fst (#a:Type0) (#b:a -> Type0)
    (pair:dtuple2 a b) : a =
  match pair with | Mkdtuple2 first _ -> first

let rec dag_inputs_are_topological (#i:Type0) (#o:i -> Type0) (#x:i)
    (order:list node_key) (d:finite_typed_dag i o x)
    (prior:list node_key) : bool =
  match order with
  | [] -> true
  | key::tail ->
      (match d.input_wire key with
       | None -> false
       | Some w ->
           refs_are_members (wire_output_refs w) prior &&
           dag_inputs_are_topological tail d (prior @ [key]))

// Graph isomorphism {{{1
// Isomorphism permits arbitrary key renaming and reordering of independent
// nodes; the well-formedness predicate below does not constrain key magnitude.
let rec wire_renamed (#i:Type0) (#x:i)
    (rename:node_key -> node_key) (left right:wire i x) : prop =
  match left, right with
  | RootWire, RootWire -> True
  | OutputWire l, OutputWire r -> rename l == r
  | ConstantWire lc lb, ConstantWire rc rb -> lc == rc /\ lb == rb
  | PairWire ll lr, PairWire rl rr ->
      wire_renamed rename ll rl /\ wire_renamed rename lr rr
  | FstWire l, FstWire r -> wire_renamed rename l r
  | SndWire l, SndWire r -> wire_renamed rename l r
  | _, _ -> False

let wire_label_isomorphic (#i:Type0) (#o:i -> Type0) (x:i)
    (left right:finite_typed_dag i o x) : prop =
  exists (rename:node_key -> node_key).
    (forall (key:node_key).
      nat_mem left.vertices key == true ==>
      nat_mem right.vertices (rename key) == true) /\
    (forall (l r:node_key).
      nat_mem left.vertices l == true /\
      nat_mem left.vertices r == true /\
      rename l == rename r ==> l == r) /\
    (forall (key:node_key).
      nat_mem right.vertices key == true ==>
      (exists (source:node_key).
        nat_mem left.vertices source == true /\ rename source == key)) /\
    (forall (key:node_key).
      nat_mem left.vertices key == true /\
      left.label key == right.label (rename key) /\
      (match left.input_wire key, right.input_wire (rename key) with
       | None, None -> True
       | Some lw, Some rw -> wire_renamed rename lw rw
       | _, _ -> False)) /\
    wire_renamed rename left.output_wire right.output_wire

// This relation compares only first-order wire syntax and durable labels. P1
// still needs a typed isomorphism transporting dependent port environments,
// resolved work signatures, and indexed constants along the key renaming.

// Concrete dependent port telescope and typed wire semantics {{{1
// A context stores both its environment type and a typed key sequence. Each
// extension adds one output whose type may depend on the previous environment.
let env_fst (#a:Type0) (#b:a -> Type0) (p:dtuple2 a b) : a =
  match p with | Mkdtuple2 x _ -> x
let env_snd (#a:Type0) (#b:a -> Type0) (p:dtuple2 a b) : b (env_fst p) =
  match p with | Mkdtuple2 _ y -> y

noeq type port_shape : env:Type0 -> Type =
  | PortShapeEmpty:port_shape unit
  | PortShapeSnoc:env:Type0 -> old:port_shape env -> key:node_key
      -> family:(env -> Type0)
      -> port_shape (dtuple2 env family)

noeq type port_context (input:Type0) (x:input) = {
  port_env_type:Type0;
  port_context_shape:port_shape port_env_type
}

let port_env (input:Type0) (x:input)
    (ports:port_context input x) : Type0 = ports.port_env_type

noeq type internal_port_ref : env:Type0 -> port_shape env -> key:node_key
    -> (env -> Type0) -> Type =
  | HerePort:#env:Type0 -> #shape:port_shape env
      -> #key:node_key -> #family:(env -> Type0)
      -> internal_port_ref (dtuple2 env family)
          (PortShapeSnoc env shape key family) key
          (fun pair -> family (env_fst pair))
  | TherePort:#env:Type0 -> #shape:port_shape env
      -> #old_key:node_key
      -> #family:(env -> Type0) -> #new_key:node_key
      -> #new_family:(env -> Type0)
      -> internal_port_ref env shape old_key family
      -> internal_port_ref (dtuple2 env new_family)
          (PortShapeSnoc env shape new_key new_family) old_key
          (fun pair -> family (env_fst pair))

noeq type port_ref (input:Type0) (x:input)
    (ports:port_context input x)
    (family:port_env input x ports -> Type0) : Type =
  | PortRef:key:node_key
      -> internal_port_ref ports.port_env_type ports.port_context_shape
          key family
      -> port_ref input x ports family

let port_ref_key (#input:Type0) (#x:input)
    (#ports:port_context input x)
    (#family:port_env input x ports -> Type0)
    (ref:port_ref input x ports family) : node_key =
  match ref with | PortRef key _ -> key

let rec eval_internal_port_ref (#env:Type0) (#key:node_key)
    (#shape:port_shape env) (#family:env -> Type0)
    (ref:internal_port_ref env shape key family) (e:env) : family e =
  match ref with
  | HerePort #old_env #old_shape #old_key #old_family ->
      env_snd #old_env #old_family e
  | TherePort #old_env #old_shape #old_key #old_family #new_key #new_family prior ->
      eval_internal_port_ref prior (env_fst #old_env #new_family e)

let eval_port_ref (#input:Type0) (#x:input)
    (#ports:port_context input x)
    (#family:port_env input x ports -> Type0)
    (ref:port_ref input x ports family)
    (env:port_env input x ports) : family env =
  match ref with
  | PortRef _ internal -> eval_internal_port_ref internal env

let rec port_shape_lookup (#env:Type0) (shape:port_shape env)
    (key:node_key)
  : Tot (option (family:(env -> Type0) &
      internal_port_ref env shape key family)) (decreases shape) =
  match shape with
  | PortShapeEmpty -> None
  | PortShapeSnoc old_env old old_key old_family ->
      if key = old_key then
        Some (Mkdtuple2 (fun pair -> old_family (env_fst pair))
          (HerePort #old_env #old #old_key #old_family))
      else
        match port_shape_lookup old key with
        | None -> None
        | Some (Mkdtuple2 family ref) ->
            Some (Mkdtuple2 (fun pair -> family (env_fst pair))
              (TherePort #old_env #old #key #family #old_key #old_family ref))

let root_port (input:Type0) (x:input) : port_context input x = {
  port_env_type=unit;
  port_context_shape=PortShapeEmpty
}

let extend (#input:Type0) (#x:input)
    (ports:port_context input x) (key:node_key)
    (family:port_env input x ports -> Type0) : port_context input x = {
  port_env_type=dtuple2 (port_env input x ports) family;
  port_context_shape=PortShapeSnoc (port_env input x ports)
    ports.port_context_shape key family
}

let prior_env (#input:Type0) (#x:input)
    (ports:port_context input x) (key:node_key)
    (family:port_env input x ports -> Type0)
    (env:port_env input x (extend ports key family))
  : port_env input x ports = env_fst env

let rec port_shape_keys (#env:Type0) (shape:port_shape env)
  : list node_key =
  match shape with
  | PortShapeEmpty -> []
  | PortShapeSnoc _ old key _ -> port_shape_keys old @ [key]

let rec nat_mem_append (left right:list node_key) (key:node_key)
  : Lemma (nat_mem (left @ right) key ==
           (nat_mem left key || nat_mem right key)) =
  match left with
  | [] -> ()
  | _::tail -> nat_mem_append tail right key

let rec internal_ref_key_member (#env:Type0)
    (#shape:port_shape env) (#key:node_key)
    (#family:env -> Type0)
    (ref:internal_port_ref env shape key family)
  : Lemma (nat_mem (port_shape_keys shape) key == true) =
  match ref with
  | HerePort #old_env #old_shape #new_key #new_family ->
      nat_mem_append (port_shape_keys old_shape) [new_key] new_key
  | TherePort #old_env #old_shape #old_key #old_family #new_key
      #new_family prior ->
      internal_ref_key_member prior;
      nat_mem_append (port_shape_keys old_shape) [new_key] old_key

let port_ref_key_member (#input:Type0) (#x:input)
    (#ports:port_context input x)
    (#family:port_env input x ports -> Type0)
    (ref:port_ref input x ports family)
  : Lemma (nat_mem (port_shape_keys ports.port_context_shape)
      (port_ref_key ref) == true) =
  match ref with
  | PortRef key internal ->
      internal_ref_key_member internal

let lookup_port_ref (#input:Type0) (#x:input)
    (ports:port_context input x) (key:node_key)
  : Tot (option (family:(port_env input x ports -> Type0) &
      port_ref input x ports family)) =
  match port_shape_lookup ports.port_context_shape key with
  | None -> None
  | Some (Mkdtuple2 family internal) ->
      Some (Mkdtuple2 family (PortRef key internal))

let dependent_snd (#a:Type0) (#b:a -> Type0)
    (pair:dtuple2 a b) : b (dependent_fst pair) =
  match pair with | Mkdtuple2 _ second -> second

noeq type wire_typing_witness (registry:pinned_registry_bundle)
    (input:Type0) (x:input) (ports:port_context input x)
    : syntax:wire input x
    -> family:(port_env input x ports -> Type0)
    -> evaluate:(env:port_env input x ports -> Tot (family env))
    -> Type =
  | RootWireTyping:
      wire_typing_witness registry input x ports RootWire (fun _ -> input)
        (fun _ -> x)
  | ConstantWireTyping: #a:Type0
      -> codec:codec a -> value:a
      -> packed_codec_membership (PlainCodec codec)
           registry.bundle_codec_registry.global_codec_entries
      -> wire_typing_witness registry input x ports
           (ConstantWire codec.codec_id (codec.encode value))
           (fun _ -> a) (fun _ -> value)
  | IndexedConstantWireTyping: #family:(input -> Type0)
      -> codec:indexed_codec input family -> value:family x
      -> packed_codec_membership (IndexedCodec codec)
           registry.bundle_codec_registry.global_codec_entries
      -> wire_typing_witness registry input x ports
           (ConstantWire codec.indexed_codec_id
             (codec.encode_indexed x value))
           (fun _ -> family x) (fun _ -> value)
  | OutputWireTyping: #family:(port_env input x ports -> Type0)
      -> ref:port_ref input x ports family
      -> wire_typing_witness registry input x ports
           (OutputWire (port_ref_key ref)) family
           (eval_port_ref ref)
  | PairWireTyping: #left_family:(port_env input x ports -> Type0)
      -> #right_family:(env:port_env input x ports ->
           left_family env -> Type0)
      -> left_syntax:wire input x
      -> left_eval:(env:port_env input x ports -> Tot (left_family env))
      -> left_proof:wire_typing_witness registry input x ports
           left_syntax left_family left_eval
      -> right_syntax:wire input x
      -> right_eval:(env:port_env input x ports -> Tot
           (right_family env (left_eval env)))
      -> right_proof:wire_typing_witness registry input x ports
           right_syntax (fun env -> right_family env (left_eval env))
           right_eval
      -> wire_typing_witness registry input x ports
           (PairWire left_syntax right_syntax)
           (fun env -> dtuple2 (left_family env) (right_family env))
           (fun env -> Mkdtuple2 (left_eval env) (right_eval env))
  | FstWireTyping: #left_family:(port_env input x ports -> Type0)
      -> #right_family:(env:port_env input x ports ->
           left_family env -> Type0)
      -> pair_syntax:wire input x
      -> pair_eval:(env:port_env input x ports -> Tot
           (dtuple2 (left_family env) (right_family env)))
      -> pair_proof:wire_typing_witness registry input x ports pair_syntax
           (fun env -> dtuple2 (left_family env) (right_family env))
           pair_eval
      -> wire_typing_witness registry input x ports (FstWire pair_syntax)
           left_family (fun env -> dependent_fst (pair_eval env))
  | SndWireTyping: #left_family:(port_env input x ports -> Type0)
      -> #right_family:(env:port_env input x ports ->
           left_family env -> Type0)
      -> pair_syntax:wire input x
      -> pair_eval:(env:port_env input x ports -> Tot
           (dtuple2 (left_family env) (right_family env)))
      -> pair_proof:wire_typing_witness registry input x ports pair_syntax
           (fun env -> dtuple2 (left_family env) (right_family env))
           pair_eval
      -> wire_typing_witness registry input x ports (SndWire pair_syntax)
           (fun env -> right_family env (dependent_fst (pair_eval env)))
           (fun env -> dependent_snd (pair_eval env))

noeq type wiring (registry:pinned_registry_bundle) (input:Type0) (x:input)
    (ports:port_context input x)
    (family:port_env input x ports -> Type0) = {
  wiring_syntax:wire input x;
  wiring_eval:env:port_env input x ports -> Tot (family env);
  wiring_typed:wire_typing_witness registry input x ports
    wiring_syntax family wiring_eval
}

let rec refs_append_members (left right keys:list node_key)
  : Lemma (requires refs_are_members left keys == true /\
                   refs_are_members right keys == true)
      (ensures refs_are_members (left @ right) keys == true)
      (decreases left) =
  match left with
  | [] -> ()
  | _::tail -> refs_append_members tail right keys

let rec typed_wire_refs_in_shape (#input:Type0) (#x:input)
    (#registry:pinned_registry_bundle)
    (#ports:port_context input x)
    (#syntax:wire input x)
    (#family:port_env input x ports -> Type0)
    (#evaluate:(env:port_env input x ports -> Tot (family env)))
    (typing:wire_typing_witness registry input x ports
       syntax family evaluate)
  : Lemma (ensures (refs_are_members (wire_output_refs syntax)
      (port_shape_keys ports.port_context_shape) == true))
      (decreases typing) =
  match typing with
  | RootWireTyping -> ()
  | ConstantWireTyping _ _ _ -> ()
  | IndexedConstantWireTyping _ _ _ -> ()
  | OutputWireTyping ref -> port_ref_key_member ref
  | PairWireTyping left_syntax _ left_proof right_syntax _ right_proof ->
      typed_wire_refs_in_shape left_proof;
      typed_wire_refs_in_shape right_proof;
      refs_append_members (wire_output_refs left_syntax)
        (wire_output_refs right_syntax)
        (port_shape_keys ports.port_context_shape)
  | FstWireTyping _ _ pair_proof -> typed_wire_refs_in_shape pair_proof
  | SndWireTyping _ _ pair_proof -> typed_wire_refs_in_shape pair_proof

// Builder API, trusted boundary, and constructors {{{1
assume type graph_builder (registry:pinned_registry_bundle)
    (input:Type0) (x:input)
    (ports:port_context input x) : Type0
assume val builder_nodes : #registry:pinned_registry_bundle
  -> #input:Type0 -> #x:input
  -> #ports:port_context input x
  -> graph_builder registry input x ports -> Tot (list (graph_node input x))

let eval_wiring : #registry:pinned_registry_bundle -> #input:Type0 -> #x:input
  -> #ports:port_context input x
  -> #family:(port_env input x ports -> Type0)
  -> wiring registry input x ports family
  -> (env:port_env input x ports -> Tot (family env)) =
  fun w -> w.wiring_eval

let root_wiring : #registry:pinned_registry_bundle -> #input:Type0 -> x:input
  -> Tot (w:wiring registry input x (root_port input x) (fun _ -> input){
       w.wiring_syntax == RootWire }) =
  fun x -> {
    wiring_syntax = RootWire;
    wiring_eval = (fun _ -> x);
    wiring_typed = RootWireTyping
  }
let constant_wiring : #registry:pinned_registry_bundle -> #input:Type0 -> #x:input
  -> #ports:port_context input x -> #a:Type0
  -> codec:codec a
  -> packed_codec_membership (PlainCodec codec)
       registry.bundle_codec_registry.global_codec_entries
  -> value:a
  -> Tot (w:wiring registry input x ports (fun _ -> a){
       w.wiring_syntax == ConstantWire codec.codec_id (codec.encode value) }) =
  fun codec member value -> {
    wiring_syntax = ConstantWire codec.codec_id (codec.encode value);
    wiring_eval = (fun _ -> value);
    wiring_typed = ConstantWireTyping codec value member
  }
let indexed_constant_wiring : #registry:pinned_registry_bundle -> #input:Type0 -> x:input
  -> #ports:port_context input x -> #family:(input -> Type0)
  -> codec:indexed_codec input family
  -> packed_codec_membership (IndexedCodec codec)
       registry.bundle_codec_registry.global_codec_entries
  -> value:family x
  -> Tot (w:wiring registry input x ports (fun _ -> family x){
       w.wiring_syntax ==
         ConstantWire codec.indexed_codec_id (codec.encode_indexed x value) }) =
  fun x codec member value -> {
    wiring_syntax = ConstantWire codec.indexed_codec_id
      (codec.encode_indexed x value);
    wiring_eval = (fun _ -> value);
    wiring_typed = IndexedConstantWireTyping codec value member
  }
let port_wiring : #registry:pinned_registry_bundle -> #input:Type0 -> #x:input
  -> #ports:port_context input x
  -> #family:(port_env input x ports -> Type0)
  -> ref:port_ref input x ports family
  -> Tot (w:wiring registry input x ports family{
       w.wiring_syntax == OutputWire (port_ref_key ref) }) =
  fun ref -> {
    wiring_syntax = OutputWire (port_ref_key ref);
    wiring_eval = eval_port_ref ref;
    wiring_typed = OutputWireTyping ref
  }
let pair_wiring : #registry:pinned_registry_bundle -> #input:Type0 -> #x:input
  -> #ports:port_context input x
  -> #a:(port_env input x ports -> Type0)
  -> w1:wiring registry input x ports a
  -> b:(env:port_env input x ports -> a env -> Type0)
  -> w2:wiring registry input x ports
       (fun env -> b env (eval_wiring w1 env))
  -> Tot (wiring registry input x ports
       (fun env -> dtuple2 (a env) (b env))) =
  fun w1 b w2 -> {
    wiring_syntax = PairWire w1.wiring_syntax w2.wiring_syntax;
    wiring_eval = (fun env ->
      Mkdtuple2 (eval_wiring w1 env) (eval_wiring w2 env));
    wiring_typed = PairWireTyping
      w1.wiring_syntax (eval_wiring w1) w1.wiring_typed
      w2.wiring_syntax (eval_wiring w2) w2.wiring_typed
  }
let fst_wiring : #registry:pinned_registry_bundle -> #input:Type0 -> #x:input
  -> #ports:port_context input x
  -> #a:(port_env input x ports -> Type0)
  -> #b:(env:port_env input x ports -> a env -> Type0)
  -> wiring registry input x ports (fun env -> dtuple2 (a env) (b env))
  -> Tot (wiring registry input x ports a) =
  fun w -> {
    wiring_syntax = FstWire w.wiring_syntax;
    wiring_eval = (fun env -> dependent_fst (eval_wiring w env));
    wiring_typed = FstWireTyping w.wiring_syntax w.wiring_eval
      w.wiring_typed
  }
let snd_wiring : #registry:pinned_registry_bundle -> #input:Type0 -> #x:input
  -> #ports:port_context input x
  -> #a:(port_env input x ports -> Type0)
  -> #b:(env:port_env input x ports -> a env -> Type0)
  -> w:wiring registry input x ports (fun env -> dtuple2 (a env) (b env))
  -> Tot (wiring registry input x ports
       (fun env -> b env (dependent_fst (eval_wiring w env)))) =
  fun w -> {
    wiring_syntax = SndWire w.wiring_syntax;
    wiring_eval = (fun env -> dependent_snd (eval_wiring w env));
    wiring_typed = SndWireTyping w.wiring_syntax w.wiring_eval
      w.wiring_typed
  }

assume val start_graph : #registry:pinned_registry_bundle -> #input:Type0 -> x:input
  -> Tot (graph_builder registry input x (root_port input x))
assume val add_node : #registry:pinned_registry_bundle -> #input:Type0 -> #x:input
  -> #ports:port_context input x
  -> #a:Type0 -> #b:(a -> Type0)
  -> builder:graph_builder registry input x ports
  -> ref:work a b
  -> packed_work_membership (PackedWork ref)
       registry.bundle_work_registry.global_work_entries
  -> w:wiring registry input x ports (fun _ -> a)
  -> Tot (next:graph_builder registry input x
       (extend ports (length (builder_nodes builder))
         (fun prior -> b (eval_wiring w prior))) &
       ref:port_ref input x
       (extend ports (length (builder_nodes builder))
         (fun prior -> b (eval_wiring w prior)))
       (fun env -> b (eval_wiring w
         (prior_env ports
           (length (builder_nodes builder))
           (fun prior -> b (eval_wiring w prior)) env)))
       {port_ref_key ref == length (builder_nodes builder)})

// Builder reachability and finishing laws {{{1
// This inductive witness means a builder was obtained only by the public
// start/add sequence. Completeness must produce this evidence; a raw graph
// record alone does not count as an API construction.
noeq type builder_reachable (registry:pinned_registry_bundle)
    (input:Type0) (x:input)
    : ports:port_context input x
    -> graph_builder registry input x ports -> Type =
  | BuilderStarted:
      builder_reachable registry input x (root_port input x)
        (start_graph x)
  | BuilderExtended: #ports:port_context input x
      -> #a:Type0 -> #b:(a -> Type0)
      -> builder:graph_builder registry input x ports
      -> builder_reachable registry input x ports builder
      -> ref:work a b
      -> member:packed_work_membership (PackedWork ref)
           registry.bundle_work_registry.global_work_entries
      -> w:wiring registry input x ports (fun _ -> a)
      -> builder_reachable registry input x
           (extend ports (length (builder_nodes builder))
             (fun prior -> b (eval_wiring w prior)))
       (match add_node builder ref member w with
            | Mkdtuple2 next _ -> next)

let finish_graph (#registry:pinned_registry_bundle)
    (#input:Type0) (#output:input -> Type0) (x:input)
    (#ports:port_context input x)
    (builder:graph_builder registry input x ports)
    (w:wiring registry input x ports (fun _ -> output x))
  : graph_desc input output x = {
    graph_nodes = builder_nodes builder;
    graph_output_wire = w.wiring_syntax
  }

let builder_finish_nodes_preserved (#registry:pinned_registry_bundle)
    (#input:Type0)
    (#output:input -> Type0) (x:input)
    (#ports:port_context input x)
    (builder:graph_builder registry input x ports)
    (w:wiring registry input x ports (fun _ -> output x))
  : Lemma ((finish_graph x builder w).graph_nodes ==
           builder_nodes builder) = ()

let rec append_one (#i:Type0) (#x:i)
    (nodes:list (graph_node i x)) (node:graph_node i x)
  : list (graph_node i x) =
  match nodes with
  | [] -> [node]
  | head::tail -> head :: append_one tail node

// Typed DAG witnesses and well-formedness {{{1
// A typed node sequence is an independent semantic witness for a finite DAG.
// Each input wire is typed in the context containing only earlier nodes, and
// each extension records its executable Work value and dependent output.
noeq type typed_node_sequence (registry:pinned_registry_bundle)
    (input:Type0) (x:input)
    : ports:port_context input x
    -> nodes:list (graph_node input x) -> Type =
  | TypedNodesEmpty:
      typed_node_sequence registry input x (root_port input x) []
  | TypedNodesSnoc: prior_ports:port_context input x
      -> prior_nodes:list (graph_node input x)
      -> typed_node_sequence registry input x prior_ports prior_nodes
      -> key:node_key
      -> fresh:squash (not (nat_mem (node_keys prior_nodes) key))
      -> #a:Type0 -> #b:(a -> Type0)
      -> node_work:work a b
      -> packed_work_membership (PackedWork node_work)
           registry.bundle_work_registry.global_work_entries
      -> input_wiring:wiring registry input x prior_ports (fun _ -> a)
      -> typed_node_sequence registry input x
           (extend prior_ports key
             (fun prior -> b (eval_wiring input_wiring prior)))
           (append_one prior_nodes {
             graph_node_key = key;
             graph_node_work = durable_ref_of_work node_work;
             graph_node_input = input_wiring.wiring_syntax
           })

let rec node_keys_append_one (#input:Type0) (#x:input)
    (nodes:list (graph_node input x)) (node:graph_node input x)
  : Lemma (node_keys (append_one nodes node) ==
           node_keys nodes @ [node.graph_node_key]) =
  match nodes with
  | [] -> ()
  | _::tail -> node_keys_append_one tail node

// Every typed port key is exactly one node key, in construction order. This
// connects the concrete port telescope to the descriptor's topological list.
let rec typed_node_sequence_shape_keys (#registry:pinned_registry_bundle)
    (#input:Type0) (#x:input)
    (#ports:port_context input x)
    (#nodes:list (graph_node input x))
    (sequence:typed_node_sequence registry input x ports nodes)
  : Lemma (ensures
      (port_shape_keys ports.port_context_shape == node_keys nodes))
      (decreases sequence) =
  match sequence with
  | TypedNodesEmpty -> ()
  | TypedNodesSnoc old_ports old_nodes prior key _ #a #b
      node_work _ input_wiring ->
      typed_node_sequence_shape_keys prior;
      let node = {
        graph_node_key = key;
        graph_node_work = durable_ref_of_work node_work;
        graph_node_input = input_wiring.wiring_syntax
      } in
      node_keys_append_one old_nodes node;
      let next_ports = extend old_ports key
          (fun prior -> b (eval_wiring input_wiring prior)) in
      assert (port_shape_keys next_ports.port_context_shape ==
        port_shape_keys old_ports.port_context_shape @ [key]);
      assert (port_shape_keys ports.port_context_shape ==
        port_shape_keys next_ports.port_context_shape);
      assert (nodes == append_one old_nodes node);
      ()

let typed_port_ref_is_prior (#registry:pinned_registry_bundle)
    (#input:Type0) (#x:input)
    (#ports:port_context input x)
    (#nodes:list (graph_node input x))
    (sequence:typed_node_sequence registry input x ports nodes)
    (#family:port_env input x ports -> Type0)
    (ref:port_ref input x ports family)
  : Lemma (nat_mem (node_keys nodes) (port_ref_key ref) == true) =
  typed_node_sequence_shape_keys sequence;
  port_ref_key_member ref;
  ()

let typed_wiring_refs_are_prior (#registry:pinned_registry_bundle)
    (#input:Type0) (#x:input)
    (#ports:port_context input x)
    (#nodes:list (graph_node input x))
    (sequence:typed_node_sequence registry input x ports nodes)
    (#family:port_env input x ports -> Type0)
    (w:wiring registry input x ports family)
  : Lemma (ensures (refs_are_members
      (wire_output_refs w.wiring_syntax) (node_keys nodes) == true)) =
  typed_node_sequence_shape_keys sequence;
  typed_wire_refs_in_shape w.wiring_typed;
  ()

// The final node added by a typed sequence consumes only ports in its exact
// prefix. This is the inductive step used to derive DAG acyclicity.
let typed_sequence_last_input_refs_are_prior
    (#registry:pinned_registry_bundle) (#input:Type0) (#x:input)
    (#ports:port_context input x)
    (#nodes:list (graph_node input x))
    (sequence:typed_node_sequence registry input x ports nodes)
  : Lemma (match sequence with
      | TypedNodesEmpty -> True
      | TypedNodesSnoc old_ports old_nodes prior key unique #a #b work _ input_wiring ->
          refs_are_members (wire_output_refs input_wiring.wiring_syntax)
            (node_keys old_nodes) == true) =
  match sequence with
  | TypedNodesEmpty -> ()
  | TypedNodesSnoc old_ports old_nodes prior key unique #a #b work _ input_wiring ->
      typed_wiring_refs_are_prior prior input_wiring

let rec typed_sequence_prefix_edges (#registry:pinned_registry_bundle)
    (#input:Type0) (#x:input)
    (#ports:port_context input x)
    (#nodes:list (graph_node input x))
    (sequence:typed_node_sequence registry input x ports nodes)
  : Tot prop (decreases sequence) =
  match sequence with
  | TypedNodesEmpty -> True
  | TypedNodesSnoc old_ports old_nodes prior key unique #a #b work _ input_wiring ->
      typed_sequence_prefix_edges prior /\
      refs_are_members (wire_output_refs input_wiring.wiring_syntax)
        (node_keys old_nodes) == true

let rec typed_sequence_prefix_edges_sound
    (#registry:pinned_registry_bundle) (#input:Type0) (#x:input)
    (#ports:port_context input x)
    (#nodes:list (graph_node input x))
    (sequence:typed_node_sequence registry input x ports nodes)
  : Lemma (ensures (typed_sequence_prefix_edges sequence))
      (decreases sequence) =
  match sequence with
  | TypedNodesEmpty -> ()
  | TypedNodesSnoc old_ports old_nodes prior key unique #a #b work _ input_wiring ->
      typed_sequence_prefix_edges_sound prior;
      typed_wiring_refs_are_prior prior input_wiring

let typed_graph_output_refs_in_nodes (#input:Type0) (#output:input -> Type0)
    (#x:input) (#registry:pinned_registry_bundle)
    (#ports:port_context input x)
    (#nodes:list (graph_node input x))
    (sequence:typed_node_sequence registry input x ports nodes)
    (output_wiring:wiring registry input x ports (fun _ -> output x))
  : Lemma (refs_are_members
      (wire_output_refs output_wiring.wiring_syntax) (node_keys nodes) == true) =
  typed_wiring_refs_are_prior sequence output_wiring

let nodes_label (#i:Type0) (#x:i) (nodes:list (graph_node i x))
    (key:node_key) : option durable_work_ref =
  match find_node nodes key with
  | None -> None
  | Some node -> Some node.graph_node_work

let nodes_input (#i:Type0) (#x:i) (nodes:list (graph_node i x))
    (key:node_key) : option (wire i x) =
  match find_node nodes key with
  | None -> None
  | Some node -> Some node.graph_node_input

let interpret_graph_label (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x)
  : Lemma (forall key.
      (interpret_graph x g).label key == nodes_label g.graph_nodes key) = ()

let interpret_graph_input (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x)
  : Lemma (forall key.
      (interpret_graph x g).input_wire key == nodes_input g.graph_nodes key) = ()

// This witness is a typed topological sequence plus an exact projection into
// the first-order DAG. Its constructors carry membership evidence for each
// selected Work and codec in this exact pinned bundle.
noeq type typed_graph_witness (registry:pinned_registry_bundle) (input:Type0)
    (output:input -> Type0) (x:input)
    (dag:finite_typed_dag input output x) : Type =
  | TypedGraphWitness: #ports:port_context input x
      -> #nodes:list (graph_node input x)
      -> typed_node_sequence registry input x ports nodes
      -> output_wiring:wiring registry input x ports (fun _ -> output x)
      -> squash (dag.vertices == node_keys nodes)
      -> squash (dag.topological_order == node_keys nodes)
      -> squash (forall key. dag.label key == nodes_label nodes key)
      -> squash (forall key. dag.input_wire key == nodes_input nodes key)
      -> squash (dag.output_wire == output_wiring.wiring_syntax)
      -> typed_graph_witness registry input output x dag

let dag_wf (#i:Type0) (#o:i -> Type0)
    (registry:pinned_registry_bundle) (x:i)
    (d:finite_typed_dag i o x) : prop =
  nat_list_unique d.vertices == true /\
  same_nat_set d.vertices d.topological_order == true /\
  (forall (key:node_key).
    nat_mem d.vertices key ==
      (match d.label key with | None -> false | Some _ -> true)) /\
  (forall (key:node_key).
    nat_mem d.vertices key ==
      (match d.input_wire key with | None -> false | Some _ -> true)) /\
  dag_inputs_are_topological d.topological_order d [] == true /\
  refs_are_members (wire_output_refs d.output_wire) d.vertices == true /\
  (exists (witness:typed_graph_witness registry i o x d). True)

let graph_wf (#i:Type0) (#o:i -> Type0)
    (registry:pinned_registry_bundle) (x:i)
    (g:graph_desc i o x) : prop = dag_wf registry x (interpret_graph x g)

// Graph-local allocation validation {{{1
// Allocation records are keyed by the descriptor's local node keys. Commit
// later lifts these keys to occurrence paths. This keeps the generated graph
// and its resource plan one result while avoiding a second per-node budget
// source in the generator API.
let rec allocation_keys (plan:graph_allocation_plan) : list node_key =
  match plan with
  | [] -> []
  | entry::tail -> entry.allocated_key :: allocation_keys tail

let rec allocation_node_valid (#i:Type0) (#x:i)
    (registry:pinned_registry_bundle)
    (nodes:list (graph_node i x)) (plan:graph_allocation_plan) : bool =
  match nodes, plan with
  | [], [] -> true
  | node::tail, entry::plan_tail ->
      node.graph_node_key = entry.allocated_key &&
      (match resolve_global_work registry.bundle_work_registry
               node.graph_node_work with
       | Some (PackedWork work) ->
           let allowance = entry.allocated_values in
           (match work with
            | LocalWork _ ->
                allowance.expansion_fuel = 0 &&
                allowance.charge_allocation = 0
            | ExternalWork operation ->
                allowance.expansion_fuel = 0 &&
                allowance.charge_allocation = operation.maximum_charge
            | GenerateWork _ -> allowance.expansion_fuel > 0) &&
           allocation_node_valid registry tail plan_tail
       | None -> false)
  | _, _ -> false

let rec child_generator_fuel (#i:Type0) (#x:i)
    (registry:pinned_registry_bundle)
    (nodes:list (graph_node i x)) (plan:graph_allocation_plan) : nat =
  match nodes, plan with
  | [], [] -> 0
  | node::tail, entry::plan_tail ->
      let here =
        match resolve_global_work registry.bundle_work_registry
                node.graph_node_work with
        | Some (PackedWork (GenerateWork _)) ->
            entry.allocated_values.expansion_fuel
        | _ -> 0 in
      here + child_generator_fuel registry tail plan_tail
  | _, _ -> 0

let rec graph_charge_pool (#i:Type0) (#x:i)
    (registry:pinned_registry_bundle)
    (nodes:list (graph_node i x)) (plan:graph_allocation_plan) : nat =
  match nodes, plan with
  | [], [] -> 0
  | node::tail, entry::plan_tail ->
      let here =
        match resolve_global_work registry.bundle_work_registry
                node.graph_node_work with
        | Some (PackedWork (ExternalWork _)) ->
            entry.allocated_values.charge_allocation
        | Some (PackedWork (GenerateWork _)) ->
            entry.allocated_values.charge_allocation
        | _ -> 0 in
      here + graph_charge_pool registry tail plan_tail
  | _, _ -> 0

let allocation_plan_wf (#i:Type0) (#o:i -> Type0) (#x:i)
    (registry:pinned_registry_bundle)
    (parent_fuel parent_charge:nat)
    (graph:graph_desc i o x) (plan:graph_allocation_plan) : prop =
  let keys = node_keys graph.graph_nodes in
  let planned = allocation_keys plan in
  keys == planned /\
  nat_list_unique planned == true /\
  allocation_node_valid registry graph.graph_nodes plan == true /\
  (let nested = child_generator_fuel registry graph.graph_nodes plan in
   nested = 0 || nested < parent_fuel) /\
  graph_charge_pool registry graph.graph_nodes plan <= parent_charge

// A generator is admitted only when every input/allocation pair returns a
// well-formed graph and an exact, ledger-safe graph-local allocation plan.
// Exact work membership is a separate registry proof obligation; the
// proposition here never substitutes identity-token equality for it.
noeq type generator_admission (registry:pinned_registry_bundle)
    (#i:Type0) (#o:i -> Type0) (generator:generator_ref i o) = {
  // Admission is for the exact generator pinned as a GenerateWork in this
  // bundle, not merely any callback with a matching first-order identity.
  generator_work_member : packed_work_membership
    (PackedWork (GenerateWork generator))
    registry.bundle_work_registry.global_work_entries;
  generator_result_valid : x:i -> metric:charge_metric_identity
    -> parent:generation_allocation ->
    Lemma (graph_wf registry x
      (generator.generate_graph x metric parent).generated_descriptor /\
      allocation_plan_wf registry parent.expansion_fuel
        parent.charge_allocation
        (generator.generate_graph x metric parent).generated_descriptor
        (generator.generate_graph x metric parent).generated_child_plan)
}

let generator_member (#i:Type0) (#o:i -> Type0)
    (registry:pinned_registry_bundle) (generator:generator_ref i o) : prop =
  forall (x:i) (metric:charge_metric_identity)
    (parent:generation_allocation).
    let result = generator.generate_graph x metric parent in
    graph_wf registry x result.generated_descriptor /\
    allocation_plan_wf registry parent.expansion_fuel
      parent.charge_allocation result.generated_descriptor
      result.generated_child_plan

// Builder construction laws {{{1
// start_graph_law: the initial builder has no nodes {{{2
let start_graph_law (#registry:pinned_registry_bundle)
    (#input:Type0) (x:input)
  : Lemma (builder_nodes #registry (start_graph #registry x) == []) = admit()

// add_node_appends_exact: extension appends its exact node {{{2
let add_node_appends_exact (#registry:pinned_registry_bundle)
    (#input:Type0) (x:input)
    (#ports:port_context input x)
    (#a:Type0) (#b:a -> Type0)
    (builder:graph_builder registry input x ports)
    (ref:work a b)
    (member:packed_work_membership (PackedWork ref)
      registry.bundle_work_registry.global_work_entries)
    (w:wiring registry input x ports (fun _ -> a))
  : Lemma
      (builder_nodes (match add_node builder ref member w with
         | Mkdtuple2 next _ -> next) ==
       append_one (builder_nodes builder) {
         graph_node_key = length (builder_nodes builder);
         graph_node_work = durable_ref_of_work ref;
         graph_node_input = w.wiring_syntax
       }) = admit()

// P1 soundness and completeness theorem spine {{{1
// P1 theorem spine. The representation-level relation and exact registry
// membership are explicit; builder preservation and completeness remain
// admitted for top-down review.
// finish_graph_sound: reachable builders produce well-formed graphs {{{2
let finish_graph_sound (#input:Type0) (#output:input -> Type0)
    (registry:pinned_registry_bundle) (x:input)
    (#ports:port_context input x)
    (builder:graph_builder registry input x ports)
    (reachable:builder_reachable registry input x ports builder)
    (w:wiring registry input x ports (fun _ -> output x))
  : Lemma (graph_wf registry x (finish_graph x builder w)) = admit()

// graph_complete: every well-formed DAG is expressible {{{2
let graph_complete (#input:Type0) (#output:input -> Type0)
    (registry:pinned_registry_bundle) (x:input)
    (dag:finite_typed_dag input output x)
  : Lemma (dag_wf registry x dag ==>
      (exists (ports:port_context input x).
       exists (builder:graph_builder registry input x ports).
       exists (w:wiring registry input x ports (fun _ -> output x)).
         (exists (reach:builder_reachable registry input x ports builder). True) /\
         graph_wf registry x (finish_graph x builder w) /\
         wire_label_isomorphic x (interpret_graph x
           (finish_graph x builder w)) dag)) =
  admit()

