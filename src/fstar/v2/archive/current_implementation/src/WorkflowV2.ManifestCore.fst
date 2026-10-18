module WorkflowV2.ManifestCore

open FStar.List.Tot
open FStar.List.Tot.Properties
open WorkflowV2.Kernel

// Lexicographic order over canonical natural-number bytes. The local
// insertion sort below proves its laws structurally without Classical or
// Squash packaging.
let rec bytes_lex_le (xs ys:bytes) : Tot bool (decreases xs) =
  match xs, ys with
  | [], _ -> true
  | _::_, [] -> false
  | x::xt, y::yt ->
      if x < y then true else if y < x then false else bytes_lex_le xt yt

let rec bytes_lex_reflexive (xs:bytes)
    : Lemma (ensures bytes_lex_le xs xs) (decreases xs) =
  match xs with | [] -> () | _::tail -> bytes_lex_reflexive tail

let rec bytes_lex_antisymmetric (xs ys:bytes)
    : Lemma (requires bytes_lex_le xs ys /\ bytes_lex_le ys xs)
            (ensures xs == ys) (decreases xs) =
  match xs, ys with
  | [], [] -> ()
  | [], _::_ -> ()
  | _::_, [] -> ()
  | x::xt, y::yt ->
      if x < y then () else if y < x then () else bytes_lex_antisymmetric xt yt

let rec bytes_lex_transitive (xs ys zs:bytes)
    : Lemma (requires bytes_lex_le xs ys /\ bytes_lex_le ys zs)
            (ensures bytes_lex_le xs zs) (decreases xs) =
  match xs, ys, zs with
  | [], _, _ -> ()
  | _::_, [], _ -> ()
  | _::_, _::_, [] -> ()
  | x::xt, y::yt, z::zt ->
      if x < y then
        (if y < z then () else if z < y then assert False else ())
      else if y < x then assert False
      else begin
        assert (x == y);
        if y < z then ()
        else if z < y then assert False
        else begin
          assert (bytes_lex_le xt yt);
          assert (bytes_lex_le yt zt);
          bytes_lex_transitive xt yt zt;
          ()
        end
      end

let rec bytes_lex_total (xs ys:bytes)
    : Lemma (ensures bytes_lex_le xs ys \/ bytes_lex_le ys xs)
            (decreases xs) =
  match xs, ys with
  | [], _ -> ()
  | _::_, [] -> ()
  | x::xt, y::yt ->
      if x < y then () else if y < x then () else bytes_lex_total xt yt

// ManifestCore is first-order durable syntax. It contains identities,
// versioned metadata, and canonical schema-syntax bytes; never closures,
// package proofs, or host artifact handles.

type manifest_identity =
  | ManifestCodeIdentity:code_identity -> manifest_identity
  | ManifestOperationIdentity:operation_identity -> manifest_identity
  | ManifestGeneratorIdentity:generator_identity -> manifest_identity
  | ManifestCodecIdentity:codec_identity -> manifest_identity
  | ManifestArtifactTypeIdentity:artifact_type_identity -> manifest_identity
  | ManifestArtifactStoreIdentity:artifact_store_identity -> manifest_identity
  | ManifestChargeMetricIdentity:charge_metric_identity -> manifest_identity
  | ManifestGraphCodecIdentity:graph_codec_identity -> manifest_identity
  | ManifestSchemaFamilyIdentity:schema_identity -> manifest_identity
  | ManifestSchemaRuleIdentity:schema_identity -> manifest_identity
  | ManifestResolverIdentity:resolver_identity -> manifest_identity
  | ManifestRootEntryIdentity:root_entry_identity -> manifest_identity

type contract_kind =
  | ValidatorContract
  | AdapterContract
  | ConfigurationContract
  | AllocationContract
  | CodecVersionContract
  | DenotationLawContract
  | ArtifactInterpretationContract
  | ResourceProjectionLawContract

type manifest_contract_ref = {
  contract_ref_kind:contract_kind;
  contract_ref_identity:contract_identity
}

// These values are syntax-level references and metadata, not a general
// reflection mechanism. Schema syntax bytes are parsed and checked by the
// later Schema module; ManifestCore commits to their exact bytes.
type manifest_value =
  | ManifestNatValue:nat -> manifest_value
  | ManifestBytesValue:bytes -> manifest_value
  | ManifestLabelValue:identity_token -> manifest_value
  | ManifestIdentityValue:manifest_identity -> manifest_value
  | ManifestContractValue:manifest_contract_ref -> manifest_value
  | ManifestSchemaSyntaxValue:bytes -> manifest_value
  | ManifestValueCodecMode:manifest_value
  | ManifestIndexedCodecMode:manifest_value

type manifest_entry = {
  manifest_entry_identity:manifest_identity;
  manifest_entry_fields:list manifest_value
}

type registry_manifest = {
  manifest_format_version:nat;
  manifest_entries:list manifest_entry
}

let manifest_identity_tag (id:manifest_identity) : nat =
  match id with
  | ManifestCodeIdentity _ -> 0
  | ManifestOperationIdentity _ -> 1
  | ManifestGeneratorIdentity _ -> 2
  | ManifestCodecIdentity _ -> 3
  | ManifestArtifactTypeIdentity _ -> 4
  | ManifestArtifactStoreIdentity _ -> 5
  | ManifestChargeMetricIdentity _ -> 6
  | ManifestGraphCodecIdentity _ -> 7
  | ManifestSchemaFamilyIdentity _ -> 8
  | ManifestSchemaRuleIdentity _ -> 9
  | ManifestResolverIdentity _ -> 10
  | ManifestRootEntryIdentity _ -> 11

let manifest_identity_payload (id:manifest_identity) : bytes =
  match id with
  | ManifestCodeIdentity x -> enc_code_identity x
  | ManifestOperationIdentity x -> enc_operation_identity x
  | ManifestGeneratorIdentity x -> enc_generator_identity x
  | ManifestCodecIdentity x -> enc_codec_identity x
  | ManifestArtifactTypeIdentity x -> enc_artifact_type_identity x
  | ManifestArtifactStoreIdentity x -> enc_artifact_store_identity x
  | ManifestChargeMetricIdentity x -> enc_charge_metric_identity x
  | ManifestGraphCodecIdentity x -> enc_graph_codec_identity x
  | ManifestSchemaFamilyIdentity x -> enc_schema_identity x
  | ManifestSchemaRuleIdentity x -> enc_schema_identity x
  | ManifestResolverIdentity x -> enc_resolver_identity x
  | ManifestRootEntryIdentity x -> enc_root_entry_identity x

// Identity encoding is tag followed by one length-framed identity payload.
// The framing makes each tagged identity a prefix-free canonical sort key.
let manifest_identity_encoding (id:manifest_identity) : bytes =
  enc_nat (manifest_identity_tag id) @
  enc_seq (manifest_identity_payload id)

let dec_manifest_identity_payload (tag:nat) (payload:bytes)
    : option manifest_identity =
  match tag with
  | 0 -> (match dec_code_identity payload with
         | Some (x, []) -> Some (ManifestCodeIdentity x) | _ -> None)
  | 1 -> (match dec_operation_identity payload with
         | Some (x, []) -> Some (ManifestOperationIdentity x) | _ -> None)
  | 2 -> (match dec_generator_identity payload with
         | Some (x, []) -> Some (ManifestGeneratorIdentity x) | _ -> None)
  | 3 -> (match dec_codec_identity payload with
         | Some (x, []) -> Some (ManifestCodecIdentity x) | _ -> None)
  | 4 -> (match dec_artifact_type_identity payload with
         | Some (x, []) -> Some (ManifestArtifactTypeIdentity x) | _ -> None)
  | 5 -> (match dec_artifact_store_identity payload with
         | Some (x, []) -> Some (ManifestArtifactStoreIdentity x) | _ -> None)
  | 6 -> (match dec_charge_metric_identity payload with
         | Some (x, []) -> Some (ManifestChargeMetricIdentity x) | _ -> None)
  | 7 -> (match dec_graph_codec_identity payload with
         | Some (x, []) -> Some (ManifestGraphCodecIdentity x) | _ -> None)
  | 8 -> (match dec_schema_identity payload with
         | Some (x, []) -> Some (ManifestSchemaFamilyIdentity x) | _ -> None)
  | 9 -> (match dec_schema_identity payload with
         | Some (x, []) -> Some (ManifestSchemaRuleIdentity x) | _ -> None)
  | 10 -> (match dec_resolver_identity payload with
          | Some (x, []) -> Some (ManifestResolverIdentity x) | _ -> None)
  | 11 -> (match dec_root_entry_identity payload with
          | Some (x, []) -> Some (ManifestRootEntryIdentity x) | _ -> None)
  | _ -> None

