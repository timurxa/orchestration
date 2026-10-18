module WorkflowV2.GraphCodec

open FStar.List.Tot
open FStar.List.Tot.Properties
open WorkflowV2.Kernel

// Graph syntax codec. Primitive identity codecs are owned by Kernel.

let rec enc_wire (#i:Type0) (#x:i) (w:wire i x) : bytes =
  match w with
  | RootWire -> [0]
  | OutputWire key -> 1 :: enc_nat key
  | ConstantWire id value -> 2 :: enc_codec_identity id @ enc_seq value
  | PairWire left right ->
      3 :: enc_wire left @ enc_wire right
  | FstWire pair -> 4 :: enc_wire pair
  | SndWire pair -> 5 :: enc_wire pair

let dec_wire_step (#i:Type0) (#x:i)
    (parse_child:bytes -> Tot (option (wire i x & bytes))) (input:bytes)
    : option (wire i x & bytes) =
  match input with
  | [] -> None
  | tag::tail ->
      match tag with
      | 0 -> Some (RootWire, tail)
      | 1 -> (match dec_nat tail with
             | None -> None
             | Some (key, rest) -> Some (OutputWire key, rest))
      | 2 -> (match dec_codec_identity tail with
             | None -> None
             | Some (id, rest) ->
                 match dec_len_seq rest with
                 | None -> None
                 | Some (value, final) -> Some (ConstantWire id value, final))
      | 3 -> (match parse_child tail with
             | None -> None
             | Some (left, rest2) ->
                 match parse_child rest2 with
                 | None -> None
                 | Some (right, final) ->
                     Some (PairWire left right, final))
      | 4 -> (match parse_child tail with
             | None -> None
             | Some (pair, rest) -> Some (FstWire pair, rest))
      | 5 -> (match parse_child tail with
             | None -> None
             | Some (pair, rest) -> Some (SndWire pair, rest))
      | _ -> None

let rec dec_wire_fuel (#i:Type0) (#x:i) (fuel:nat) (input:bytes)
    : Tot (option (wire i x & bytes)) (decreases fuel) =
  if fuel = 0 then None
  else dec_wire_step (dec_wire_fuel (fuel - 1)) input

let no_wire (#i:Type0) (#x:i) : option (wire i x & bytes) = None

let dec_wire_fuel_equation (#i:Type0) (#x:i) (fuel:nat) (input:bytes)
    : Lemma (dec_wire_fuel fuel input ==
             (if fuel = 0 then no_wire #i #x
              else dec_wire_step #i #x
                (dec_wire_fuel #i #x (fuel - 1)) input)) = ()

let dec_wire (#i:Type0) (#x:i) (input:bytes)
    : Tot (option (wire i x & bytes)) =
  dec_wire_fuel (FStar.List.Tot.length input) input

let enc_graph_node (#i:Type0) (#x:i) (n:graph_node i x) : bytes =
  enc_nat n.graph_node_key @ enc_durable_work_ref n.graph_node_work @
  enc_wire n.graph_node_input

let dec_graph_node (#i:Type0) (#x:i) (input:bytes)
    : option (graph_node i x & bytes) =
  match dec_nat input with
  | None -> None
  | Some (key, tail) ->
      match dec_durable_work_ref tail with
      | None -> None
      | Some (work, tail2) ->
          match dec_wire tail2 with
          | None -> None
          | Some (wiring, rest) ->
              Some ({graph_node_key=key; graph_node_work=work;
                     graph_node_input=wiring}, rest)

let rec enc_nodes (#i:Type0) (#x:i) (nodes:list (graph_node i x)) : bytes =
  match nodes with | [] -> [] | node::tail ->
    enc_graph_node node @ enc_nodes tail

let rec dec_nodes (#i:Type0) (#x:i) (count:nat) (input:bytes)
    : Tot (option (list (graph_node i x) & bytes)) (decreases count) =
  if count = 0 then Some ([], input)
  else match dec_graph_node input with
       | None -> None
       | Some (node, rest) ->
           match dec_nodes (count - 1) rest with
           | None -> None
           | Some (tail, final) -> Some (node::tail, final)

let graph_magic : nat = 0x47524150

let encode_graph_syntax (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x) : bytes =
  [graph_magic] @ enc_nat (FStar.List.Tot.length g.graph_nodes) @
  enc_nodes g.graph_nodes @
  enc_wire g.graph_output_wire

let parse_graph_syntax (#i:Type0) (#o:i -> Type0) (x:i) (input:bytes)
    : Tot (option (graph_desc i o x)) =
  match input with
  | graph_magic::tail ->
      (match dec_nat tail with
       | None -> None
       | Some (count, rest) ->
           match dec_nodes count rest with
           | None -> None
           | Some (nodes, after_nodes) ->
               match dec_wire after_nodes with
               | Some (output, []) ->
                   Some ({graph_nodes=nodes; graph_output_wire=output})
               | _ -> None)
  | _ -> None

let decode_graph_syntax (#i:Type0) (#o:i -> Type0) (x:i) (input:bytes)
    : Tot (option (graph_desc i o x)) =
  match parse_graph_syntax x input with
  | None -> None
  | Some g ->
      if input = encode_graph_syntax x g then Some g else None

// Structural induction follows syntax trees; list fields follow their
// declared lengths. Exact EOF makes every accepted byte string canonical.
let max_nat (a b:nat) : nat = if a < b then b else a

let rec wire_depth (#i:Type0) (#x:i) (w:wire i x) : nat =
  match w with
  | RootWire -> 0
  | OutputWire _ -> 0
  | ConstantWire _ _ -> 0
  | PairWire left right ->
      1 + max_nat (wire_depth left) (wire_depth right)
  | FstWire pair -> 1 + wire_depth pair
  | SndWire pair -> 1 + wire_depth pair

let rec wire_depth_fits (#i:Type0) (#x:i) (w:wire i x)
    : Lemma (ensures
        (wire_depth w < FStar.List.Tot.length (enc_wire w)))
      (decreases w) =
  match w with
  | RootWire -> ()
  | OutputWire _ -> ()
  | ConstantWire _ _ -> ()
  | PairWire left right ->
      wire_depth_fits left;
      wire_depth_fits right;
      FStar.List.Tot.Properties.append_length [3]
        (enc_wire left @ enc_wire right);
      FStar.List.Tot.Properties.append_length (enc_wire left) (enc_wire right);
      assert (wire_depth w < FStar.List.Tot.length (enc_wire w))
  | FstWire pair ->
      wire_depth_fits pair;
      FStar.List.Tot.Properties.append_length [4] (enc_wire pair);
      assert (wire_depth w < FStar.List.Tot.length (enc_wire w))
  | SndWire pair ->
      wire_depth_fits pair;
      FStar.List.Tot.Properties.append_length [5] (enc_wire pair);
      assert (wire_depth w < FStar.List.Tot.length (enc_wire w))

let rec wire_decode_encoding_fuel (#i:Type0) (#x:i) (w:wire i x)
    (fuel:nat) (suffix:bytes)
    : Lemma (requires (fuel > 0 /\ wire_depth w < fuel))
      (ensures (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix)))
      (decreases w) =
  dec_wire_fuel_equation #i #x fuel (enc_wire w @ suffix);
  match w with
  | RootWire ->
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (enc_wire w @ suffix) == Some (w, suffix));
      assert (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix))
  | OutputWire key ->
      let out:wire i x = OutputWire key in
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (1 :: (enc_nat key @ suffix)) == Some (out, suffix));
      assert (dec_wire_fuel fuel (enc_wire out @ suffix) == Some (out, suffix))
  | ConstantWire id value ->
      let constant:wire i x = ConstantWire id value in
      append_assoc_local (enc_codec_identity id) (enc_seq value) suffix;
      codec_identity_decode_encoding_suffix id (enc_seq value @ suffix);
      sequence_decode_encoding_suffix value suffix;
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (2 :: (enc_codec_identity id @ (enc_seq value @ suffix))) ==
        Some (constant, suffix));
      assert (dec_wire_fuel fuel (enc_wire constant @ suffix) ==
              Some (constant, suffix))
  | PairWire left right ->
      append_assoc_local [3] (enc_wire left) (enc_wire right @ suffix);
      append_assoc_local (enc_wire left) (enc_wire right) suffix;
      assert (fuel - 1 > 0);
      assert (wire_depth left < fuel - 1);
      assert (wire_depth right < fuel - 1);
      wire_decode_encoding_fuel left (fuel - 1) (enc_wire right @ suffix);
      wire_decode_encoding_fuel right (fuel - 1) suffix;
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (enc_wire w @ suffix) == Some (w, suffix));
      assert (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix))
  | FstWire pair ->
      assert (fuel - 1 > 0);
      assert (wire_depth pair < fuel - 1);
      wire_decode_encoding_fuel pair (fuel - 1) suffix;
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (enc_wire w @ suffix) == Some (w, suffix));
      assert (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix))
  | SndWire pair ->
      assert (fuel - 1 > 0);
      assert (wire_depth pair < fuel - 1);
      wire_decode_encoding_fuel pair (fuel - 1) suffix;
      assert (dec_wire_step #i #x (dec_wire_fuel #i #x (fuel - 1))
        (enc_wire w @ suffix) == Some (w, suffix));
      assert (dec_wire_fuel fuel (enc_wire w @ suffix) == Some (w, suffix))

let wire_decode_encoding (#i:Type0) (#x:i) (w:wire i x)
    : Lemma (dec_wire (enc_wire w) == Some (w, [])) =
  wire_depth_fits w;
  wire_decode_encoding_fuel w (FStar.List.Tot.length (enc_wire w)) []

let wire_decode_encoding_suffix (#i:Type0) (#x:i) (w:wire i x)
    (suffix:bytes)
    : Lemma (dec_wire (enc_wire w @ suffix) == Some (w, suffix)) =
  FStar.List.Tot.Properties.append_length (enc_wire w) suffix;
  wire_depth_fits w;
  wire_decode_encoding_fuel w
    (FStar.List.Tot.length (enc_wire w @ suffix)) suffix

let durable_ref_decode_encoding (r:durable_work_ref)
    : Lemma (dec_durable_work_ref (enc_durable_work_ref r) == Some (r, [])) =
  durable_work_ref_decode_encoding_suffix r []

let node_decode_encoding_suffix (#i:Type0) (#x:i) (n:graph_node i x)
    (suffix:bytes)
    : Lemma (dec_graph_node (enc_graph_node n @ suffix) ==
             Some (n, suffix)) =
  let rest = enc_durable_work_ref n.graph_node_work @
             (enc_wire n.graph_node_input @ suffix) in
  append_assoc_local (enc_nat n.graph_node_key)
    (enc_durable_work_ref n.graph_node_work @ enc_wire n.graph_node_input)
    suffix;
  append_assoc_local (enc_durable_work_ref n.graph_node_work)
    (enc_wire n.graph_node_input) suffix;
  assert (enc_graph_node n @ suffix == enc_nat n.graph_node_key @ rest);
  assert (dec_nat (enc_nat n.graph_node_key @ rest) ==
          Some (n.graph_node_key, rest));
  wire_decode_encoding_suffix n.graph_node_input suffix;
  durable_work_ref_decode_encoding_suffix n.graph_node_work
    (enc_wire n.graph_node_input @ suffix);
  assert (dec_graph_node (enc_graph_node n @ suffix) == Some (n, suffix))

let node_decode_encoding (#i:Type0) (#x:i) (n:graph_node i x)
    : Lemma (dec_graph_node (enc_graph_node n) == Some (n, [])) =
  node_decode_encoding_suffix n []

let rec nodes_decode_encoding_suffix (#i:Type0) (#x:i)
    (nodes:list (graph_node i x)) (suffix:bytes)
    : Lemma (ensures
        (dec_nodes (FStar.List.Tot.length nodes)
           (enc_nodes nodes @ suffix) == Some (nodes, suffix)))
    (decreases nodes) =
  match nodes with
  | [] -> ()
  | node::tail ->
      append_assoc_local (enc_graph_node node) (enc_nodes tail) suffix;
      node_decode_encoding_suffix node (enc_nodes tail @ suffix);
      nodes_decode_encoding_suffix tail suffix

let rec nodes_decode_encoding (#i:Type0) (#x:i)
    (nodes:list (graph_node i x))
    : Lemma (ensures
        (dec_nodes (FStar.List.Tot.length nodes) (enc_nodes nodes) ==
         Some (nodes, [])))
    (decreases nodes) =
  nodes_decode_encoding_suffix nodes []

let graph_decode_encoding (#i:Type0) (#o:i -> Type0) (x:i)
    (g:graph_desc i o x)
    : Lemma (decode_graph_syntax x (encode_graph_syntax x g) == Some g) =
  nodes_decode_encoding_suffix g.graph_nodes (enc_wire g.graph_output_wire);
  wire_decode_encoding g.graph_output_wire;
  assert (parse_graph_syntax x (encode_graph_syntax x g) == Some g)

let graph_decode_canonical (#i:Type0) (#o:i -> Type0) (x:i) (input:bytes)
    (g:graph_desc i o x)
    : Lemma (decode_graph_syntax x input == Some g ==>
             input == encode_graph_syntax x g) = ()
