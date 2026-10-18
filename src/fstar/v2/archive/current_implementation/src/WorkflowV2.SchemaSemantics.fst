module WorkflowV2.SchemaSemantics

open FStar.List.Tot
open FStar.List.Tot.Properties
open WorkflowV2.Kernel
open WorkflowV2.ManifestCore
open WorkflowV2.SchemaCodec

// Canonical codecs are also equality-reflecting at a fixed index. These
// lemmas are the bridge used by SchemaEqual: once both expressions are shown
// to have the same exact carrier/index, equality of their canonical bytes
// implies equality of the represented F* values.
let schema_plain_codec_encode_injective (#a:Type0) (c:codec a)
    (left right:a)
    : Lemma (requires c.encode left == c.encode right)
            (ensures left == right) =
  c.roundtrip left;
  c.roundtrip right;
  assert (c.decode (c.encode left) == Some left);
  assert (c.decode (c.encode right) == Some right);
  ()

let schema_indexed_codec_encode_injective (#i:Type0) (#o:i -> Type0)
    (c:indexed_codec i o) (index:i) (left right:o index)
    : Lemma (requires c.encode_indexed index left ==
                       c.encode_indexed index right)
            (ensures left == right) =
  c.roundtrip_indexed index left;
  c.roundtrip_indexed index right;
  assert (c.decode_indexed index (c.encode_indexed index left) == Some left);
  assert (c.decode_indexed index (c.encode_indexed index right) == Some right);
  assert (c.encode_indexed index left == c.encode_indexed index right);
  ()

// Exact manifest-selected schema rows {{{1
// Schema packages are selected through the canonical manifest row. This
// prevents a second editable identity-to-expression table; A04/P0 later binds
// the proof-bearing F* package to this exact row.
let selected_schema_family_row
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) : option manifest_entry =
  manifest_identity_present (ManifestSchemaFamilyIdentity identity)
    manifest.manifest_entries

let selected_schema_family_row_member
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) (row:manifest_entry)
    : Lemma
      (requires selected_schema_family_row manifest identity == Some row)
      (ensures mem row manifest.manifest_entries /\
               row.manifest_entry_identity ==
                 ManifestSchemaFamilyIdentity identity) =
  manifest_identity_present_member
    (ManifestSchemaFamilyIdentity identity) manifest.manifest_entries row

let selected_schema_family_row_unique
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) (selected candidate:manifest_entry)
    : Lemma
      (requires entries_ids_unique manifest.manifest_entries /\
        selected_schema_family_row manifest identity == Some selected /\
        mem candidate manifest.manifest_entries /\
        candidate.manifest_entry_identity ==
          ManifestSchemaFamilyIdentity identity)
      (ensures candidate == selected) =
  manifest_identity_present_unique
    (ManifestSchemaFamilyIdentity identity) manifest.manifest_entries
    selected candidate

// Family and rule rows share a field layout. The owner tag remains part of
// the expected identity, preventing a rule row from standing in for a family
// row with the same schema_identity payload.
let schema_entry_expression (expected:manifest_identity)
    (row:manifest_entry) : option schema_type_expr =
  match row.manifest_entry_fields with
  | [ManifestSchemaSyntaxValue wire; law] ->
      if row.manifest_entry_identity = expected &&
         contract_kind_is DenotationLawContract law
      then decode_schema_type wire else None
  | _ -> None

let schema_entry_law (expected:manifest_identity) (row:manifest_entry)
    : option manifest_contract_ref =
  match row.manifest_entry_fields with
  | [ManifestSchemaSyntaxValue _; ManifestContractValue law] ->
      if row.manifest_entry_identity = expected &&
         law.contract_ref_kind = DenotationLawContract
      then Some law else None
  | _ -> None

let schema_family_row_expression (identity:schema_identity)
    (row:manifest_entry) : option schema_type_expr =
  schema_entry_expression (ManifestSchemaFamilyIdentity identity) row

let schema_family_row_law (identity:schema_identity)
    (row:manifest_entry) : option manifest_contract_ref =
  schema_entry_law (ManifestSchemaFamilyIdentity identity) row

let selected_schema_family_expression
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) : option schema_type_expr =
  match selected_schema_family_row manifest identity with
  | None -> None
  | Some row -> schema_family_row_expression identity row

let selected_schema_family_law
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) : option manifest_contract_ref =
  match selected_schema_family_row manifest identity with
  | None -> None
  | Some row -> schema_family_row_law identity row

// Syntax and law token must project from the same canonical selected row.
let selected_family_components_from_same_row
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) (row:manifest_entry)
    (expression:schema_type_expr) (law:manifest_contract_ref)
    : Lemma
      (requires
        selected_schema_family_row manifest identity == Some row /\
        schema_family_row_expression identity row == Some expression /\
        schema_family_row_law identity row == Some law)
      (ensures
        exists (wire:bytes).
          exists (row_law:manifest_contract_ref).
            row.manifest_entry_identity == ManifestSchemaFamilyIdentity identity /\
            row.manifest_entry_fields ==
              [ManifestSchemaSyntaxValue wire; ManifestContractValue row_law] /\
            decode_schema_type wire == Some expression /\
            row_law == law /\
            row_law.contract_ref_kind == DenotationLawContract) =
  match row.manifest_entry_fields with
  | [ManifestSchemaSyntaxValue wire; ManifestContractValue row_law] ->
      assert (row.manifest_entry_identity == ManifestSchemaFamilyIdentity identity);
      assert (row_law.contract_ref_kind == DenotationLawContract);
      assert (decode_schema_type wire == Some expression);
      ()
  | _ -> ()