let dec_manifest_identity (input:bytes)
    : option (manifest_identity & bytes) =
  match dec_nat input with
  | None -> None
  | Some (tag, tail) ->
      match dec_len_seq tail with
      | None -> None
      | Some (payload, rest) ->
          match dec_manifest_identity_payload tag payload with
          | None -> None
          | Some id -> Some (id, rest)

let manifest_identity_payload_decode (id:manifest_identity)
    : Lemma (dec_manifest_identity_payload
       (manifest_identity_tag id) (manifest_identity_payload id) == Some id) =
  match id with
  | ManifestCodeIdentity x ->
      code_identity_decode_encoding_suffix x [];
      assert (dec_code_identity (enc_code_identity x) == Some (x, [])); ()
  | ManifestOperationIdentity x ->
      operation_identity_decode_encoding_suffix x [];
      assert (dec_operation_identity (enc_operation_identity x) == Some (x, [])); ()
  | ManifestGeneratorIdentity x ->
      generator_identity_decode_encoding_suffix x [];
      assert (dec_generator_identity (enc_generator_identity x) == Some (x, [])); ()
  | ManifestCodecIdentity x ->
      codec_identity_decode_encoding_suffix x [];
      assert (dec_codec_identity (enc_codec_identity x) == Some (x, [])); ()
  | ManifestArtifactTypeIdentity x ->
      artifact_type_identity_decode_encoding_suffix x [];
      assert (dec_artifact_type_identity (enc_artifact_type_identity x) == Some (x, [])); ()
  | ManifestArtifactStoreIdentity x ->
      artifact_store_identity_decode_encoding_suffix x [];
      assert (dec_artifact_store_identity (enc_artifact_store_identity x) == Some (x, [])); ()
  | ManifestChargeMetricIdentity x ->
      charge_metric_identity_decode_encoding_suffix x [];
      assert (dec_charge_metric_identity (enc_charge_metric_identity x) == Some (x, [])); ()
  | ManifestGraphCodecIdentity x ->
      graph_codec_identity_decode_encoding_suffix x [];
      assert (dec_graph_codec_identity (enc_graph_codec_identity x) == Some (x, [])); ()
  | ManifestSchemaFamilyIdentity x ->
      schema_identity_decode_encoding_suffix x [];
      assert (dec_schema_identity (enc_schema_identity x) == Some (x, [])); ()
  | ManifestSchemaRuleIdentity x ->
      schema_identity_decode_encoding_suffix x [];
      assert (dec_schema_identity (enc_schema_identity x) == Some (x, [])); ()
  | ManifestResolverIdentity x ->
      resolver_identity_decode_encoding_suffix x [];
      assert (dec_resolver_identity (enc_resolver_identity x) == Some (x, [])); ()
  | ManifestRootEntryIdentity x ->
      root_entry_identity_decode_encoding_suffix x [];
      assert (dec_root_entry_identity (enc_root_entry_identity x) == Some (x, [])); ()

let manifest_identity_decode_encoding_suffix
    (id:manifest_identity) (suffix:bytes)
    : Lemma (dec_manifest_identity
       (manifest_identity_encoding id @ suffix) == Some (id, suffix)) =
  append_assoc_local (enc_nat (manifest_identity_tag id))
    (enc_seq (manifest_identity_payload id)) suffix;
  assert (dec_nat (enc_nat (manifest_identity_tag id) @
    (enc_seq (manifest_identity_payload id) @ suffix)) ==
    Some (manifest_identity_tag id, enc_seq (manifest_identity_payload id) @ suffix));
  sequence_decode_encoding_suffix (manifest_identity_payload id) suffix;
  manifest_identity_payload_decode id;
  assert (dec_manifest_identity_payload (manifest_identity_tag id)
    (manifest_identity_payload id) == Some id);
  ()

let manifest_identity_encode_injective (left right:manifest_identity)
    (h:manifest_identity_encoding left == manifest_identity_encoding right)
    : Lemma (left == right) =
  manifest_identity_decode_encoding_suffix left [];
  manifest_identity_decode_encoding_suffix right [];
  ()

let contract_kind_tag (kind:contract_kind) : nat =
  match kind with
  | ValidatorContract -> 0
  | AdapterContract -> 1
  | ConfigurationContract -> 2
  | AllocationContract -> 3
  | CodecVersionContract -> 4
  | DenotationLawContract -> 5
  | ArtifactInterpretationContract -> 6
  | ResourceProjectionLawContract -> 7

let dec_contract_kind (tag:nat) : option contract_kind =
  match tag with
  | 0 -> Some ValidatorContract
  | 1 -> Some AdapterContract
  | 2 -> Some ConfigurationContract
  | 3 -> Some AllocationContract
  | 4 -> Some CodecVersionContract
  | 5 -> Some DenotationLawContract
  | 6 -> Some ArtifactInterpretationContract
  | 7 -> Some ResourceProjectionLawContract
  | _ -> None

let enc_manifest_contract_ref (r:manifest_contract_ref) : bytes =
  enc_nat (contract_kind_tag r.contract_ref_kind) @
  enc_contract_identity r.contract_ref_identity

let dec_manifest_contract_ref (input:bytes)
    : option (manifest_contract_ref & bytes) =
  match dec_nat input with
  | None -> None
  | Some (tag, tail) ->
      match dec_contract_kind tag with
      | None -> None
      | Some kind ->
          match dec_contract_identity tail with
          | None -> None
          | Some (id, rest) ->
              Some ({contract_ref_kind=kind; contract_ref_identity=id}, rest)

let contract_kind_decode_encoding (kind:contract_kind)
    : Lemma (dec_contract_kind (contract_kind_tag kind) == Some kind) = ()

let manifest_contract_ref_decode_encoding_suffix
    (r:manifest_contract_ref) (suffix:bytes)
    : Lemma (dec_manifest_contract_ref
      (enc_manifest_contract_ref r @ suffix) == Some (r, suffix)) =
  contract_kind_decode_encoding r.contract_ref_kind;
  contract_identity_decode_encoding_suffix r.contract_ref_identity suffix;
  ()

let manifest_contract_ref_encode_injective
    (left right:manifest_contract_ref)
    (h:enc_manifest_contract_ref left == enc_manifest_contract_ref right)
    : Lemma (left == right) =
  manifest_contract_ref_decode_encoding_suffix left [];
  manifest_contract_ref_decode_encoding_suffix right [];
  ()

let enc_manifest_value (v:manifest_value) : bytes =
  match v with
  | ManifestNatValue n -> enc_nat 0 @ enc_nat n
  | ManifestBytesValue b -> enc_nat 1 @ enc_seq b
  | ManifestLabelValue token -> enc_nat 2 @ enc_identity_token token
  | ManifestIdentityValue id -> enc_nat 3 @ manifest_identity_encoding id
  | ManifestContractValue r -> enc_nat 4 @ enc_manifest_contract_ref r
  | ManifestSchemaSyntaxValue b -> enc_nat 5 @ enc_seq b
  | ManifestValueCodecMode -> enc_nat 6
  | ManifestIndexedCodecMode -> enc_nat 7

let dec_manifest_value (input:bytes) : option manifest_value =
  match dec_nat input with
  | None -> None
  | Some (tag, tail) ->
      match tag with
      | 0 -> (match dec_nat tail with
             | Some (n, []) -> Some (ManifestNatValue n)
             | _ -> None)
      | 1 -> (match dec_len_seq tail with
             | Some (b, []) -> Some (ManifestBytesValue b)
             | _ -> None)
      | 2 -> (match dec_identity_token tail with
             | Some (token, []) -> Some (ManifestLabelValue token)
             | _ -> None)
      | 3 -> (match dec_manifest_identity tail with
             | Some (id, []) -> Some (ManifestIdentityValue id)
             | _ -> None)
      | 4 -> (match dec_manifest_contract_ref tail with
             | Some (r, []) -> Some (ManifestContractValue r)
             | _ -> None)
      | 5 -> (match dec_len_seq tail with
             | Some (b, []) -> Some (ManifestSchemaSyntaxValue b)
             | _ -> None)
      | 6 -> if tail = [] then Some ManifestValueCodecMode else None
      | 7 -> if tail = [] then Some ManifestIndexedCodecMode else None
      | _ -> None

