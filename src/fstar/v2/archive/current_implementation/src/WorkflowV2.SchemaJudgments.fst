module WorkflowV2.SchemaJudgments

open FStar.List.Tot
open WorkflowV2.Kernel
open WorkflowV2.SchemaScope
open WorkflowV2.ManifestCore
open WorkflowV2.Identity
open WorkflowV2.SchemaPackages

// Formal signature arguments are nearest-first. A later signature type is
// evaluated after substituting the earlier actual syntax arguments.
let rec argument_prefix_substitution
    (prefix:list schema_value_expr) : schema_substitution =
  fun index ->
    match prefix with
    | [] -> SchemaBound index
    | head::tail ->
        if index = 0 then head
        else argument_prefix_substitution tail (index - 1)

// A derivation aligns a package's AST argument telescope with actual syntax
// arguments and its dependent F* carrier telescope. `jvalue` is a type-valued
// evidence relation parameter here, not yet the canonical A05c judgment: it
// currently has no context parameter, and this module's example is a
// placeholder. Such evidence is not automatically a logical proposition.
// A05c must replace this scaffold with the hidden context-indexed judgment.
noeq type schema_argument_derivation :
    (jvalue:(carrier:Type0 -> schema_type_expr -> schema_value_expr ->
      carrier -> Type)) ->
    list schema_value_expr -> list schema_type_expr ->
    list schema_value_expr -> (arity:nat) ->
    (carriers:schema_argument_telescope arity) ->
    schema_arguments_denote carriers -> Type =
  | SchemaArgumentDerivationNil :
      #jvalue:(carrier:Type0 -> schema_type_expr -> schema_value_expr ->
        carrier -> Type) ->
      #prefix:list schema_value_expr ->
      schema_argument_derivation jvalue prefix [] [] 0 SchemaArgumentsNil ()
  | SchemaArgumentDerivationCons :
      #jvalue:(carrier:Type0 -> schema_type_expr -> schema_value_expr ->
        carrier -> Type) ->
      #head:Type0 -> #tail_arity:nat ->
      tail_carriers:(head -> schema_argument_telescope tail_arity) ->
      head_value:head ->
      tail_values:schema_arguments_denote (tail_carriers head_value) ->
      prefix:list schema_value_expr ->
      head_expression:schema_value_expr ->
      tail_expressions:list schema_value_expr ->
      head_type:schema_type_expr ->
      tail_types:list schema_type_expr ->
      jvalue head (substitute_schema_type
        (argument_prefix_substitution prefix) head_type)
        head_expression head_value ->
      schema_argument_derivation jvalue
        (head_expression::prefix) tail_types tail_expressions
        tail_arity (tail_carriers head_value) tail_values ->
      schema_argument_derivation jvalue prefix (head_type::tail_types)
        (head_expression::tail_expressions) (tail_arity + 1)
        (SchemaArgumentsCons #head #tail_arity tail_carriers)
        (Mkdtuple2 head_value tail_values)

// Selected-package constructors are centralized here. The returned package
// is exactly the object produced by the registry lookup; the boolean
// predicates are checked before it can be consumed by semantic rules.
let select_family_for_type
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (packages:schema_packages manifest codec_registry)
    (identity:schema_identity) (expression:schema_type_expr)
    : Tot (option (schema_family_package manifest codec_registry identity)) =
  match packages.family_at identity with
  | None -> None
  | Some package ->
      if schema_type_ast_matches_family_package manifest codec_registry
           identity package expression
      then Some package
      else None

let select_rule_for_value
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (packages:schema_packages manifest codec_registry)
    (identity:schema_identity) (expression:schema_value_expr)
    : Tot (option (schema_rule_package manifest codec_registry identity)) =
  match packages.rule_at identity with
  | None -> None
  | Some package ->
      if rule_ast_matches_package manifest codec_registry identity package
           expression
      then Some package
      else None

let selected_atom_is_nullary
    (manifest:registry_manifest{manifest_data_canonical manifest})
    (codec_registry:global_codec_registry)
    (packages:schema_packages manifest codec_registry)
    (identity:schema_identity)
    (package:schema_family_package manifest codec_registry identity)
    (selected:select_family_for_type manifest codec_registry packages
      identity (SchemaAtom identity) == Some package)
    : Lemma (package.family_arguments == []) =
  assert (schema_type_ast_matches_family_package manifest codec_registry
    identity package (SchemaAtom identity) == true);
  schema_atom_requires_nullary_package manifest codec_registry identity
    package

// Conditional A05c family-type rule. The exact selected package and one
// dependent argument tuple determine the result carrier, and that same
// package carries the indexed codec. The argument derivation is internal
// judgment evidence, not a graph-author proof field. The jvalue relation is
// still a parameterized scaffold here; canonical context-indexed JValue
// replaces it before A05c acceptance. A05g will derive the argument evidence
// from the package alignment law plus semantic substitution.
noeq type schema_family_type_judgment :
    (manifest:registry_manifest{manifest_data_canonical manifest}) ->
    (codec_registry:global_codec_registry) ->
    (packages:schema_packages manifest codec_registry) ->
    (jvalue:(carrier:Type0 -> schema_type_expr -> schema_value_expr ->
      carrier -> Type)) ->
    (identity:schema_identity) ->
    (arguments:list schema_value_expr) ->
    (expression:schema_type_expr) ->
    (carrier:Type0) -> Type =
  | SchemaFamilyTypeJudgment :
      #manifest:registry_manifest{manifest_data_canonical manifest} ->
      #codec_registry:global_codec_registry ->
      #packages:schema_packages manifest codec_registry ->
      #jvalue:(carrier:Type0 -> schema_type_expr -> schema_value_expr ->
        carrier -> Type) ->
      #identity:schema_identity ->
      #arguments:list schema_value_expr ->
      (package:schema_family_package manifest codec_registry identity) ->
      select_family_for_type manifest codec_registry packages identity
        (SchemaFamily identity arguments) == Some package ->
      (indices:schema_arguments_denote package.family_argument_carriers) ->
      schema_argument_derivation jvalue [] package.family_arguments
        arguments (length package.family_arguments)
        package.family_argument_carriers indices ->
      schema_family_type_judgment manifest codec_registry packages jvalue
        identity arguments (SchemaFamily identity arguments)
        (package.family_denotation indices)