let selected_schema_rule_row
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) : option manifest_entry =
  manifest_identity_present (ManifestSchemaRuleIdentity identity)
    manifest.manifest_entries

let selected_schema_rule_row_member
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) (row:manifest_entry)
    : Lemma
      (requires selected_schema_rule_row manifest identity == Some row)
      (ensures mem row manifest.manifest_entries /\
               row.manifest_entry_identity ==
                 ManifestSchemaRuleIdentity identity) =
  manifest_identity_present_member
    (ManifestSchemaRuleIdentity identity) manifest.manifest_entries row

let selected_schema_rule_row_unique
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) (selected candidate:manifest_entry)
    : Lemma
      (requires entries_ids_unique manifest.manifest_entries /\
        selected_schema_rule_row manifest identity == Some selected /\
        mem candidate manifest.manifest_entries /\
        candidate.manifest_entry_identity ==
          ManifestSchemaRuleIdentity identity)
      (ensures candidate == selected) =
  manifest_identity_present_unique
    (ManifestSchemaRuleIdentity identity) manifest.manifest_entries
    selected candidate

let schema_rule_row_expression (identity:schema_identity)
    (row:manifest_entry) : option schema_type_expr =
  schema_entry_expression (ManifestSchemaRuleIdentity identity) row

let schema_rule_row_law (identity:schema_identity)
    (row:manifest_entry) : option manifest_contract_ref =
  schema_entry_law (ManifestSchemaRuleIdentity identity) row

let selected_schema_rule_expression
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) : option schema_type_expr =
  match selected_schema_rule_row manifest identity with
  | None -> None
  | Some row -> schema_rule_row_expression identity row

let selected_schema_rule_law
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) : option manifest_contract_ref =
  match selected_schema_rule_row manifest identity with
  | None -> None
  | Some row -> schema_rule_row_law identity row

// The selected rows carry canonical syntax and exact law tokens. A04/P0
// binds those tokens to the actual proof-bearing package fields.

// Carrier-telescope utilities {{{1
// These helpers establish safe lookup in a carrier telescope. They do not yet
// establish that a carrier is the denotation of a schema AST binder; that
// stronger relation is the next semantic-judgment proof.
noeq type hlist : list Type0 -> Type =
  | HNil : hlist []
  | HCons : #head:Type0 -> #tail:list Type0 ->
      head -> hlist tail -> hlist (head :: tail)

noeq type context_member : list Type0 -> nat -> Type0 -> Type =
  | ContextHere : #head:Type0 -> #tail:list Type0 ->
      context_member (head :: tail) 0 head
  | ContextThere : #head:Type0 -> #tail:list Type0 ->
      #carrier:Type0 -> index:nat ->
      context_member tail index carrier ->
      context_member (head :: tail) (index + 1) carrier

