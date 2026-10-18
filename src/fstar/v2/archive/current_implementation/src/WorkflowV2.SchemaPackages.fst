module WorkflowV2.SchemaPackages

open FStar.List.Tot
open WorkflowV2.Kernel
open WorkflowV2.ManifestCore
open WorkflowV2.Identity
open WorkflowV2.SchemaScope
open WorkflowV2.SchemaSemantics

// Schema argument carriers and dependent products {{{1
// This universe-1 telescope represents F* carriers. Its matching AST
// telescope is retained beside it and connected by A05c/A05d judgments.
noeq type schema_argument_telescope : nat -> Type =
  | SchemaArgumentsNil : schema_argument_telescope 0
  | SchemaArgumentsCons : #head:Type0 -> #arity:nat
      -> (head -> schema_argument_telescope arity)
      -> schema_argument_telescope (arity + 1)

let rec schema_arguments_denote (#arity:nat)
    (arguments:schema_argument_telescope arity) : Type0 =
  match arguments with
  | SchemaArgumentsNil -> unit
  | SchemaArgumentsCons #head #tail_arity tail ->
      dtuple2 head (fun value -> schema_arguments_denote (tail value))

// A schema declaration telescope is nearest-first and dependent: the first
// type is in the surrounding scope, and each later type is under one more
// value binder. The declaration remains first-order syntax; it contains no
// carrier oracle or executable callback.
let rec schema_telescope_scoped (depth:nat)
    (arguments:list schema_type_expr) : Tot bool (decreases arguments) =
  match arguments with
  | [] -> true
  | argument::tail ->
      schema_type_scoped depth argument &&
      schema_telescope_scoped (depth + 1) tail

let schema_declaration_scoped (arguments:list schema_type_expr)
    (result:schema_type_expr) : Tot bool =
  schema_telescope_scoped 0 arguments &&
  schema_type_scoped (length arguments) result

// First-order equation syntax {{{1
type schema_equation = {
  equation_left:schema_value_expr;
  equation_right:schema_value_expr
}

let schema_equation_scoped (depth:nat) (equation:schema_equation) : Tot bool =
  schema_value_scoped depth equation.equation_left &&
  schema_value_scoped depth equation.equation_right

let rec schema_equations_scoped (depth:nat)
    (equations:list schema_equation) : Tot bool (decreases equations) =
  match equations with
  | [] -> true
  | equation::tail ->
      schema_equation_scoped depth equation &&
      schema_equations_scoped depth tail

let option_is_some (#a:Type) (candidate:option a) : Tot bool =
  match candidate with | None -> false | Some _ -> true

let option_is_none (#a:Type) (candidate:option a) : Tot bool =
  match candidate with | None -> true | Some _ -> false

// Exact manifest owner-row projections {{{1
// These owner records are projections of one exact canonical manifest row.
// They intentionally select by the tagged owner identity, never by the law
// token. The token is checked as a field of the selected row.
noeq type selected_family_owner
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) = {
  family_owner_row:manifest_entry;
  family_owner_selected:
    selected_schema_family_row manifest identity == Some family_owner_row;
  family_owner_expression:schema_type_expr;
  family_owner_expression_exact:
    schema_family_row_expression identity family_owner_row ==
      Some family_owner_expression;
  family_owner_law:manifest_contract_ref;
  family_owner_law_exact:
    schema_family_row_law identity family_owner_row == Some family_owner_law
}

noeq type selected_rule_owner
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (identity:schema_identity) = {
  rule_owner_row:manifest_entry;
  rule_owner_selected:
    selected_schema_rule_row manifest identity == Some rule_owner_row;
  rule_owner_expression:schema_type_expr;
  rule_owner_expression_exact:
    schema_rule_row_expression identity rule_owner_row ==
      Some rule_owner_expression;
  rule_owner_law:manifest_contract_ref;
  rule_owner_law_exact:
    schema_rule_row_law identity rule_owner_row == Some rule_owner_law
}

// Typed family package {{{1
// A family declaration's row expression is its result type under the exact
// dependent index telescope. The telescope's type index fixes its arity to
// the AST declaration's number of arguments. A05c uses an empty telescope for
// SchemaAtom; SchemaFamily may also have zero indices. The codec object is
// the sole codec source here; its membership witness selects this exact
// object from the shared registry. P0 binds that registry to manifest codec
// rows and restart-stable package lookup.
noeq type schema_family_package
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity) = {
  family_owner:selected_family_owner manifest identity;
  family_arguments:list schema_type_expr;
  family_result:schema_type_expr;
  family_argument_carriers:schema_argument_telescope (length family_arguments);
  family_denotation:schema_arguments_denote family_argument_carriers -> Type0;
  family_codec:indexed_codec
    (schema_arguments_denote family_argument_carriers) family_denotation;
  family_codec_member:packed_codec_membership
    (IndexedCodec family_codec) codec_registry.global_codec_entries;
  family_signature_scoped:
    schema_declaration_scoped family_arguments family_result == true;
  family_result_is_owner_expression:
    family_result == family_owner.family_owner_expression
}

// Typed rule package sum {{{1
// Rule syntax is a sum so that the AST constructor and index-call forms can
// only be interpreted by the matching declaration. Constructor results are
// statically an application of their declared parent family. Index-call
// results and their finite equations are first-order scoped syntax. A05c/A06
// supply typed judgments and prove equation soundness/completeness.
noeq type schema_constructor_package
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity) = {
  constructor_owner:selected_rule_owner manifest identity;
  constructor_arguments:list schema_type_expr;
  constructor_parent:schema_identity;
  constructor_result_indices:list schema_value_expr;
  constructor_result:schema_type_expr;
  constructor_argument_carriers:schema_argument_telescope
    (length constructor_arguments);
  constructor_parent_indices:(parent:schema_family_package manifest
      codec_registry
      constructor_parent) ->
    (args:schema_arguments_denote constructor_argument_carriers) ->
      Tot (schema_arguments_denote parent.family_argument_carriers);
  constructor_build:(parent:schema_family_package manifest
      codec_registry
      constructor_parent) ->
    (args:schema_arguments_denote constructor_argument_carriers) ->
      Tot (parent.family_denotation
        (constructor_parent_indices parent args));
  constructor_signature_scoped:
    schema_declaration_scoped constructor_arguments constructor_result == true;
  constructor_indices_scoped:
    schema_values_scoped (length constructor_arguments)
      constructor_result_indices == true;
  constructor_result_is_family:
    constructor_result ==
      SchemaFamily constructor_parent constructor_result_indices;
  constructor_result_is_owner_expression:
    constructor_result == constructor_owner.rule_owner_expression
}