let manifest_value_decode_encoding (v:manifest_value)
    : Lemma (dec_manifest_value (enc_manifest_value v) == Some v) =
  match v with
  | ManifestNatValue n ->
      assert (dec_nat (enc_nat n) == Some (n, []));
      assert (dec_manifest_value (enc_manifest_value (ManifestNatValue n)) ==
              Some (ManifestNatValue n));
      ()
  | ManifestBytesValue b ->
      sequence_decode_encoding b;
      assert (dec_manifest_value (enc_manifest_value (ManifestBytesValue b)) ==
              Some (ManifestBytesValue b));
      ()
  | ManifestLabelValue token ->
      identity_token_decode_encoding token;
      assert (dec_manifest_value (enc_manifest_value (ManifestLabelValue token)) ==
              Some (ManifestLabelValue token));
      ()
  | ManifestIdentityValue id ->
      manifest_identity_decode_encoding_suffix id [];
      assert (dec_manifest_value (enc_manifest_value
        (ManifestIdentityValue id)) == Some (ManifestIdentityValue id));
      ()
  | ManifestContractValue r ->
      manifest_contract_ref_decode_encoding_suffix r [];
      assert (dec_manifest_value (enc_manifest_value
        (ManifestContractValue r)) == Some (ManifestContractValue r));
      ()
  | ManifestSchemaSyntaxValue b ->
      sequence_decode_encoding b;
      assert (dec_manifest_value (enc_manifest_value
        (ManifestSchemaSyntaxValue b)) == Some (ManifestSchemaSyntaxValue b));
      ()
  | ManifestValueCodecMode -> ()
  | ManifestIndexedCodecMode -> ()

let manifest_value_encode_injective (left right:manifest_value)
    (h:enc_manifest_value left == enc_manifest_value right)
    : Lemma (left == right) =
  manifest_value_decode_encoding left;
  manifest_value_decode_encoding right;
  ()

let rec enc_manifest_values (vs:list manifest_value) : bytes =
  match vs with
  | [] -> []
  | v::tail -> enc_seq (enc_manifest_value v) @ enc_manifest_values tail

let rec dec_manifest_values (count:nat) (input:bytes)
    : Tot (option (list manifest_value & bytes)) (decreases count) =
  if count = 0 then Some ([], input)
  else match dec_len_seq input with
       | None -> None
       | Some (field, tail) ->
           match dec_manifest_value field with
           | None -> None
           | Some value ->
               match dec_manifest_values (count - 1) tail with
               | None -> None
               | Some (values, rest) -> Some (value::values, rest)

let dec_manifest_values_equation (count:nat) (input:bytes)
    : Lemma (dec_manifest_values count input ==
      (if count = 0 then Some ([], input)
       else match dec_len_seq input with
            | None -> None
            | Some (field, tail) ->
                match dec_manifest_value field with
                | None -> None
                | Some value ->
                    match dec_manifest_values (count - 1) tail with
                    | None -> None
                    | Some (values, rest) -> Some (value::values, rest))) = ()

let rec manifest_values_decode_encoding_suffix
    (vs:list manifest_value) (suffix:bytes)
    : Lemma (ensures (dec_manifest_values (length vs)
       (enc_manifest_values vs @ suffix) == Some (vs, suffix)))
    (decreases vs) =
  match vs with
  | [] -> ()
  | value::tail ->
      dec_manifest_values_equation (length (value::tail))
        (enc_manifest_values (value::tail) @ suffix);
      assert (length (value::tail) > 0);
      assert (enc_manifest_values (value::tail) ==
        enc_seq (enc_manifest_value value) @ enc_manifest_values tail);
      append_assoc_local (enc_seq (enc_manifest_value value))
        (enc_manifest_values tail) suffix;
      sequence_decode_encoding_suffix (enc_manifest_value value)
        (enc_manifest_values tail @ suffix);
      manifest_value_decode_encoding value;
      manifest_values_decode_encoding_suffix tail suffix;
      assert (dec_len_seq (enc_seq (enc_manifest_value value) @
        (enc_manifest_values tail @ suffix)) ==
        Some (enc_manifest_value value, enc_manifest_values tail @ suffix));
      assert (dec_manifest_value (enc_manifest_value value) == Some value);
      assert (length (value::tail) - 1 == length tail);
      assert (dec_manifest_values (length (value::tail) - 1)
        (enc_manifest_values tail @ suffix) == Some (tail, suffix));
      assert (dec_manifest_values (length (value::tail))
        (enc_manifest_values (value::tail) @ suffix) ==
        Some (value::tail, suffix))

let is_codec_value (v:manifest_value) : bool =
  match v with
  | ManifestIdentityValue (ManifestCodecIdentity _) -> true
  | _ -> false

let is_schema_family_value (v:manifest_value) : bool =
  match v with
  | ManifestIdentityValue (ManifestSchemaFamilyIdentity _) -> true
  | _ -> false

let is_graph_codec_value (v:manifest_value) : bool =
  match v with
  | ManifestIdentityValue (ManifestGraphCodecIdentity _) -> true
  | _ -> false

let is_metric_value (v:manifest_value) : bool =
  match v with
  | ManifestIdentityValue (ManifestChargeMetricIdentity _) -> true
  | _ -> false

let is_artifact_store_value (v:manifest_value) : bool =
  match v with
  | ManifestIdentityValue (ManifestArtifactStoreIdentity _) -> true
  | _ -> false

let rec manifest_identity_present (id:manifest_identity)
    (entries:list manifest_entry) : Tot (option manifest_entry)
    (decreases entries) =
  match entries with
  | [] -> None
  | entry::tail ->
      if entry.manifest_entry_identity = id
      then Some entry
      else manifest_identity_present id tail

let is_codec_mode (mode:manifest_value) (entry:manifest_entry) : bool =
  match mode, entry.manifest_entry_fields with
  | ManifestValueCodecMode, ManifestValueCodecMode::_ -> true
  | ManifestIndexedCodecMode, ManifestIndexedCodecMode::_ -> true
  | _, _ -> false

let codec_target_has_mode (v:manifest_value) (mode:manifest_value)
    (entries:list manifest_entry) : bool =
  match v with
  | ManifestIdentityValue (ManifestCodecIdentity id) ->
      (match manifest_identity_present (ManifestCodecIdentity id) entries with
       | None -> false
       | Some target -> is_codec_mode mode target)
  | _ -> false

let codec_row_schemas (v:manifest_value)
    (entries:list manifest_entry) : option (list manifest_value) =
  match v with
  | ManifestIdentityValue (ManifestCodecIdentity id) ->
      (match manifest_identity_present (ManifestCodecIdentity id) entries with
       | None -> None
       | Some target ->
           match target.manifest_entry_fields with
           | [ManifestValueCodecMode; schema; _] -> Some [schema]
           | [ManifestIndexedCodecMode; input_schema; output_schema; _] ->
               Some [input_schema; output_schema]
           | _ -> None)
  | _ -> None

let graph_codec_row_schemas (v:manifest_value)
    (entries:list manifest_entry) : option (list manifest_value) =
  match v with
  | ManifestIdentityValue (ManifestGraphCodecIdentity id) ->
      (match manifest_identity_present (ManifestGraphCodecIdentity id) entries with
       | None -> None
       | Some target ->
           match target.manifest_entry_fields with
           | [input_schema; output_schema; _] ->
               Some [input_schema; output_schema]
           | _ -> None)
  | _ -> None

let schemas_match_codec (codec:manifest_value)
    (schemas:list manifest_value) (entries:list manifest_entry) : bool =
  codec_row_schemas codec entries = Some schemas

let schemas_match_graph_codec (codec:manifest_value)
    (schemas:list manifest_value) (entries:list manifest_entry) : bool =
  graph_codec_row_schemas codec entries = Some schemas

let contract_kind_is (kind:contract_kind) (v:manifest_value) : bool =
  match v with
  | ManifestContractValue r -> r.contract_ref_kind = kind
  | _ -> false

