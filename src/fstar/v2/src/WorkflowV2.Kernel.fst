module WorkflowV2.Kernel

// Durable identities and work references {{{1
// Durable bytes and their identities are made concrete here only as simple
// values. Their canonicality and registry resolution laws are V2-01 proof
// obligations; graph structure and well-formedness are defined in V2-02.
type bytes = list nat
type digest = bytes

type codec_identity = {
  codec_name:string;
  codec_version:nat;
  codec_build:digest
}

type code_identity = {
  code_name:string;
  code_version:nat;
  code_build:digest
}

type operation_identity = {
  operation_name:string;
  operation_version:nat;
  operation_build:digest
}

type generator_identity = {
  generator_name:string;
  generator_version:nat;
  generator_build:digest
}

type graph_codec_identity = {
  graph_codec_name:string;
  graph_codec_version:nat;
  graph_codec_build:digest
}

type output_identity =
  | ValueOutputIdentity:codec_identity -> output_identity
  | GeneratedGraphCodecIdentity:graph_codec_identity -> output_identity

type registry_identity = {
  registry_name:string;
  registry_version:nat;
  registry_build:digest
}

type work_identity =
  | CodeWorkIdentity:code_identity -> work_identity
  | OperationWorkIdentity:operation_identity -> work_identity
  | GeneratorWorkIdentity:generator_identity -> work_identity

// First-order journal and graph form; dependent type indices are recovered by
// resolving this exact identity in the pinned registry.
type durable_work_ref = {
  durable_kind:work_identity;
  durable_input_codec:codec_identity;
  durable_output:output_identity
}

// Graph and wire syntax {{{1
type node_key = nat

// First-order wire syntax. Constant typing is recovered from the pinned codec
// identity at this graph's exact root input.
type wire (input:Type0) (x:input) =
  | RootWire:wire input x
  | OutputWire:node_key -> wire input x
  | ConstantWire:codec_identity -> bytes -> wire input x
  | PairWire:wire input x -> wire input x -> wire input x
  | FstWire:wire input x -> wire input x
  | SndWire:wire input x -> wire input x

type graph_node (input:Type0) (x:input) = {
  graph_node_key:node_key;
  graph_node_work:durable_work_ref;
  graph_node_input:wire input x
}

// Nodes are stored topologically. The descriptor contains references and wire
// syntax, never executable closures or runtime values.
type graph_desc (input:Type0) (output:input -> Type0) (x:input) = {
  graph_nodes:list (graph_node input x);
  graph_output_wire:wire input x
}

// Codec and executable work contracts {{{1
noeq type codec (a:Type0) = {
  codec_id:codec_identity;
  encode:a -> Tot bytes;
  decode:bytes -> Tot (option a);
  roundtrip:(x:a) -> Lemma (decode (encode x) == Some x);
  canonical:(wire:bytes) -> (x:a)
    -> Lemma (decode wire == Some x ==> wire == encode x)
}

noeq type indexed_codec (i:Type0) (o:i -> Type0) = {
  indexed_codec_id:codec_identity;
  encode_indexed:(x:i) -> o x -> Tot bytes;
  decode_indexed:(x:i) -> bytes -> Tot (option (o x));
  roundtrip_indexed:(x:i) -> (y:o x)
    -> Lemma (decode_indexed x (encode_indexed x y) == Some y);
  canonical_indexed:(x:i) -> (wire:bytes) -> (y:o x)
    -> Lemma
      (decode_indexed x wire == Some y ==> wire == encode_indexed x y)
}

noeq type code_ref (input:Type0) (output:input -> Type0) = {
  code_ref_id:code_identity;
  input_codec:codec input;
  output_codec:indexed_codec input output;
  run:(x:input) -> Tot (output x)
}

noeq type op_ref (input:Type0) (output:input -> Type0) = {
  operation_ref_id:operation_identity;
  request_codec:codec input;
  operation_output_codec:indexed_codec input output;
  validate_reply:(x:input) -> (reply:bytes)
    -> Tot (option (output x));
  maximum_charge:nat
}

noeq type graph_codec (input:Type0) (output:input -> Type0) = {
  graph_codec_id:graph_codec_identity;
  encode_graph:(x:input) -> graph_desc input output x -> Tot bytes;
  decode_graph:(x:input) -> bytes
    -> Tot (option (graph_desc input output x));
  graph_roundtrip:(x:input) -> (g:graph_desc input output x) -> Lemma
    (decode_graph x (encode_graph x g) == Some g);
  graph_canonical:(x:input) -> (wire:bytes)
    -> (g:graph_desc input output x)
    -> Lemma (decode_graph x wire == Some g ==> wire == encode_graph x g)
}

// One per-occurrence allocation is the source for both generation fuel and
// reserved charge. Graph size and encoded size are measured from the finite
// descriptor; they are not duplicated as API bounds.
type generation_allocation = {
  expansion_fuel:nat;
  charge_allocation:nat
}

// A generated descriptor carries one allocation per graph-local key. The
// occurrence path is not known until commit, so lifting into the journal's
// occurrence-keyed plan happens at that boundary.
type node_allocation = {
  allocated_key:node_key;
  allocated_values:generation_allocation
}

type graph_allocation_plan = list node_allocation

noeq type generated_graph (input:Type0) (output:input -> Type0)
    (x:input) (parent:generation_allocation) = {
  generated_descriptor:graph_desc input output x;
  generated_child_plan:graph_allocation_plan
}

type run_budget = {
  total_expansion_fuel:nat;
  total_charge:nat
}

noeq type generator_ref (input:Type0)
    (output:input -> Type0) = {
  generator_ref_id:generator_identity;
  generator_input_codec:codec input;
  generator_output_codec:graph_codec input output;
  generate_graph:(x:input)
    -> (allocation:generation_allocation)
    -> Tot (generated_graph input output x allocation)
}

noeq type work : input:Type0 -> (input -> Type0) -> Type =
  | LocalWork : #input:Type0 -> #output:(input -> Type0)
      -> code_ref input output
      -> work input output
  | ExternalWork : #input:Type0 -> #output:(input -> Type0)
      -> op_ref input output
      -> work input output
  | GenerateWork : #input:Type0 -> #output:(input -> Type0)
      -> generator_ref input output
      -> work input output