noeq type schema_index_call_package
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity) = {
  index_call_owner:selected_rule_owner manifest identity;
  index_call_arguments:list schema_type_expr;
  index_call_result:schema_type_expr;
  index_call_equations:list schema_equation;
  index_call_argument_carriers:schema_argument_telescope
    (length index_call_arguments);
  index_call_denotation:(args:schema_arguments_denote
      index_call_argument_carriers) -> Type0;
  index_call_apply:(args:schema_arguments_denote
      index_call_argument_carriers) -> Tot (index_call_denotation args);
  index_call_codec:indexed_codec
    (schema_arguments_denote index_call_argument_carriers)
    index_call_denotation;
  index_call_codec_member:packed_codec_membership
    (IndexedCodec index_call_codec) codec_registry.global_codec_entries;
  index_call_signature_scoped:
    schema_declaration_scoped index_call_arguments index_call_result == true;
  index_call_equations_scoped:
    schema_equations_scoped (length index_call_arguments)
      index_call_equations == true;
  index_call_result_is_owner_expression:
    index_call_result == index_call_owner.rule_owner_expression
}

noeq type schema_rule_package
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity) =
  | SchemaConstructorRule :
      schema_constructor_package manifest codec_registry identity ->
      schema_rule_package manifest codec_registry identity
  | SchemaIndexCallRule :
      schema_index_call_package manifest codec_registry identity ->
      schema_rule_package manifest codec_registry identity

// The one manifest-indexed package map {{{1
// This is the one schema package map consumed by later denotation and
// resolution proofs. Its lookups are total functions returning at most one
// package per exact tagged owner identity. Completeness laws forbid silently
// omitting a declared row. A04/P0 later proves the pinned Bundle stores and
// reloads this exact map; this interface alone makes no host-loader claim.
noeq type schema_packages
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry) = {
  // This registry is the exact codec source for every schema package. The
  // package codecs below carry membership in this value, so A04/P0 can prove
  // that schema interpretation and ordinary Work decoding share one codec.
  family_at:(identity:schema_identity) -> Tot
    (option (schema_family_package manifest codec_registry identity));
  rule_at:(identity:schema_identity) -> Tot
    (option (schema_rule_package manifest codec_registry identity));
  every_family_row_has_package:identity:schema_identity -> Lemma
    (requires selected_schema_family_row manifest identity <> None)
    (ensures option_is_some (family_at identity));
  every_rule_row_has_package:identity:schema_identity -> Lemma
    (requires selected_schema_rule_row manifest identity <> None)
    (ensures option_is_some (rule_at identity));
  no_family_package_without_row:identity:schema_identity -> Lemma
    (requires selected_schema_family_row manifest identity == None)
    (ensures option_is_none (family_at identity));
  no_rule_package_without_row:identity:schema_identity -> Lemma
    (requires selected_schema_rule_row manifest identity == None)
    (ensures option_is_none (rule_at identity))
}