let manifest_entry_fields_well_formed (entry:manifest_entry) : bool =
  match entry.manifest_entry_identity with
  | ManifestCodeIdentity _ ->
      (match entry.manifest_entry_fields with
       | [input_codec; output_codec; input_schema; output_schema;
          ManifestNatValue _] ->
           is_codec_value input_codec &&
           is_schema_family_value input_schema &&
           is_schema_family_value output_schema
       | _ -> false)


  | ManifestOperationIdentity _ ->
      (match entry.manifest_entry_fields with
       | [request_codec; result_codec; request_schema; result_schema;
          validator; adapter; configuration; metric; ManifestNatValue _] ->
           is_codec_value request_codec &&
           is_schema_family_value request_schema &&
           is_schema_family_value result_schema &&
           contract_kind_is ValidatorContract validator &&
           contract_kind_is AdapterContract adapter &&
           contract_kind_is ConfigurationContract configuration &&
           is_metric_value metric
       | _ -> false)
  | ManifestGeneratorIdentity _ ->
      (match entry.manifest_entry_fields with
       | [input_codec; input_schema; graph_codec; result_schema;
          allocation_contract] ->
           is_codec_value input_codec && is_schema_family_value input_schema &&
           is_graph_codec_value graph_codec &&
           is_schema_family_value result_schema &&
           contract_kind_is AllocationContract allocation_contract
       | _ -> false)
  | ManifestCodecIdentity _ ->
      (match entry.manifest_entry_fields with
       | [ManifestValueCodecMode; schema; codec_version] ->
           is_schema_family_value schema &&
           contract_kind_is CodecVersionContract codec_version
       | [ManifestIndexedCodecMode; input_schema; output_schema;
          codec_version] ->
           is_schema_family_value input_schema &&
           is_schema_family_value output_schema &&
           contract_kind_is CodecVersionContract codec_version
       | _ -> false)
  | ManifestArtifactTypeIdentity _ ->
      (match entry.manifest_entry_fields with
       | [schema; reference_codec; store; interpretation; projection_law] ->
           is_schema_family_value schema && is_codec_value reference_codec &&
           is_artifact_store_value store &&
           contract_kind_is ArtifactInterpretationContract interpretation &&
           contract_kind_is ResourceProjectionLawContract projection_law
       | _ -> false)
  | ManifestArtifactStoreIdentity _ ->
      (match entry.manifest_entry_fields with
       | [ManifestNatValue _] -> true
       | _ -> false)
  | ManifestChargeMetricIdentity _ ->
      (match entry.manifest_entry_fields with
       | [ManifestLabelValue _; ManifestNatValue _] -> true
       | _ -> false)
  | ManifestGraphCodecIdentity _ ->
      (match entry.manifest_entry_fields with
       | [input_schema; output_schema; ManifestNatValue _] ->
           is_schema_family_value input_schema &&
           is_schema_family_value output_schema
       | _ -> false)
  | ManifestSchemaFamilyIdentity _ ->
      (match entry.manifest_entry_fields with
       | [ManifestSchemaSyntaxValue _; law] ->
           contract_kind_is DenotationLawContract law
       | _ -> false)
  | ManifestSchemaRuleIdentity _ ->
      (match entry.manifest_entry_fields with
       | [ManifestSchemaSyntaxValue _; law] ->
           contract_kind_is DenotationLawContract law
       | _ -> false)
  | ManifestResolverIdentity _ ->
      (match entry.manifest_entry_fields with
       | [ManifestNatValue _] -> true
       | _ -> false)
  | ManifestRootEntryIdentity _ ->
      (match entry.manifest_entry_fields with
       | [input_codec; graph_codec; result_schema; ManifestNatValue _] ->
           is_codec_value input_codec && is_graph_codec_value graph_codec &&
           is_schema_family_value result_schema
       | _ -> false)


let rec entries_fields_well_formed (entries:list manifest_entry) : bool =
  match entries with
  | [] -> true
  | entry::tail ->
      manifest_entry_fields_well_formed entry &&
      entries_fields_well_formed tail

let rec identity_occurs (id:manifest_identity)
    (entries:list manifest_entry) : bool =
  match entries with
  | [] -> false
  | entry::tail ->
      entry.manifest_entry_identity = id || identity_occurs id tail

// This recursive check rejects repeated IDs even when both serialized rows
// are byte-for-byte equal. It never silently deduplicates conflicting rows.
let rec entries_ids_unique (entries:list manifest_entry) : bool =
  match entries with
  | [] -> true
  | entry::tail ->
      not (identity_occurs entry.manifest_entry_identity tail) &&
      entries_ids_unique tail

let rec identity_occurs_for_member (id:manifest_identity)
    (entries:list manifest_entry) (selected:manifest_entry)
    : Lemma (requires mem selected entries /\
                      selected.manifest_entry_identity = id)
            (ensures identity_occurs id entries)
            (decreases entries) =
  match entries with
  | [] -> ()
  | head::tail ->
      if head = selected then
        assert (head.manifest_entry_identity = id)
      else identity_occurs_for_member id tail selected

let rec entries_ids_unique_implies_no_repeats
    (entries:list manifest_entry)
    : Lemma (requires entries_ids_unique entries)
            (ensures noRepeats entries)
            (decreases entries) =
  match entries with
  | [] -> noRepeats_nil #manifest_entry; ()
  | head::tail ->
      assert (entries_ids_unique tail);
      entries_ids_unique_implies_no_repeats tail;
      if mem head tail then begin
        identity_occurs_for_member head.manifest_entry_identity tail head;
        assert False
      end;
      noRepeats_cons head tail;
      ()

let rec manifest_identity_present_member (id:manifest_identity)
    (entries:list manifest_entry) (selected:manifest_entry)
    : Lemma
      (requires manifest_identity_present id entries == Some selected)
      (ensures mem selected entries /\ selected.manifest_entry_identity = id)
      (decreases entries) =
  match entries with
  | [] -> ()
  | entry::tail ->
      if entry.manifest_entry_identity = id then begin
        assert (selected == entry);
        assert (mem selected (entry::tail));
        ()
      end else begin
        manifest_identity_present_member id tail selected;
        assert (mem selected (entry::tail));
        ()
      end

let rec manifest_identity_present_unique (id:manifest_identity)
    (entries:list manifest_entry) (selected candidate:manifest_entry)
    : Lemma
      (requires entries_ids_unique entries /\
        manifest_identity_present id entries == Some selected /\
        mem candidate entries /\ candidate.manifest_entry_identity = id)
      (ensures candidate == selected)
      (decreases entries) =
  match entries with
  | [] -> ()
  | entry::tail ->
      if entry.manifest_entry_identity = id then begin
        assert (selected == entry);
        if candidate = entry then () else begin
          assert (mem candidate tail);
          identity_occurs_for_member id tail candidate;
          assert (identity_occurs id tail);
          assert (not (identity_occurs entry.manifest_entry_identity tail));
          assert False
        end
      end else begin
        assert (candidate <> entry);
        assert (mem candidate tail);
        assert (entries_ids_unique tail);
        manifest_identity_present_unique id tail selected candidate;
        ()
      end

let rec manifest_value_references (fields:list manifest_value)
    : list manifest_identity =
  match fields with
  | [] -> []
  | ManifestIdentityValue id :: tail ->
      id :: manifest_value_references tail
  | _ :: tail -> manifest_value_references tail

let rec manifest_references_closed (references:list manifest_identity)
    (entries:list manifest_entry) : bool =
  match references with
  | [] -> true
  | id::tail ->
      (match manifest_identity_present id entries with
       | None -> false
       | Some _ -> manifest_references_closed tail entries)

let rec manifest_references_closed_target
    (id:manifest_identity) (references:list manifest_identity)
    (entries:list manifest_entry)
    : Lemma
      (requires manifest_references_closed references entries /\
        mem id references)
      (ensures exists target.
        manifest_identity_present id entries == Some target)
      (decreases references) =
  match references with
  | [] -> ()
  | head::tail ->
      if id = head then begin
        match manifest_identity_present id entries with
        | Some target -> ()
        | None -> ()
      end else begin
        assert (mem id tail);
        assert (manifest_references_closed tail entries);
        manifest_references_closed_target id tail entries;
        ()
      end