// This executable shape witness confirms that the first formal argument may
// affect the second argument's carrier. The proof itself is generic above;
// these declarations intentionally make no claim about the abstract jvalue
// relation until the canonical A05c judgment is supplied.
let example_dependent_argument_carriers : schema_argument_telescope 2 =
  SchemaArgumentsCons (fun (_:nat) ->
    SchemaArgumentsCons (fun (_:nat) -> SchemaArgumentsNil))

let example_dependent_argument_types : list schema_type_expr =
  [SchemaNat;
   SchemaRefine SchemaNat
     (SchemaEqual (SchemaBound 1) (SchemaNatValue 7))]

let example_dependent_argument_expressions : list schema_value_expr =
  [SchemaNatValue 7; SchemaNatValue 7]

let example_value_judgment :
    carrier:Type0 -> schema_type_expr -> schema_value_expr -> carrier -> Type =
  fun _ _ _ _ -> unit

let example_dependent_argument_alignment :
    schema_argument_derivation example_value_judgment []
      example_dependent_argument_types
      example_dependent_argument_expressions 2
      example_dependent_argument_carriers
      (Mkdtuple2 7 (Mkdtuple2 7 ())) =
  SchemaArgumentDerivationCons
    (fun (_:nat) -> SchemaArgumentsCons
      (fun (_:nat) -> SchemaArgumentsNil))
    7 (Mkdtuple2 7 ()) [] (SchemaNatValue 7) [SchemaNatValue 7] SchemaNat
    [SchemaRefine SchemaNat
      (SchemaEqual (SchemaBound 1) (SchemaNatValue 7))]
    ()
    (SchemaArgumentDerivationCons
      (fun (_:nat) -> SchemaArgumentsNil)
      7 () [SchemaNatValue 7] (SchemaNatValue 7) []
      (SchemaRefine SchemaNat
        (SchemaEqual (SchemaBound 1) (SchemaNatValue 7))) []
      ()
      SchemaArgumentDerivationNil)

let argument_prefix_substitution_respects_refine_binder ()
  : Lemma (ensures
      substitute_schema_type
        (argument_prefix_substitution [SchemaNatValue 7])
        (SchemaRefine SchemaNat
          (SchemaEqual (SchemaBound 1) (SchemaNatValue 7))) ==
      SchemaRefine SchemaNat
        (SchemaEqual (SchemaNatValue 7) (SchemaNatValue 7))) =
  let sigma1 = (fun (index:nat) ->
    if index = 0 then SchemaNatValue 7 else SchemaBound (index - 1)) in
  let pointwise : schema_substitution_pointwise
      (argument_prefix_substitution [SchemaNatValue 7]) sigma1 =
    fun index -> () in
  substitute_type_pointwise
    (argument_prefix_substitution [SchemaNatValue 7]) sigma1 pointwise
    (SchemaRefine SchemaNat
      (SchemaEqual (SchemaBound 1) (SchemaNatValue 7)));
  assert (substitute_schema_type sigma1
    (SchemaRefine SchemaNat
      (SchemaEqual (SchemaBound 1) (SchemaNatValue 7))) ==
    SchemaRefine SchemaNat
      (SchemaEqual (SchemaNatValue 7) (SchemaNatValue 7)));
  ()