// Constructor interpretation always obtains its parent through this exact
// package map. The helper returns that selected package beside its result,
// avoiding a second caller-supplied parent package as a semantic source.
let apply_constructor_from_selected_parent
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (#identity:schema_identity)
    (packages:schema_packages manifest codec_registry)
    (declaration:schema_constructor_package manifest codec_registry identity)
    (arguments:schema_arguments_denote
      declaration.constructor_argument_carriers)
    : Tot (option
      (parent:schema_family_package manifest codec_registry
          declaration.constructor_parent &
       parent.family_denotation
         (declaration.constructor_parent_indices parent arguments))) =
  match packages.family_at declaration.constructor_parent with
  | None -> None
  | Some parent ->
      Some (Mkdtuple2 parent
        (declaration.constructor_build parent arguments))

// Exact owner and variant lemmas {{{1
// Reuse selected-row uniqueness to expose the exact owner rows carried by
// packages without comparing noeq records or package functions.
let family_owner_row_is_selected
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity)
    (package:schema_family_package manifest codec_registry identity)
    : Lemma
      (ensures selected_schema_family_row manifest identity ==
        Some package.family_owner.family_owner_row) =
  package.family_owner.family_owner_selected

let schema_rule_owner_row
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity)
    (package:schema_rule_package manifest codec_registry identity)
    : manifest_entry =
  match package with
  | SchemaConstructorRule declaration ->
      declaration.constructor_owner.rule_owner_row
  | SchemaIndexCallRule declaration ->
      declaration.index_call_owner.rule_owner_row

let rule_owner_row_is_selected
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity)
    (package:schema_rule_package manifest codec_registry identity)
    : Lemma
      (ensures selected_schema_rule_row manifest identity ==
        Some (schema_rule_owner_row manifest codec_registry identity package)) =
  match package with
  | SchemaConstructorRule declaration ->
      declaration.constructor_owner.rule_owner_selected
  | SchemaIndexCallRule declaration ->
      declaration.index_call_owner.rule_owner_selected

// AST/package variant matching {{{2
// A Constructor AST cannot be interpreted through an IndexCall package, nor
// vice versa. Typed argument and result judgments are A05c/A05d obligations.
let rule_ast_matches_package
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity)
    (package:schema_rule_package manifest codec_registry identity)
    (expression:schema_value_expr) : Tot bool =
  match package, expression with
  | SchemaConstructorRule declaration,
      SchemaConstructorValue owner arguments ->
      owner = identity &&
      length arguments = length declaration.constructor_arguments
  | SchemaIndexCallRule declaration,
      SchemaIndexCallValue owner arguments ->
      owner = identity &&
      length arguments = length declaration.index_call_arguments
  | _, _ -> false

let schema_type_ast_matches_family_package
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity)
    (package:schema_family_package manifest codec_registry identity)
    (expression:schema_type_expr) : Tot bool =
  match expression with
  | SchemaAtom owner ->
      owner = identity && package.family_arguments = []
  | SchemaFamily owner arguments ->
      owner = identity &&
      length arguments = length package.family_arguments
  | _ -> false

let schema_atom_requires_nullary_package
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity)
    (package:schema_family_package manifest codec_registry identity)
    : Lemma
      (requires schema_type_ast_matches_family_package manifest codec_registry
        identity package (SchemaAtom identity) == true)
      (ensures package.family_arguments == []) = ()

let schema_family_package_arity_exact
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity)
    (package:schema_family_package manifest codec_registry identity)
    (arguments:list schema_value_expr)
    : Lemma
      (requires schema_type_ast_matches_family_package manifest codec_registry
        identity package (SchemaFamily identity arguments) == true)
      (ensures length arguments == length package.family_arguments) = ()

let constructor_ast_rejected_for_index_call
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity)
    (package:schema_index_call_package manifest codec_registry identity)
    (arguments:list schema_value_expr)
    : Lemma
      (ensures rule_ast_matches_package manifest codec_registry identity
        (SchemaIndexCallRule package)
        (SchemaConstructorValue identity arguments) == false) = ()

let index_call_ast_rejected_for_constructor
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (identity:schema_identity)
    (package:schema_constructor_package manifest codec_registry identity)
    (arguments:list schema_value_expr)
    : Lemma
      (ensures rule_ast_matches_package manifest codec_registry identity
        (SchemaConstructorRule package)
        (SchemaIndexCallValue identity arguments) == false) = ()