let manifest_entries_links_closed (entries:list manifest_entry) : bool =
  let rec check (remaining:list manifest_entry)
      : Tot bool (decreases remaining) =
    match remaining with
    | [] -> true
    | entry::tail ->
        manifest_references_closed
          (manifest_value_references entry.manifest_entry_fields) entries &&
        check tail
  in
  check entries

// Every identity-valued field must resolve to the same tagged identity in
// this manifest. Contract tokens are deliberately different: the v2 manifest
// names them in typed package positions, and A04 binds those positions to the
// actual proof-bearing validator/adapter/law packages. They are not standalone
// identity domains in the normative manifest tag set.
let manifest_entries_references_typed (entries:list manifest_entry) : bool =
  let rec check (remaining:list manifest_entry)
      : Tot bool (decreases remaining) =
    match remaining with
    | [] -> true
    | entry::tail ->
        let fields = entry.manifest_entry_fields in
        let links_ok =
          match entry.manifest_entry_identity, fields with
          | ManifestCodeIdentity _,
              [input_codec; output_codec; _; _; _] ->
              codec_target_has_mode input_codec ManifestValueCodecMode entries &&
              codec_target_has_mode output_codec ManifestIndexedCodecMode entries
          | ManifestOperationIdentity _,
              [request_codec; result_codec; _; _; _; _; _; metric; _] ->
              codec_target_has_mode request_codec ManifestValueCodecMode entries &&
              codec_target_has_mode result_codec ManifestIndexedCodecMode entries &&
              (match metric with
               | ManifestIdentityValue (ManifestChargeMetricIdentity id) ->
                   manifest_identity_present (ManifestChargeMetricIdentity id)
                     entries <> None
               | _ -> false)
          | ManifestGeneratorIdentity _,
              [input_codec; _; graph_codec; _; _] ->
              codec_target_has_mode input_codec ManifestValueCodecMode entries &&
              (match graph_codec with
               | ManifestIdentityValue (ManifestGraphCodecIdentity id) ->
                   manifest_identity_present (ManifestGraphCodecIdentity id)
                     entries <> None
               | _ -> false)
          | ManifestCodecIdentity _, _ -> true
          | ManifestArtifactTypeIdentity _,
              [_; reference_codec; store; _; _] ->
              codec_target_has_mode reference_codec ManifestValueCodecMode entries &&
              (match store with
               | ManifestIdentityValue (ManifestArtifactStoreIdentity id) ->
                   manifest_identity_present (ManifestArtifactStoreIdentity id)
                     entries <> None
               | _ -> false)
          | ManifestArtifactStoreIdentity _, _ -> true
          | ManifestChargeMetricIdentity _, _ -> true
          | ManifestGraphCodecIdentity _, [_; _; _] -> true
          | ManifestSchemaFamilyIdentity _, _ -> true
          | ManifestSchemaRuleIdentity _, _ -> true
          | ManifestResolverIdentity _, _ -> true
          | ManifestRootEntryIdentity _,
              [input_codec; graph_codec; _; _] ->
              codec_target_has_mode input_codec ManifestValueCodecMode entries &&
              (match graph_codec with
               | ManifestIdentityValue (ManifestGraphCodecIdentity id) ->
                   manifest_identity_present (ManifestGraphCodecIdentity id)
                     entries <> None
               | _ -> false)
          | _ -> false
        in
        links_ok && check tail
  in
  check entries

// First-order linked schema equations are checked here. A04/P0 still proves
// that each schema token denotes the exact package carrier and that callbacks
// or codecs implement these declarations.
let manifest_entries_links_coherent (entries:list manifest_entry) : bool =
  let rec check (remaining:list manifest_entry)
      : Tot bool (decreases remaining) =
    match remaining with
    | [] -> true
    | entry::tail ->
        let fields = entry.manifest_entry_fields in
        let coherent =
          match entry.manifest_entry_identity, fields with
          | ManifestCodeIdentity _,
              [input_codec; output_codec; input_schema; output_schema; _] ->
              schemas_match_codec input_codec [input_schema] entries &&
              schemas_match_codec output_codec
                [input_schema; output_schema] entries
          | ManifestOperationIdentity _,
              [request_codec; result_codec; request_schema; result_schema;
               _; _; _; _; _] ->
              schemas_match_codec request_codec [request_schema] entries &&
              schemas_match_codec result_codec
                [request_schema; result_schema] entries
          | ManifestGeneratorIdentity _,
              [input_codec; input_schema; graph_codec; result_schema; _] ->
              schemas_match_codec input_codec [input_schema] entries &&
              schemas_match_graph_codec graph_codec
                [input_schema; result_schema] entries
          | ManifestRootEntryIdentity _,
              [input_codec; graph_codec; result_schema; _] ->
              (match codec_row_schemas input_codec entries with
               | Some [input_schema] ->
                   schemas_match_graph_codec graph_codec
                     [input_schema; result_schema] entries
               | _ -> false)
          | ManifestArtifactTypeIdentity _,
              [logical_schema; reference_codec; _; _; _] ->
              schemas_match_codec reference_codec [logical_schema] entries
          | _ -> true
        in
        coherent && check tail
  in
  check entries

let enc_manifest_entry (entry:manifest_entry) : bytes =
  manifest_identity_encoding entry.manifest_entry_identity @
  enc_nat (length entry.manifest_entry_fields) @
  enc_manifest_values entry.manifest_entry_fields

let dec_manifest_entry (input:bytes)
    : option (manifest_entry & bytes) =
  match dec_manifest_identity input with
  | None -> None
  | Some (id, tail) ->
      match dec_nat tail with
      | None -> None
      | Some (field_count, tail2) ->
          match dec_manifest_values field_count tail2 with
          | None -> None
          | Some (fields, rest) ->
              Some ({manifest_entry_identity=id;
                     manifest_entry_fields=fields}, rest)

let manifest_entry_decode_encoding_suffix
    (entry:manifest_entry) (suffix:bytes)
    : Lemma (dec_manifest_entry (enc_manifest_entry entry @ suffix) ==
             Some (entry, suffix)) =
  append_assoc_local (manifest_identity_encoding
      entry.manifest_entry_identity)
    (enc_nat (length entry.manifest_entry_fields) @
     enc_manifest_values entry.manifest_entry_fields) suffix;
  append_assoc_local (enc_nat (length entry.manifest_entry_fields))
    (enc_manifest_values entry.manifest_entry_fields) suffix;
  manifest_identity_decode_encoding_suffix entry.manifest_entry_identity
    (enc_nat (length entry.manifest_entry_fields) @
     enc_manifest_values entry.manifest_entry_fields @ suffix);
  assert (dec_nat (enc_nat (length entry.manifest_entry_fields) @
    (enc_manifest_values entry.manifest_entry_fields @ suffix)) ==
    Some (length entry.manifest_entry_fields,
      enc_manifest_values entry.manifest_entry_fields @ suffix));
  manifest_values_decode_encoding_suffix entry.manifest_entry_fields suffix;
  ()

let manifest_entry_encode_injective (left right:manifest_entry)
    : Lemma (requires enc_manifest_entry left == enc_manifest_entry right)
            (ensures left == right) =
  manifest_entry_decode_encoding_suffix left [];
  manifest_entry_decode_encoding_suffix right [];
  ()

// The primary sort component is the framed tagged identity encoding. The
// complete row encoding is a deterministic tie-break only for duplicate-ID
// input, which canonicalization rejects before sorting.
let manifest_entry_sort_key (entry:manifest_entry) : bytes =
  manifest_identity_encoding entry.manifest_entry_identity @
  enc_manifest_entry entry

let manifest_entry_sort_key_decode (entry:manifest_entry)
    : Lemma (dec_manifest_identity (manifest_entry_sort_key entry) ==
      Some (entry.manifest_entry_identity,
            enc_manifest_entry entry)) =
  manifest_identity_decode_encoding_suffix
    entry.manifest_entry_identity
    (enc_manifest_entry entry)

let manifest_entry_sort_key_injective (left right:manifest_entry)
    : Lemma (requires manifest_entry_sort_key left ==
                      manifest_entry_sort_key right)
            (ensures left == right) =
  manifest_entry_sort_key_decode left;
  manifest_entry_sort_key_decode right;
  assert (left.manifest_entry_identity == right.manifest_entry_identity);
  assert (enc_manifest_entry left == enc_manifest_entry right);
  manifest_entry_encode_injective left right