let rec context_lookup (#carriers:list Type0) (#index:nat)
    (#carrier:Type0) (values:hlist carriers)
    (member:context_member carriers index carrier) : Tot carrier =
  match member with
  | ContextHere ->
      (match values with | HCons value _ -> value)
  | ContextThere _ prior ->
      (match values with | HCons _ tail -> context_lookup tail prior)

// A carrier-only dependent telescope is useful plumbing, but is not a
// SchemaBound typing judgment until its declarations are linked to AST types.
noeq type dependent_carrier_context = {
  local_environment:Type0;
  local_carriers:local_environment -> list Type0;
  local_values:(rho:local_environment) ->
    hlist (local_carriers rho)
}

let extend_dependent_carrier_context (context:dependent_carrier_context)
    (binder:context.local_environment -> Type0)
    : dependent_carrier_context =
  let extended_environment =
    dtuple2 context.local_environment binder in
  {
    local_environment=extended_environment;
    local_carriers=(fun (pair:dtuple2 context.local_environment binder) ->
      match pair with
      | Mkdtuple2 rho _ -> binder rho :: context.local_carriers rho);
    local_values=(fun (pair:dtuple2 context.local_environment binder) ->
      match pair with
      | Mkdtuple2 rho candidate -> HCons candidate (context.local_values rho))
  }

let dependent_carrier_lookup (context:dependent_carrier_context)
    (rho:context.local_environment) (index:nat) (#carrier:Type0)
    (member:context_member (context.local_carriers rho) index carrier)
    : carrier = context_lookup (context.local_values rho) member

let nearest_dependent_candidate (#context:dependent_carrier_context)
    (binder:context.local_environment -> Type0)
    (rho:context.local_environment) (candidate:binder rho)
    : binder rho =
  dependent_carrier_lookup (extend_dependent_carrier_context context binder)
    (Mkdtuple2 rho candidate) 0 ContextHere

let outer_dependent_binding (#context:dependent_carrier_context)
    (binder:context.local_environment -> Type0)
    (rho:context.local_environment) (candidate:binder rho)
    (index:nat) (#carrier:Type0)
    (member:context_member (context.local_carriers rho) index carrier)
    : carrier =
  dependent_carrier_lookup (extend_dependent_carrier_context context binder)
    (Mkdtuple2 rho candidate) (index + 1) (ContextThere index member)

let carrier_bound_lookup (#carriers:list Type0) (index:nat)
    (#carrier:Type0) (values:hlist carriers)
    (member:context_member carriers index carrier) : carrier =
  context_lookup values member

// Nearest-first lookup examples: a Sigma/Refine candidate is slot zero;
// pre-existing binders shift outward by one.
let sigma_candidate_is_carrier_slot_zero (candidate:nat) (outer:bool)
    : nat =
  carrier_bound_lookup 0 (HCons candidate (HCons outer HNil)) ContextHere

let refine_outer_is_carrier_slot_one (candidate:nat) (outer:bool)
    : bool =
  carrier_bound_lookup 1 (HCons candidate (HCons outer HNil))
    (ContextThere 0 ContextHere)

// Root-indexed constants and full-family prefix kernel {{{1
// Constants can themselves be indexed by the exact root value. These generic
// structures are not yet GraphDesc/Work semantics: graph-specific constructors
// must derive them from the pinned declarations before they can witness
// LegalEnv.
noeq type base_environment (root:Type0) (constants:root -> list Type0) = {
  base_root:root;
  base_constants:hlist (constants base_root)
}

let exact_root_value (#root:Type0) (#constants:root -> list Type0)
    (base:base_environment root constants) : root = base.base_root

let exact_constant_value (#root:Type0) (#constants:root -> list Type0)
    (#carrier:Type0) (#index:nat) (base:base_environment root constants)
    (member:context_member (constants base.base_root) index carrier) : carrier =
  context_lookup base.base_constants member

noeq type full_family_snoc_environment (prior:Type0) (output:prior -> Type0) = {
  prior_environment:prior;
  completed_output:output prior_environment
}

noeq type full_family_step (base:Type0) (environment:base -> Type0) = {
  resolved_work_identity:work_identity;
  resolved_input:Type0;
  resolved_output:resolved_input -> Type0;
  resolved_input_wire:(b:base) -> environment b -> resolved_input
}

noeq type full_family_prefix (base:Type0) : (base -> Type0) -> Type =
  | FullFamilyPrefixEmpty : full_family_prefix base (fun (_:base) -> unit)
  | FullFamilyPrefixSnoc : #environment:(base -> Type0) ->
      prior:full_family_prefix base environment ->
      step:full_family_step base environment ->
      full_family_prefix base
        (fun b -> full_family_snoc_environment (environment b)
          (fun rho -> step.resolved_output
            (step.resolved_input_wire b rho)))

let append_full_family_environment (#base:Type0)
    (#environment:(base -> Type0))
    (prior:full_family_prefix base environment)
    (step:full_family_step base environment)
    (base_value:base) (rho:environment base_value)
    (result:step.resolved_output
      (step.resolved_input_wire base_value rho))
    : full_family_snoc_environment (environment base_value)
        (fun q -> step.resolved_output
          (step.resolved_input_wire base_value q)) =
  { prior_environment=rho; completed_output=result }

let appended_value_has_full_family_type (#base:Type0)
    (#environment:(base -> Type0))
    (prior:full_family_prefix base environment)
    (step:full_family_step base environment)
    (base_value:base) (rho:environment base_value)
    (result:step.resolved_output
      (step.resolved_input_wire base_value rho))
    : step.resolved_output (step.resolved_input_wire base_value rho) =
  (append_full_family_environment prior step base_value rho result).
    completed_output

let append_preserves_prior_environment (#base:Type0)
    (#environment:(base -> Type0))
    (prior:full_family_prefix base environment)
    (step:full_family_step base environment)
    (base_value:base) (rho:environment base_value)
    (result:step.resolved_output
      (step.resolved_input_wire base_value rho))
    : Lemma ((append_full_family_environment prior step base_value rho result).
        prior_environment == rho) = ()

// Refinement membership and generated facts {{{1
// Refine is interpreted as an ordinary F* refinement at its candidate value.
// Consequently every legal appended output already carries its predicate;
// extracting this fact does not filter the LegalEnv quantifier.
let schema_refinement (#carrier:Type0) (predicate:carrier -> prop)
    : Type0 = x:carrier{predicate x}

let refinement_member_implies_predicate (#carrier:Type0)
    (predicate:carrier -> prop) (value:schema_refinement predicate)
    : Lemma (predicate value) = ()

let singleton_three_has_exact_index : n:nat{n == 3} = 3

let singleton_three_predicate () : Lemma
    (singleton_three_has_exact_index == 3) = ()

let empty_full_family_prefix (#base:Type0) :
    full_family_prefix base (fun _ -> unit) = FullFamilyPrefixEmpty