let manifest_entry_encoding_le (left right:manifest_entry) : bool =
  bytes_lex_le (manifest_entry_sort_key left) (manifest_entry_sort_key right)

let compare_manifest_entries (left right:manifest_entry) : Tot int =
  if manifest_entry_encoding_le left right then -1 else 1

let manifest_entry_cmp_rel (left right:manifest_entry) : Tot bool =
  compare_manifest_entries left right < 0

let manifest_entry_cmp_refl (entry:manifest_entry)
    : Lemma (manifest_entry_cmp_rel entry entry) =
  bytes_lex_reflexive (manifest_entry_sort_key entry)

let manifest_entry_cmp_antisym (left right:manifest_entry)
    : Lemma (requires manifest_entry_cmp_rel left right /\
                      manifest_entry_cmp_rel right left)
            (ensures left == right) =
  assert (manifest_entry_encoding_le left right);
  assert (manifest_entry_encoding_le right left);
  bytes_lex_antisymmetric (manifest_entry_sort_key left)
    (manifest_entry_sort_key right);
  assert (manifest_entry_sort_key left == manifest_entry_sort_key right);
  manifest_entry_sort_key_injective left right

let manifest_entry_cmp_trans (left middle right:manifest_entry)
    : Lemma (requires manifest_entry_cmp_rel left middle /\
                      manifest_entry_cmp_rel middle right)
            (ensures manifest_entry_cmp_rel left right) =
  assert (manifest_entry_encoding_le left middle);
  assert (manifest_entry_encoding_le middle right);
  bytes_lex_transitive (manifest_entry_sort_key left)
    (manifest_entry_sort_key middle) (manifest_entry_sort_key right);
  assert (manifest_entry_cmp_rel left right)

let manifest_entry_cmp_total (left right:manifest_entry)
    : Lemma (manifest_entry_cmp_rel left right \/
             manifest_entry_cmp_rel right left) =
  bytes_lex_total (manifest_entry_sort_key left)
    (manifest_entry_sort_key right);
  assert (manifest_entry_cmp_rel left right \/
          manifest_entry_cmp_rel right left)

let rec manifest_entry_insert (entry:manifest_entry) (entries:list manifest_entry)
    : Tot (list manifest_entry) (decreases entries) =
  match entries with
  | [] -> [entry]
  | head::tail ->
      if manifest_entry_encoding_le entry head
      then entry::entries
      else head::manifest_entry_insert entry tail

let rec manifest_entry_insert_sorted (entry:manifest_entry)
    (entries:list manifest_entry)
    : Lemma
      (requires sorted (bool_of_compare compare_manifest_entries) entries)
      (ensures sorted (bool_of_compare compare_manifest_entries)
        (manifest_entry_insert entry entries))
      (decreases entries) =
  match entries with
  | [] -> ()
  | head::[] ->
      if manifest_entry_encoding_le entry head then ()
      else begin
        bytes_lex_total (manifest_entry_sort_key entry)
          (manifest_entry_sort_key head);
        assert (manifest_entry_encoding_le head entry);
        ()
      end
  | head::next::tail ->
      if manifest_entry_encoding_le entry head then ()
      else begin
        bytes_lex_total (manifest_entry_sort_key entry)
          (manifest_entry_sort_key head);
        assert (manifest_entry_encoding_le head entry);
        assert (manifest_entry_encoding_le head next);
        manifest_entry_insert_sorted entry (next::tail);
        match manifest_entry_insert entry (next::tail) with
        | [] -> ()
        | inserted_head::inserted_tail ->
          if manifest_entry_encoding_le entry next then
            bytes_lex_transitive (manifest_entry_sort_key head)
              (manifest_entry_sort_key entry)
              (manifest_entry_sort_key next)
          else begin
            bytes_lex_total (manifest_entry_sort_key entry)
              (manifest_entry_sort_key next);
            assert (manifest_entry_encoding_le next entry);
            bytes_lex_transitive (manifest_entry_sort_key head)
              (manifest_entry_sort_key next)
              (manifest_entry_sort_key entry)
          end;
          ()
      end

let manifest_entry_count_cons_elim (x head:manifest_entry)
    (tail:list manifest_entry)
    : Lemma (count x (head::tail) ==
      (if x = head then 1 + count x tail else count x tail)) = ()

let rec manifest_entry_insert_counts (entry x:manifest_entry)
    (entries:list manifest_entry)
    : Lemma (ensures count x (manifest_entry_insert entry entries) ==
             count x (entry::entries)) (decreases entries) =
  match entries with
  | [] -> ()
  | head::tail ->
      if manifest_entry_encoding_le entry head then ()
      else begin
        manifest_entry_insert_counts entry x tail;
        manifest_entry_count_cons_elim x head
          (manifest_entry_insert entry tail);
        manifest_entry_count_cons_elim x head tail;
        ()
      end

let rec sort_manifest_entries (entries:list manifest_entry)
    : Tot (list manifest_entry) (decreases entries) =
  match entries with
  | [] -> []
  | head::tail -> manifest_entry_insert head (sort_manifest_entries tail)

let rec sort_manifest_entries_sorted (entries:list manifest_entry)
    : Lemma (ensures sorted (bool_of_compare compare_manifest_entries)
       (sort_manifest_entries entries)) (decreases entries) =
  match entries with
  | [] -> ()
  | head::tail ->
      sort_manifest_entries_sorted tail;
      manifest_entry_insert_sorted head (sort_manifest_entries tail)

let rec sort_manifest_entries_counts (entries:list manifest_entry)
    (x:manifest_entry)
    : Lemma (ensures count x entries == count x (sort_manifest_entries entries))
      (decreases entries) =
  match entries with
  | [] -> ()
  | head::tail ->
      sort_manifest_entries_counts tail x;
      manifest_entry_insert_counts head x (sort_manifest_entries tail);
      manifest_entry_count_cons_elim x head tail;
      ()

let manifest_no_repeats_tail (#a:eqtype) (head:a) (tail:list a)
    : Lemma (requires noRepeats (head::tail)) (ensures noRepeats tail) = ()

let manifest_head_not_in_tail (#a:eqtype) (head:a) (tail:list a)
    : Lemma (requires noRepeats (head::tail))
            (ensures not (mem head tail)) = ()

let count_cons_elim (#a:eqtype) (x head:a) (tail:list a)
    : Lemma (ensures (count x (head::tail) ==
      (if x = head then 1 + count x tail else count x tail))) = ()

let rec manifest_entry_no_repeats_count_bound
    (entries:list manifest_entry) (unique:unit{noRepeats entries})
    (x:manifest_entry)
    : Lemma (ensures count x entries <= 1) (decreases entries) =
  match entries with
  | [] -> ()
  | head::tail ->
      manifest_head_not_in_tail head tail;
      manifest_no_repeats_tail head tail;
      manifest_entry_no_repeats_count_bound tail () x;
      if x = head then begin
        mem_count tail head;
        assert (count head tail == 0);
        count_cons_elim head head tail;
        ()
      end else begin
        count_cons_elim x head tail;
        ()
      end

let rec count_bound_manifest_entries_no_repeats
    (entries:list manifest_entry)
    (bounded:(x:manifest_entry -> Lemma (ensures count x entries <= 1)))
    : Lemma (ensures noRepeats entries) (decreases entries) =
  match entries with
  | [] -> noRepeats_nil #manifest_entry; ()
  | head::tail ->
      bounded head;
      assert (count head (head::tail) <= 1);
      count_cons_elim head head tail;
      assert (count head (head::tail) == 1 + count head tail);
      assert (count head tail == 0);
      mem_count tail head;
      assert (~ (mem head tail));
      let tail_bounded (x:manifest_entry)
          : Lemma (ensures count x tail <= 1) =
        bounded x;
        count_cons_elim x head tail;
        if x = head then begin assert (count x tail == 0); () end
        else begin assert (count x tail == count x (head::tail)); () end
      in
      count_bound_manifest_entries_no_repeats tail tail_bounded;
      noRepeats_cons head tail

let sort_manifest_entries_preserves_no_repeats
    (entries:list manifest_entry) (unique:unit{noRepeats entries})
    : Lemma (ensures noRepeats (sort_manifest_entries entries)) =
  count_bound_manifest_entries_no_repeats (sort_manifest_entries entries)
    (fun x -> begin
      manifest_entry_no_repeats_count_bound entries unique x;
      sort_manifest_entries_counts entries x;
      ()
    end)

let rec manifest_entry_sorted_head_le_member
    (entries:list manifest_entry) (x:manifest_entry)
    : Lemma
      (requires sorted (bool_of_compare compare_manifest_entries) entries /\
        mem x entries)
      (ensures manifest_entry_cmp_rel (hd entries) x)
      (decreases entries) =
  match entries with
  | [] -> ()
  | head::[] -> manifest_entry_cmp_refl head
  | head::next::tail ->
      if x = head then manifest_entry_cmp_refl head
      else begin
        assert (manifest_entry_cmp_rel head next);
        assert (mem x (next::tail));
        if x = next then () else begin
          manifest_entry_sorted_head_le_member (next::tail) x;
          manifest_entry_cmp_trans head next x
        end
      end

let rec manifest_entry_count_positive_member
    (x:manifest_entry) (entries:list manifest_entry)
    : Lemma (requires count x entries > 0) (ensures mem x entries)
      (decreases entries) =
  match entries with
  | [] -> ()
  | head::tail ->
      if x = head then ()
      else manifest_entry_count_positive_member x tail

let sorted_manifest_entry_heads_equal
    (left_head right_head:manifest_entry)
    (left_tail right_tail:list manifest_entry)
    (same_counts:(key:manifest_entry -> Lemma
      (ensures count key (left_head::left_tail) ==
               count key (right_head::right_tail))))
    : Lemma
      (requires
        sorted (bool_of_compare compare_manifest_entries)
          (left_head::left_tail) /\
        sorted (bool_of_compare compare_manifest_entries)
          (right_head::right_tail))
      (ensures left_head == right_head) =
  assert (count left_head (left_head::left_tail) > 0);
  same_counts left_head;
  assert (count left_head (right_head::right_tail) > 0);
  manifest_entry_count_positive_member left_head (right_head::right_tail);
  same_counts right_head;
  assert (count right_head (left_head::left_tail) > 0);
  manifest_entry_count_positive_member right_head (left_head::left_tail);
  manifest_entry_sorted_head_le_member (right_head::right_tail) left_head;
  manifest_entry_sorted_head_le_member (left_head::left_tail) right_head;
  manifest_entry_cmp_antisym right_head left_head;
  ()

let manifest_entry_count_tails_equal
    (left_head right_head:manifest_entry)
    (left_tail right_tail:list manifest_entry)
    (same_counts:(key:manifest_entry -> Lemma
      (ensures count key (left_head::left_tail) ==
               count key (right_head::right_tail))))
    (same_head:unit{left_head == right_head})
    (left_unique:unit{noRepeats (left_head::left_tail)})
    (right_unique:unit{noRepeats (right_head::right_tail)})
    (key:manifest_entry)
    : Lemma (ensures count key left_tail == count key right_tail) =
  same_counts key;
  manifest_entry_count_cons_elim key left_head left_tail;
  manifest_entry_count_cons_elim key right_head right_tail;
  if key = left_head then begin
    manifest_head_not_in_tail left_head left_tail;
    manifest_head_not_in_tail right_head right_tail;
    mem_count left_tail key;
    mem_count right_tail key;
    assert (count key left_tail == 0);
    assert (count key right_tail == 0);
    ()
  end else ()

let rec sorted_manifest_entry_counts_unique
    (left right:list manifest_entry)
    (same_counts:(key:manifest_entry -> Lemma
      (ensures count key left == count key right)))
    : Lemma
      (requires
        sorted (bool_of_compare compare_manifest_entries) left /\
        sorted (bool_of_compare compare_manifest_entries) right /\
        noRepeats left /\ noRepeats right)
      (ensures left == right)
      (decreases left) =
  match left, right with
  | [], [] -> ()
  | [], _::_ -> same_counts (hd right); assert False
  | _::_, [] -> same_counts (hd left); assert False
  | left_head::left_tail, right_head::right_tail ->
      sorted_manifest_entry_heads_equal left_head right_head
        left_tail right_tail same_counts;
      manifest_head_not_in_tail left_head left_tail;
      manifest_head_not_in_tail right_head right_tail;
      manifest_no_repeats_tail left_head left_tail;
      manifest_no_repeats_tail right_head right_tail;
      let tail_counts (key:manifest_entry)
          : Lemma (ensures count key left_tail == count key right_tail) =
        manifest_entry_count_tails_equal left_head right_head
          left_tail right_tail same_counts () () () key
      in
      sorted_manifest_entry_counts_unique left_tail right_tail tail_counts;
      ()

let sort_manifest_entries_permutation_unique
    (left right:list manifest_entry)
    (left_unique:unit{noRepeats left})
    (right_unique:unit{noRepeats right})
    (same_counts:(key:manifest_entry -> Lemma
      (ensures count key left == count key right)))
    : Lemma (ensures sort_manifest_entries left ==
                      sort_manifest_entries right) =
  sort_manifest_entries_sorted left;
  sort_manifest_entries_sorted right;
  sort_manifest_entries_preserves_no_repeats left left_unique;
  sort_manifest_entries_preserves_no_repeats right right_unique;
  let sorted_counts (key:manifest_entry)
      : Lemma (ensures count key (sort_manifest_entries left) ==
                       count key (sort_manifest_entries right)) =
    same_counts key;
    sort_manifest_entries_counts left key;
    sort_manifest_entries_counts right key;
    ()
  in
  sorted_manifest_entry_counts_unique
    (sort_manifest_entries left) (sort_manifest_entries right) sorted_counts

let sort_manifest_entries_sorted_unique_fixed_point
    (entries:list manifest_entry)
    (is_sorted:unit{sorted (bool_of_compare compare_manifest_entries) entries})
    (is_unique:unit{noRepeats entries})
    : Lemma (ensures sort_manifest_entries entries == entries) =
  sort_manifest_entries_sorted entries;
  sort_manifest_entries_preserves_no_repeats entries is_unique;
  let counts_equal (key:manifest_entry)
      : Lemma (ensures count key entries ==
                       count key (sort_manifest_entries entries)) =
    sort_manifest_entries_counts entries key;
    ()
  in
  sorted_manifest_entry_counts_unique entries (sort_manifest_entries entries) counts_equal

let current_manifest_format_version : nat = 1

let manifest_data_fields_valid (m:registry_manifest) : bool =
  entries_fields_well_formed m.manifest_entries

let manifest_data_ids_unique (m:registry_manifest) : bool =
  entries_ids_unique m.manifest_entries

let manifest_data_links_closed (m:registry_manifest) : bool =
  manifest_entries_links_closed m.manifest_entries &&
  manifest_entries_references_typed m.manifest_entries &&
  manifest_entries_links_coherent m.manifest_entries

let manifest_data_canonical_order (m:registry_manifest) : bool =
  sorted (bool_of_compare compare_manifest_entries) m.manifest_entries

let manifest_data_canonical (m:registry_manifest) : bool =
  m.manifest_format_version = current_manifest_format_version &&
  manifest_data_fields_valid m && manifest_data_ids_unique m &&
  manifest_data_links_closed m && manifest_data_canonical_order m

// Reject duplicate keys on the unsorted source list first. Sorting is a
// canonicalization step only; it never chooses a winner or drops a row.
let canonicalize_manifest_entries (entries:list manifest_entry)
    : option (list manifest_entry) =
  if not (entries_ids_unique entries) then None
  else if not (entries_fields_well_formed entries) then None
  else if not (manifest_entries_links_closed entries) then None
  else if not (manifest_entries_references_typed entries) then None
  else if not (manifest_entries_links_coherent entries) then None
  else
    let ordered = sort_manifest_entries entries in
    if entries_ids_unique ordered &&
       entries_fields_well_formed ordered &&
       manifest_entries_links_closed ordered &&
       manifest_entries_references_typed ordered &&
       manifest_entries_links_coherent ordered &&
       sorted (bool_of_compare compare_manifest_entries) ordered
    then Some ordered
    else None

let canonicalize_manifest_entries_result
    (entries ordered:list manifest_entry)
    : Lemma
      (requires canonicalize_manifest_entries entries == Some ordered)
      (ensures
        entries_ids_unique entries /\
        ordered == sort_manifest_entries entries /\
        entries_ids_unique ordered /\
        entries_fields_well_formed ordered /\
        manifest_entries_links_closed ordered /\
        manifest_entries_references_typed ordered /\
        manifest_entries_links_coherent ordered /\
        sorted (bool_of_compare compare_manifest_entries) ordered) = ()

let canonicalize_manifest_entries_permutation
    (left right left_canonical right_canonical:list manifest_entry)
    (same_source_counts:(key:manifest_entry -> Lemma
      (ensures count key left == count key right)))
    : Lemma
      (requires
        canonicalize_manifest_entries left == Some left_canonical /\
        canonicalize_manifest_entries right == Some right_canonical)
      (ensures left_canonical == right_canonical) =
  canonicalize_manifest_entries_result left left_canonical;
  canonicalize_manifest_entries_result right right_canonical;
  entries_ids_unique_implies_no_repeats left;
  entries_ids_unique_implies_no_repeats right;
  sort_manifest_entries_permutation_unique left right () () same_source_counts;
  ()

let canonicalize_manifest_entries_idempotent
    (entries canonical:list manifest_entry)
    : Lemma
      (requires canonicalize_manifest_entries entries == Some canonical)
      (ensures canonicalize_manifest_entries canonical == Some canonical) =
  canonicalize_manifest_entries_result entries canonical;
  entries_ids_unique_implies_no_repeats canonical;
  sort_manifest_entries_sorted_unique_fixed_point canonical () ();
  ()

let canonicalize_registry_manifest (m:registry_manifest)
    : option registry_manifest =
  if m.manifest_format_version <> current_manifest_format_version then None
  else match canonicalize_manifest_entries m.manifest_entries with
       | None -> None
       | Some entries ->
           let canonical = {
             manifest_format_version=current_manifest_format_version;
             manifest_entries=entries
           } in
           if manifest_data_canonical canonical then Some canonical else None

let canonicalize_manifest_duplicate_rejects (entries:list manifest_entry)
    : Lemma (requires not (entries_ids_unique entries))
            (ensures canonicalize_manifest_entries entries == None) = ()

let canonicalize_manifest_sound (m canonical:registry_manifest)
    : Lemma (requires canonicalize_registry_manifest m == Some canonical)
            (ensures manifest_data_canonical canonical) = ()

let dec_manifest_entry_frame (input:bytes)
    : option (manifest_entry & bytes) =
  match dec_len_seq input with
  | None -> None
  | Some (entry_bytes, tail) ->
      match dec_manifest_entry entry_bytes with
      | None -> None
      | Some (entry, rest) ->
          if rest = [] then Some (entry, tail) else None

let rec enc_manifest_entries (entries:list manifest_entry) : bytes =
  match entries with
  | [] -> []
  | entry::tail ->
      enc_seq (enc_manifest_entry entry) @ enc_manifest_entries tail

let rec dec_manifest_entries (count:nat) (input:bytes)
    : Tot (option (list manifest_entry & bytes)) (decreases count) =
  match count with
  | 0 -> Some ([], input)
  | _ -> match dec_manifest_entry_frame input with
         | None -> None
         | Some (entry, tail) ->
             match dec_manifest_entries (count - 1) tail with
             | None -> None
             | Some (entries, rest) -> Some (entry::entries, rest)

let rec manifest_entries_decode_encoding_suffix
    (entries:list manifest_entry) (suffix:bytes)
    : Lemma (ensures (dec_manifest_entries (length entries)
        (enc_manifest_entries entries @ suffix) == Some (entries, suffix)))
    (decreases entries) =
  match entries with
  | [] -> ()
  | entry::tail ->
      append_assoc_local (enc_seq (enc_manifest_entry entry))
        (enc_manifest_entries tail) suffix;
      sequence_decode_encoding_suffix (enc_manifest_entry entry)
        (enc_manifest_entries tail @ suffix);
      manifest_entry_decode_encoding_suffix entry [];
      manifest_entries_decode_encoding_suffix tail suffix;
      assert (length (entry::tail) - 1 == length tail);
      ()

let manifest_magic : nat = 0x4d414e49

let encode_manifest_data (m:registry_manifest) : bytes =
  enc_nat manifest_magic @ enc_nat m.manifest_format_version @
  enc_nat (length m.manifest_entries) @
  enc_manifest_entries m.manifest_entries

let decode_manifest_data (input:bytes) : option registry_manifest =
  match dec_nat input with
  | None -> None
  | Some (magic, tail) ->
      if magic <> manifest_magic then None
      else match dec_nat tail with
           | None -> None
           | Some (format_version, tail2) ->
               match dec_nat tail2 with
               | None -> None
               | Some (count, tail3) ->
                   match dec_manifest_entries count tail3 with
                   | Some (entries, []) ->
                       let m = {manifest_format_version=format_version;
                                manifest_entries=entries} in
                       if manifest_data_canonical m &&
                          input = encode_manifest_data m
                       then Some m else None
                   | _ -> None

let manifest_data_decode_canonical (input:bytes) (m:registry_manifest)
    : Lemma (requires decode_manifest_data input == Some m)
            (ensures input == encode_manifest_data m) = ()

let manifest_data_decode_encoding (m:registry_manifest)
    : Lemma (requires manifest_data_canonical m)
            (ensures decode_manifest_data (encode_manifest_data m) == Some m) =
  append_assoc_local (enc_nat manifest_magic)
    (enc_nat m.manifest_format_version @
     (enc_nat (length m.manifest_entries) @
      enc_manifest_entries m.manifest_entries)) [];
  append_assoc_local (enc_nat m.manifest_format_version)
    (enc_nat (length m.manifest_entries) @
     enc_manifest_entries m.manifest_entries) [];
  append_assoc_local (enc_nat (length m.manifest_entries))
    (enc_manifest_entries m.manifest_entries) [];
  assert (dec_nat (enc_nat manifest_magic @
    (enc_nat m.manifest_format_version @
     (enc_nat (length m.manifest_entries) @
      enc_manifest_entries m.manifest_entries))) ==
    Some (manifest_magic, enc_nat m.manifest_format_version @
      (enc_nat (length m.manifest_entries) @
       enc_manifest_entries m.manifest_entries)));
  assert (dec_nat (enc_nat m.manifest_format_version @
    (enc_nat (length m.manifest_entries) @
     enc_manifest_entries m.manifest_entries)) ==
    Some (m.manifest_format_version, enc_nat (length m.manifest_entries) @
      enc_manifest_entries m.manifest_entries));
  assert (dec_nat (enc_nat (length m.manifest_entries) @
    enc_manifest_entries m.manifest_entries) ==
    Some (length m.manifest_entries, enc_manifest_entries m.manifest_entries));
  manifest_entries_decode_encoding_suffix m.manifest_entries [];
  assert (manifest_data_canonical m);
  ()

let manifest_data_encoding_injective (left right:registry_manifest)
    : Lemma (requires manifest_data_canonical left /\
                      manifest_data_canonical right /\
                      encode_manifest_data left == encode_manifest_data right)
            (ensures left == right) =
  manifest_data_decode_encoding left;
  manifest_data_decode_encoding right;
  ()

let registry_manifest_identity
    (m:registry_manifest{manifest_data_canonical m}) : registry_identity =
  registry_identity_of_bytes (encode_manifest_data m)

let registry_manifest_identity_injective (left right:registry_manifest)
    : Lemma (requires manifest_data_canonical left /\
                      manifest_data_canonical right /\
                      registry_manifest_identity left ==
                      registry_manifest_identity right)
            (ensures left == right) =
  assert (encode_manifest_data left == encode_manifest_data right);
  manifest_data_encoding_injective left right

// The first-order projection boundary is list equality over complete rows,
// not a one-way membership test. A04 instantiates `projected` from executable
// bundle tables and proves this exact relation without comparing closures.
let first_order_manifest_projection_exact
    (projected:list manifest_entry) (m:registry_manifest) : prop =
  projected == m.manifest_entries

let first_order_manifest_projection_both_ways
    (projected:list manifest_entry) (m:registry_manifest)
    : Lemma
      (requires first_order_manifest_projection_exact projected m)
      (ensures (forall row.
        (mem row projected <==> mem row m.manifest_entries))) = ()
