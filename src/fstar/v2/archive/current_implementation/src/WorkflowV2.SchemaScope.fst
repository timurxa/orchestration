module WorkflowV2.SchemaScope

open FStar.List.Tot
open FStar.List.Tot.Properties
open WorkflowV2.Kernel

// Locally nameless scope for schema-bound values. Sigma's second type and a
// refinement predicate introduce one value binder; every other child stays
// in the current scope.
let rec schema_value_scoped (depth:nat) (e:schema_value_expr) : Tot bool
    (decreases e) =
  match e with
  | SchemaBound n -> n < depth
  | SchemaRoot -> true
  | SchemaPort _ -> true
  | SchemaConstant _ _ -> true
  | SchemaUnitValue -> true
  | SchemaBoolValue _ -> true
  | SchemaNatValue _ -> true
  | SchemaIntValue _ -> true
  | SchemaPairValue left right ->
      schema_value_scoped depth left && schema_value_scoped depth right
  | SchemaFstValue pair -> schema_value_scoped depth pair
  | SchemaSndValue pair -> schema_value_scoped depth pair
  | SchemaConstructorValue _ args -> schema_values_scoped depth args
  | SchemaIndexCallValue _ args -> schema_values_scoped depth args

and schema_values_scoped (depth:nat) (es:list schema_value_expr) : Tot bool
    (decreases es) =
  match es with
  | [] -> true
  | e::tail -> schema_value_scoped depth e && schema_values_scoped depth tail

and schema_predicate_scoped (depth:nat) (p:schema_predicate_expr) : Tot bool
    (decreases p) =
  match p with
  | SchemaTrue -> true
  | SchemaFalse -> true
  | SchemaEqual left right ->
      schema_value_scoped depth left && schema_value_scoped depth right
  | SchemaAnd left right ->
      schema_predicate_scoped depth left && schema_predicate_scoped depth right

and schema_type_scoped (depth:nat) (t:schema_type_expr) : Tot bool
    (decreases t) =
  match t with
  | SchemaAtom _ -> true
  | SchemaUnit -> true
  | SchemaBool -> true
  | SchemaNat -> true
  | SchemaInt -> true
  | SchemaProduct left right ->
      schema_type_scoped depth left && schema_type_scoped depth right
  | SchemaSum left right ->
      schema_type_scoped depth left && schema_type_scoped depth right
  | SchemaList item -> schema_type_scoped depth item
  | SchemaOption item -> schema_type_scoped depth item
  | SchemaSigma domain codomain ->
      schema_type_scoped depth domain && schema_type_scoped (depth + 1) codomain
  | SchemaFamily _ args -> schema_values_scoped depth args
  | SchemaRefine base predicate ->
      schema_type_scoped depth base && schema_predicate_scoped (depth + 1) predicate

// Lift indices at or above cutoff by amount. This operation is used when a
// substitution is extended beneath a binder.
let rec lift_schema_value (amount cutoff:nat) (e:schema_value_expr)
    : Tot schema_value_expr (decreases e) =
  match e with
  | SchemaBound n ->
      if n < cutoff then SchemaBound n else SchemaBound (n + amount)
  | SchemaRoot -> SchemaRoot
  | SchemaPort k -> SchemaPort k
  | SchemaConstant c b -> SchemaConstant c b
  | SchemaUnitValue -> SchemaUnitValue
  | SchemaBoolValue b -> SchemaBoolValue b
  | SchemaNatValue n -> SchemaNatValue n
  | SchemaIntValue n -> SchemaIntValue n
  | SchemaPairValue left right ->
      SchemaPairValue (lift_schema_value amount cutoff left)
        (lift_schema_value amount cutoff right)
  | SchemaFstValue pair -> SchemaFstValue (lift_schema_value amount cutoff pair)
  | SchemaSndValue pair -> SchemaSndValue (lift_schema_value amount cutoff pair)
  | SchemaConstructorValue id args ->
      SchemaConstructorValue id (lift_schema_values amount cutoff args)
  | SchemaIndexCallValue id args ->
      SchemaIndexCallValue id (lift_schema_values amount cutoff args)

and lift_schema_values (amount cutoff:nat) (es:list schema_value_expr)
    : Tot (list schema_value_expr) (decreases es) =
  match es with
  | [] -> []
  | e::tail -> lift_schema_value amount cutoff e ::
               lift_schema_values amount cutoff tail

and lift_schema_predicate (amount cutoff:nat) (p:schema_predicate_expr)
    : Tot schema_predicate_expr (decreases p) =
  match p with
  | SchemaTrue -> SchemaTrue
  | SchemaFalse -> SchemaFalse
  | SchemaEqual left right ->
      SchemaEqual (lift_schema_value amount cutoff left)
        (lift_schema_value amount cutoff right)
  | SchemaAnd left right ->
      SchemaAnd (lift_schema_predicate amount cutoff left)
        (lift_schema_predicate amount cutoff right)

and lift_schema_type (amount cutoff:nat) (t:schema_type_expr)
    : Tot schema_type_expr (decreases t) =
  match t with
  | SchemaAtom id -> SchemaAtom id
  | SchemaUnit -> SchemaUnit
  | SchemaBool -> SchemaBool
  | SchemaNat -> SchemaNat
  | SchemaInt -> SchemaInt
  | SchemaProduct left right ->
      SchemaProduct (lift_schema_type amount cutoff left)
        (lift_schema_type amount cutoff right)
  | SchemaSum left right ->
      SchemaSum (lift_schema_type amount cutoff left)
        (lift_schema_type amount cutoff right)
  | SchemaList item -> SchemaList (lift_schema_type amount cutoff item)
  | SchemaOption item -> SchemaOption (lift_schema_type amount cutoff item)
  | SchemaSigma domain codomain ->
      SchemaSigma (lift_schema_type amount cutoff domain)
        (lift_schema_type amount (cutoff + 1) codomain)
  | SchemaFamily id args ->
      SchemaFamily id (lift_schema_values amount cutoff args)
  | SchemaRefine base predicate ->
      SchemaRefine (lift_schema_type amount cutoff base)
        (lift_schema_predicate amount (cutoff + 1) predicate)

// Lifting preserves the set of well-scoped bound indices.
let bool_and_true_left (left right:bool) (h:(left && right) == true)
    : Lemma (left == true) = ()

let bool_and_true_right (left right:bool) (h:(left && right) == true)
    : Lemma (right == true) = ()

let rec schema_value_lift_preserves_scope (depth amount cutoff:nat)
    (e:schema_value_expr) (h:schema_value_scoped depth e == true)
    : Lemma (ensures (schema_value_scoped (depth + amount)
               (lift_schema_value amount cutoff e)))
      (decreases e) =
  match e with
  | SchemaBound n ->
      if n < cutoff then () else ()
  | SchemaRoot -> ()
  | SchemaPort _ -> ()
  | SchemaConstant _ _ -> ()
  | SchemaUnitValue -> ()
  | SchemaBoolValue _ -> ()
  | SchemaNatValue _ -> ()
  | SchemaIntValue _ -> ()
  | SchemaPairValue left right ->
      bool_and_true_left (schema_value_scoped depth left)
        (schema_value_scoped depth right) h;
      bool_and_true_right (schema_value_scoped depth left)
        (schema_value_scoped depth right) h;
      schema_value_lift_preserves_scope depth amount cutoff left
        (bool_and_true_left (schema_value_scoped depth left)
          (schema_value_scoped depth right) h);
      schema_value_lift_preserves_scope depth amount cutoff right
        (bool_and_true_right (schema_value_scoped depth left)
          (schema_value_scoped depth right) h)
  | SchemaFstValue pair ->
      schema_value_lift_preserves_scope depth amount cutoff pair h
  | SchemaSndValue pair ->
      schema_value_lift_preserves_scope depth amount cutoff pair h
  | SchemaConstructorValue _ args ->
      schema_values_lift_preserves_scope depth amount cutoff args h
  | SchemaIndexCallValue _ args ->
      schema_values_lift_preserves_scope depth amount cutoff args h

and schema_values_lift_preserves_scope (depth amount cutoff:nat)
    (es:list schema_value_expr) (h:schema_values_scoped depth es == true)
    : Lemma (ensures (schema_values_scoped (depth + amount)
               (lift_schema_values amount cutoff es)))
      (decreases es) =
  match es with
  | [] -> ()
  | e::tail ->
      bool_and_true_left (schema_value_scoped depth e)
        (schema_values_scoped depth tail) h;
      bool_and_true_right (schema_value_scoped depth e)
        (schema_values_scoped depth tail) h;
      schema_value_lift_preserves_scope depth amount cutoff e
        (bool_and_true_left (schema_value_scoped depth e)
          (schema_values_scoped depth tail) h);
      schema_values_lift_preserves_scope depth amount cutoff tail
        (bool_and_true_right (schema_value_scoped depth e)
          (schema_values_scoped depth tail) h)

and schema_predicate_lift_preserves_scope (depth amount cutoff:nat)
    (p:schema_predicate_expr) (h:schema_predicate_scoped depth p == true)
    : Lemma (ensures (schema_predicate_scoped (depth + amount)
               (lift_schema_predicate amount cutoff p)))
      (decreases p) =
  match p with
  | SchemaTrue -> ()
  | SchemaFalse -> ()
  | SchemaEqual left right ->
      bool_and_true_left (schema_value_scoped depth left)
        (schema_value_scoped depth right) h;
      bool_and_true_right (schema_value_scoped depth left)
        (schema_value_scoped depth right) h;
      schema_value_lift_preserves_scope depth amount cutoff left
        (bool_and_true_left (schema_value_scoped depth left)
          (schema_value_scoped depth right) h);
      schema_value_lift_preserves_scope depth amount cutoff right
        (bool_and_true_right (schema_value_scoped depth left)
          (schema_value_scoped depth right) h)
  | SchemaAnd left right ->
      bool_and_true_left (schema_predicate_scoped depth left)
        (schema_predicate_scoped depth right) h;
      bool_and_true_right (schema_predicate_scoped depth left)
        (schema_predicate_scoped depth right) h;
      schema_predicate_lift_preserves_scope depth amount cutoff left
        (bool_and_true_left (schema_predicate_scoped depth left)
          (schema_predicate_scoped depth right) h);
      schema_predicate_lift_preserves_scope depth amount cutoff right
        (bool_and_true_right (schema_predicate_scoped depth left)
          (schema_predicate_scoped depth right) h)

and schema_type_lift_preserves_scope (depth amount cutoff:nat)
    (t:schema_type_expr) (h:schema_type_scoped depth t == true)
    : Lemma (ensures (schema_type_scoped (depth + amount)
               (lift_schema_type amount cutoff t)))
      (decreases t) =
  match t with
  | SchemaAtom _ -> ()
  | SchemaUnit -> ()
  | SchemaBool -> ()
  | SchemaNat -> ()
  | SchemaInt -> ()
  | SchemaProduct left right ->
      bool_and_true_left (schema_type_scoped depth left)
        (schema_type_scoped depth right) h;
      bool_and_true_right (schema_type_scoped depth left)
        (schema_type_scoped depth right) h;
      schema_type_lift_preserves_scope depth amount cutoff left
        (bool_and_true_left (schema_type_scoped depth left)
          (schema_type_scoped depth right) h);
      schema_type_lift_preserves_scope depth amount cutoff right
        (bool_and_true_right (schema_type_scoped depth left)
          (schema_type_scoped depth right) h)
  | SchemaSum left right ->
      bool_and_true_left (schema_type_scoped depth left)
        (schema_type_scoped depth right) h;
      bool_and_true_right (schema_type_scoped depth left)
        (schema_type_scoped depth right) h;
      schema_type_lift_preserves_scope depth amount cutoff left
        (bool_and_true_left (schema_type_scoped depth left)
          (schema_type_scoped depth right) h);
      schema_type_lift_preserves_scope depth amount cutoff right
        (bool_and_true_right (schema_type_scoped depth left)
          (schema_type_scoped depth right) h)
  | SchemaList item -> schema_type_lift_preserves_scope depth amount cutoff item h
  | SchemaOption item -> schema_type_lift_preserves_scope depth amount cutoff item h
  | SchemaSigma domain codomain ->
      bool_and_true_left (schema_type_scoped depth domain)
        (schema_type_scoped (depth + 1) codomain) h;
      bool_and_true_right (schema_type_scoped depth domain)
        (schema_type_scoped (depth + 1) codomain) h;
      schema_type_lift_preserves_scope depth amount cutoff domain
        (bool_and_true_left (schema_type_scoped depth domain)
          (schema_type_scoped (depth + 1) codomain) h);
      schema_type_lift_preserves_scope (depth + 1) amount (cutoff + 1)
        codomain (bool_and_true_right (schema_type_scoped depth domain)
          (schema_type_scoped (depth + 1) codomain) h)
  | SchemaFamily _ args ->
      schema_values_lift_preserves_scope depth amount cutoff args h
  | SchemaRefine base predicate ->
      bool_and_true_left (schema_type_scoped depth base)
        (schema_predicate_scoped (depth + 1) predicate) h;
      bool_and_true_right (schema_type_scoped depth base)
        (schema_predicate_scoped (depth + 1) predicate) h;
      schema_type_lift_preserves_scope depth amount cutoff base
        (bool_and_true_left (schema_type_scoped depth base)
          (schema_predicate_scoped (depth + 1) predicate) h);
      schema_predicate_lift_preserves_scope (depth + 1) amount (cutoff + 1)
        predicate (bool_and_true_right (schema_type_scoped depth base)
          (schema_predicate_scoped (depth + 1) predicate) h)

type schema_substitution = nat -> schema_value_expr

type schema_substitution_scope (depth target:nat)
    (sigma:schema_substitution) =
  n:nat{n < depth} -> schema_value_scoped target (sigma n) == true

let lift_schema_substitution (sigma:schema_substitution) : schema_substitution =
  fun n -> if n = 0 then SchemaBound 0
           else lift_schema_value 1 0 (sigma (n - 1))

let nat_predicate_below_bound (n depth:nat)
    : Lemma (requires (n > 0 /\ n < depth + 1))
            (ensures (n - 1 < depth)) = ()

let rec substitute_schema_value (sigma:schema_substitution)
    (e:schema_value_expr) : Tot schema_value_expr (decreases e) =
  match e with
  | SchemaBound n -> sigma n
  | SchemaRoot -> SchemaRoot
  | SchemaPort k -> SchemaPort k
  | SchemaConstant c b -> SchemaConstant c b
  | SchemaUnitValue -> SchemaUnitValue
  | SchemaBoolValue b -> SchemaBoolValue b
  | SchemaNatValue n -> SchemaNatValue n
  | SchemaIntValue n -> SchemaIntValue n
  | SchemaPairValue left right ->
      SchemaPairValue (substitute_schema_value sigma left)
        (substitute_schema_value sigma right)
  | SchemaFstValue pair -> SchemaFstValue (substitute_schema_value sigma pair)
  | SchemaSndValue pair -> SchemaSndValue (substitute_schema_value sigma pair)
  | SchemaConstructorValue id args ->
      SchemaConstructorValue id (substitute_schema_values sigma args)
  | SchemaIndexCallValue id args ->
      SchemaIndexCallValue id (substitute_schema_values sigma args)

and substitute_schema_values (sigma:schema_substitution)
    (es:list schema_value_expr) : Tot (list schema_value_expr) (decreases es) =
  match es with
  | [] -> []
  | e::tail -> substitute_schema_value sigma e ::
               substitute_schema_values sigma tail

and substitute_schema_predicate (sigma:schema_substitution)
    (p:schema_predicate_expr) : Tot schema_predicate_expr (decreases p) =
  match p with
  | SchemaTrue -> SchemaTrue
  | SchemaFalse -> SchemaFalse
  | SchemaEqual left right ->
      SchemaEqual (substitute_schema_value sigma left)
        (substitute_schema_value sigma right)
  | SchemaAnd left right ->
      SchemaAnd (substitute_schema_predicate sigma left)
        (substitute_schema_predicate sigma right)

and substitute_schema_type (sigma:schema_substitution)
    (t:schema_type_expr) : Tot schema_type_expr (decreases t) =
  match t with
  | SchemaAtom id -> SchemaAtom id
  | SchemaUnit -> SchemaUnit
  | SchemaBool -> SchemaBool
  | SchemaNat -> SchemaNat
  | SchemaInt -> SchemaInt
  | SchemaProduct left right ->
      SchemaProduct (substitute_schema_type sigma left)
        (substitute_schema_type sigma right)
  | SchemaSum left right ->
      SchemaSum (substitute_schema_type sigma left)
        (substitute_schema_type sigma right)
  | SchemaList item -> SchemaList (substitute_schema_type sigma item)
  | SchemaOption item -> SchemaOption (substitute_schema_type sigma item)
  | SchemaSigma domain codomain ->
      SchemaSigma (substitute_schema_type sigma domain)
        (substitute_schema_type (lift_schema_substitution sigma) codomain)
  | SchemaFamily id args ->
      SchemaFamily id (substitute_schema_values sigma args)
  | SchemaRefine base predicate ->
      SchemaRefine (substitute_schema_type sigma base)
        (substitute_schema_predicate (lift_schema_substitution sigma) predicate)

let identity_schema_substitution : schema_substitution = SchemaBound

let substitute0_schema_value (replacement:schema_value_expr)
    (e:schema_value_expr) : schema_value_expr =
  substitute_schema_value
    (fun n -> if n = 0 then replacement else SchemaBound (n - 1)) e

let substitute0_schema_predicate (replacement:schema_value_expr)
    (p:schema_predicate_expr) : schema_predicate_expr =
  substitute_schema_predicate
    (fun n -> if n = 0 then replacement else SchemaBound (n - 1)) p

let substitute0_schema_type (replacement:schema_value_expr)
    (t:schema_type_expr) : schema_type_expr =
  substitute_schema_type
    (fun n -> if n = 0 then replacement else SchemaBound (n - 1)) t

let lift_schema_substitution_preserves_scope (depth target:nat)
    (sigma:schema_substitution) (n:nat{n < depth + 1})
    (h:schema_substitution_scope depth target sigma)
    : Lemma (schema_value_scoped (target + 1)
        (lift_schema_substitution sigma n) == true) =
  if n = 0 then ()
  else (
    assert (n > 0);
    nat_predicate_below_bound n depth;
    schema_value_lift_preserves_scope target 1 0 (sigma (n - 1))
      (h (n - 1));
    ()
  )

let rec schema_value_substitute_preserves_scope (depth target:nat)
    (sigma:schema_substitution) (e:schema_value_expr)
    (h:schema_value_scoped depth e == true)
    (hs:schema_substitution_scope depth target sigma)
    : Lemma (ensures (schema_value_scoped target
               (substitute_schema_value sigma e) == true))
      (decreases e) =
  match e with
  | SchemaBound n -> hs n
  | SchemaRoot -> ()
  | SchemaPort _ -> ()
  | SchemaConstant _ _ -> ()
  | SchemaUnitValue -> ()
  | SchemaBoolValue _ -> ()
  | SchemaNatValue _ -> ()
  | SchemaIntValue _ -> ()
  | SchemaPairValue left right ->
      bool_and_true_left (schema_value_scoped depth left)
        (schema_value_scoped depth right) h;
      bool_and_true_right (schema_value_scoped depth left)
        (schema_value_scoped depth right) h;
      schema_value_substitute_preserves_scope depth target sigma left
        (bool_and_true_left (schema_value_scoped depth left)
          (schema_value_scoped depth right) h) hs;
      schema_value_substitute_preserves_scope depth target sigma right
        (bool_and_true_right (schema_value_scoped depth left)
          (schema_value_scoped depth right) h) hs
  | SchemaFstValue pair ->
      schema_value_substitute_preserves_scope depth target sigma pair h hs
  | SchemaSndValue pair ->
      schema_value_substitute_preserves_scope depth target sigma pair h hs
  | SchemaConstructorValue _ args ->
      schema_values_substitute_preserves_scope depth target sigma args h hs
  | SchemaIndexCallValue _ args ->
      schema_values_substitute_preserves_scope depth target sigma args h hs

and schema_values_substitute_preserves_scope (depth target:nat)
    (sigma:schema_substitution) (es:list schema_value_expr)
    (h:schema_values_scoped depth es == true)
    (hs:schema_substitution_scope depth target sigma)
    : Lemma (ensures (schema_values_scoped target
               (substitute_schema_values sigma es) == true))
      (decreases es) =
  match es with
  | [] -> ()
  | e::tail ->
      bool_and_true_left (schema_value_scoped depth e)
        (schema_values_scoped depth tail) h;
      bool_and_true_right (schema_value_scoped depth e)
        (schema_values_scoped depth tail) h;
      schema_value_substitute_preserves_scope depth target sigma e
        (bool_and_true_left (schema_value_scoped depth e)
          (schema_values_scoped depth tail) h) hs;
      schema_values_substitute_preserves_scope depth target sigma tail
        (bool_and_true_right (schema_value_scoped depth e)
          (schema_values_scoped depth tail) h) hs

and schema_predicate_substitute_preserves_scope (depth target:nat)
    (sigma:schema_substitution) (p:schema_predicate_expr)
    (h:schema_predicate_scoped depth p == true)
    (hs:schema_substitution_scope depth target sigma)
    : Lemma (ensures (schema_predicate_scoped target
               (substitute_schema_predicate sigma p) == true))
      (decreases p) =
  match p with
  | SchemaTrue -> ()
  | SchemaFalse -> ()
  | SchemaEqual left right ->
      bool_and_true_left (schema_value_scoped depth left)
        (schema_value_scoped depth right) h;
      bool_and_true_right (schema_value_scoped depth left)
        (schema_value_scoped depth right) h;
      schema_value_substitute_preserves_scope depth target sigma left
        (bool_and_true_left (schema_value_scoped depth left)
          (schema_value_scoped depth right) h) hs;
      schema_value_substitute_preserves_scope depth target sigma right
        (bool_and_true_right (schema_value_scoped depth left)
          (schema_value_scoped depth right) h) hs
  | SchemaAnd left right ->
      bool_and_true_left (schema_predicate_scoped depth left)
        (schema_predicate_scoped depth right) h;
      bool_and_true_right (schema_predicate_scoped depth left)
        (schema_predicate_scoped depth right) h;
      schema_predicate_substitute_preserves_scope depth target sigma left
        (bool_and_true_left (schema_predicate_scoped depth left)
          (schema_predicate_scoped depth right) h) hs;
      schema_predicate_substitute_preserves_scope depth target sigma right
        (bool_and_true_right (schema_predicate_scoped depth left)
          (schema_predicate_scoped depth right) h) hs

and schema_type_substitute_preserves_scope (depth target:nat)
    (sigma:schema_substitution) (t:schema_type_expr)
    (h:schema_type_scoped depth t == true)
    (hs:schema_substitution_scope depth target sigma)
    : Lemma (ensures (schema_type_scoped target
               (substitute_schema_type sigma t) == true))
      (decreases t) =
  match t with
  | SchemaAtom _ -> ()
  | SchemaUnit -> ()
  | SchemaBool -> ()
  | SchemaNat -> ()
  | SchemaInt -> ()
  | SchemaProduct left right ->
      bool_and_true_left (schema_type_scoped depth left)
        (schema_type_scoped depth right) h;
      bool_and_true_right (schema_type_scoped depth left)
        (schema_type_scoped depth right) h;
      schema_type_substitute_preserves_scope depth target sigma left
        (bool_and_true_left (schema_type_scoped depth left)
          (schema_type_scoped depth right) h) hs;
      schema_type_substitute_preserves_scope depth target sigma right
        (bool_and_true_right (schema_type_scoped depth left)
          (schema_type_scoped depth right) h) hs
  | SchemaSum left right ->
      bool_and_true_left (schema_type_scoped depth left)
        (schema_type_scoped depth right) h;
      bool_and_true_right (schema_type_scoped depth left)
        (schema_type_scoped depth right) h;
      schema_type_substitute_preserves_scope depth target sigma left
        (bool_and_true_left (schema_type_scoped depth left)
          (schema_type_scoped depth right) h) hs;
      schema_type_substitute_preserves_scope depth target sigma right
        (bool_and_true_right (schema_type_scoped depth left)
          (schema_type_scoped depth right) h) hs
  | SchemaList item -> schema_type_substitute_preserves_scope depth target sigma item h hs
  | SchemaOption item -> schema_type_substitute_preserves_scope depth target sigma item h hs
  | SchemaSigma domain codomain ->
      bool_and_true_left (schema_type_scoped depth domain)
        (schema_type_scoped (depth + 1) codomain) h;
      bool_and_true_right (schema_type_scoped depth domain)
        (schema_type_scoped (depth + 1) codomain) h;
      schema_type_substitute_preserves_scope depth target sigma domain
        (bool_and_true_left (schema_type_scoped depth domain)
          (schema_type_scoped (depth + 1) codomain) h) hs;
      schema_type_substitute_preserves_scope (depth + 1) (target + 1)
        (lift_schema_substitution sigma) codomain
        (bool_and_true_right (schema_type_scoped depth domain)
          (schema_type_scoped (depth + 1) codomain) h)
        (fun n -> lift_schema_substitution_preserves_scope
          depth target sigma n hs)
  | SchemaFamily _ args ->
      schema_values_substitute_preserves_scope depth target sigma args h hs
  | SchemaRefine base predicate ->
      bool_and_true_left (schema_type_scoped depth base)
        (schema_predicate_scoped (depth + 1) predicate) h;
      bool_and_true_right (schema_type_scoped depth base)
        (schema_predicate_scoped (depth + 1) predicate) h;
      schema_type_substitute_preserves_scope depth target sigma base
        (bool_and_true_left (schema_type_scoped depth base)
          (schema_predicate_scoped (depth + 1) predicate) h) hs;
      schema_predicate_substitute_preserves_scope (depth + 1) (target + 1)
        (lift_schema_substitution sigma) predicate
        (bool_and_true_right (schema_type_scoped depth base)
          (schema_predicate_scoped (depth + 1) predicate) h)
        (fun n -> lift_schema_substitution_preserves_scope
          depth target sigma n hs)

// Proof examples fix the intended binder convention at the API boundary.
let singleton_refinement_example : schema_type_expr =
  SchemaRefine SchemaNat
    (SchemaEqual (SchemaBound 0) (SchemaNatValue 3))

let singleton_refinement_is_scoped () : Lemma (ensures
    (schema_type_scoped 0 singleton_refinement_example == true)) = ()

let singleton_refinement_scoped_at_depth_one () : Lemma (ensures
    (schema_type_scoped 1 singleton_refinement_example == true)) = ()

let free_bound_is_rejected () : Lemma (ensures
    (schema_value_scoped 0 (SchemaBound 0) == false)) = ()

let nested_sigma_refine_example : schema_type_expr =
  SchemaSigma SchemaNat
    (SchemaRefine SchemaNat
      (SchemaEqual (SchemaBound 0) (SchemaBound 2)))

let nested_sigma_refine_is_scoped () : Lemma (ensures
    (schema_type_scoped 1 nested_sigma_refine_example == true)) = ()

let substitute_outer_value_preserves_nested_binders () : Lemma (ensures
    (substitute0_schema_type SchemaRoot nested_sigma_refine_example ==
      SchemaSigma SchemaNat
        (SchemaRefine SchemaNat
          (SchemaEqual (SchemaBound 0) SchemaRoot)))) = ()
// Pointwise relation avoids requiring equality of F* functions.
type schema_substitution_pointwise (left right:schema_substitution) =
  n:nat -> Lemma (left n == right n)

let lift_schema_substitution_pointwise
    (left right:schema_substitution)
    (h:schema_substitution_pointwise left right)
    (n:nat)
    : Lemma (lift_schema_substitution left n ==
             lift_schema_substitution right n) =
  if n = 0 then ()
  else (
    h (n - 1);
    ()
  )

let rec substitute_value_pointwise
    (left right:schema_substitution)
    (h:schema_substitution_pointwise left right)
    (e:schema_value_expr)
    : Lemma (ensures (substitute_schema_value left e ==
             substitute_schema_value right e))
      (decreases e) =
  match e with
  | SchemaBound n -> h n
  | SchemaRoot -> ()
  | SchemaPort _ -> ()
  | SchemaConstant _ _ -> ()
  | SchemaUnitValue -> ()
  | SchemaBoolValue _ -> ()
  | SchemaNatValue _ -> ()
  | SchemaIntValue _ -> ()
  | SchemaPairValue a b ->
      substitute_value_pointwise left right h a;
      substitute_value_pointwise left right h b
  | SchemaFstValue a -> substitute_value_pointwise left right h a
  | SchemaSndValue a -> substitute_value_pointwise left right h a
  | SchemaConstructorValue _ xs ->
      substitute_values_pointwise left right h xs
  | SchemaIndexCallValue _ xs ->
      substitute_values_pointwise left right h xs

and substitute_values_pointwise
    (left right:schema_substitution)
    (h:schema_substitution_pointwise left right)
    (xs:list schema_value_expr)
    : Lemma (ensures (substitute_schema_values left xs ==
             substitute_schema_values right xs))
      (decreases xs) =
  match xs with
  | [] -> ()
  | x::tail ->
      substitute_value_pointwise left right h x;
      substitute_values_pointwise left right h tail

and substitute_predicate_pointwise
    (left right:schema_substitution)
    (h:schema_substitution_pointwise left right)
    (p:schema_predicate_expr)
    : Lemma (ensures (substitute_schema_predicate left p ==
             substitute_schema_predicate right p))
      (decreases p) =
  match p with
  | SchemaTrue -> ()
  | SchemaFalse -> ()
  | SchemaEqual a b ->
      substitute_value_pointwise left right h a;
      substitute_value_pointwise left right h b
  | SchemaAnd a b ->
      substitute_predicate_pointwise left right h a;
      substitute_predicate_pointwise left right h b

and substitute_type_pointwise
    (left right:schema_substitution)
    (h:schema_substitution_pointwise left right)
    (t:schema_type_expr)
    : Lemma (ensures (substitute_schema_type left t ==
             substitute_schema_type right t))
      (decreases t) =
  match t with
  | SchemaAtom _ -> ()
  | SchemaUnit -> ()
  | SchemaBool -> ()
  | SchemaNat -> ()
  | SchemaInt -> ()
  | SchemaProduct a b ->
      substitute_type_pointwise left right h a;
      substitute_type_pointwise left right h b
  | SchemaSum a b ->
      substitute_type_pointwise left right h a;
      substitute_type_pointwise left right h b
  | SchemaList a -> substitute_type_pointwise left right h a
  | SchemaOption a -> substitute_type_pointwise left right h a
  | SchemaSigma a b ->
      substitute_type_pointwise left right h a;
      substitute_type_pointwise (lift_schema_substitution left)
        (lift_schema_substitution right)
        (fun n -> lift_schema_substitution_pointwise left right h n) b
  | SchemaFamily _ xs -> substitute_values_pointwise left right h xs
  | SchemaRefine a p ->
      substitute_type_pointwise left right h a;
      substitute_predicate_pointwise (lift_schema_substitution left)
        (lift_schema_substitution right)
        (fun n -> lift_schema_substitution_pointwise left right h n) p

let rec substitute_value_identity
    (sigma:schema_substitution)
    (h:schema_substitution_pointwise sigma SchemaBound)
    (e:schema_value_expr)
    : Lemma (ensures (substitute_schema_value sigma e == e))
      (decreases e) =
  match e with
  | SchemaBound n -> h n
  | SchemaRoot -> ()
  | SchemaPort _ -> ()
  | SchemaConstant _ _ -> ()
  | SchemaUnitValue -> ()
  | SchemaBoolValue _ -> ()
  | SchemaNatValue _ -> ()
  | SchemaIntValue _ -> ()
  | SchemaPairValue a b ->
      substitute_value_identity sigma h a;
      substitute_value_identity sigma h b
  | SchemaFstValue a -> substitute_value_identity sigma h a
  | SchemaSndValue a -> substitute_value_identity sigma h a
  | SchemaConstructorValue _ xs -> substitute_values_identity sigma h xs
  | SchemaIndexCallValue _ xs -> substitute_values_identity sigma h xs

and substitute_values_identity
    (sigma:schema_substitution)
    (h:schema_substitution_pointwise sigma SchemaBound)
    (xs:list schema_value_expr)
    : Lemma (ensures (substitute_schema_values sigma xs == xs))
      (decreases xs) =
  match xs with
  | [] -> ()
  | x::tail ->
      substitute_value_identity sigma h x;
      substitute_values_identity sigma h tail

and substitute_predicate_identity
    (sigma:schema_substitution)
    (h:schema_substitution_pointwise sigma SchemaBound)
    (p:schema_predicate_expr)
    : Lemma (ensures (substitute_schema_predicate sigma p == p))
      (decreases p) =
  match p with
  | SchemaTrue -> ()
  | SchemaFalse -> ()
  | SchemaEqual a b ->
      substitute_value_identity sigma h a;
      substitute_value_identity sigma h b
  | SchemaAnd a b ->
      substitute_predicate_identity sigma h a;
      substitute_predicate_identity sigma h b

and substitute_type_identity
    (sigma:schema_substitution)
    (h:schema_substitution_pointwise sigma SchemaBound)
    (t:schema_type_expr)
    : Lemma (ensures (substitute_schema_type sigma t == t))
      (decreases t) =
  match t with
  | SchemaAtom _ -> ()
  | SchemaUnit -> ()
  | SchemaBool -> ()
  | SchemaNat -> ()
  | SchemaInt -> ()
  | SchemaProduct a b ->
      substitute_type_identity sigma h a;
      substitute_type_identity sigma h b
  | SchemaSum a b ->
      substitute_type_identity sigma h a;
      substitute_type_identity sigma h b
  | SchemaList a -> substitute_type_identity sigma h a
  | SchemaOption a -> substitute_type_identity sigma h a
  | SchemaSigma a b ->
      substitute_type_identity sigma h a;
      substitute_type_identity (lift_schema_substitution sigma)
        (fun n -> lift_schema_substitution_pointwise sigma SchemaBound h n) b
  | SchemaFamily _ xs -> substitute_values_identity sigma h xs
  | SchemaRefine a p ->
      substitute_type_identity sigma h a;
      substitute_predicate_identity (lift_schema_substitution sigma)
        (fun n -> lift_schema_substitution_pointwise sigma SchemaBound h n) p

let schema_identity_substitution_pointwise (n:nat)
    : Lemma (identity_schema_substitution n == SchemaBound n) = ()

let substitute_type_identity_exact (t:schema_type_expr)
    : Lemma (ensures
        (substitute_schema_type identity_schema_substitution t == t)) =
  substitute_type_identity identity_schema_substitution
    schema_identity_substitution_pointwise t

let rec lift_value_substitution_commutes
    (sigma:schema_substitution) (e:schema_value_expr)
    : Lemma (ensures
        (lift_schema_value 1 0 (substitute_schema_value sigma e) ==
         substitute_schema_value (lift_schema_substitution sigma)
           (lift_schema_value 1 0 e)))
      (decreases e) =
  match e with
  | SchemaBound _ -> ()
  | SchemaRoot -> ()
  | SchemaPort _ -> ()
  | SchemaConstant _ _ -> ()
  | SchemaUnitValue -> ()
  | SchemaBoolValue _ -> ()
  | SchemaNatValue _ -> ()
  | SchemaIntValue _ -> ()
  | SchemaPairValue a b ->
      lift_value_substitution_commutes sigma a;
      lift_value_substitution_commutes sigma b
  | SchemaFstValue a -> lift_value_substitution_commutes sigma a
  | SchemaSndValue a -> lift_value_substitution_commutes sigma a
  | SchemaConstructorValue _ xs ->
      lift_values_substitution_commutes sigma xs
  | SchemaIndexCallValue _ xs ->
      lift_values_substitution_commutes sigma xs

and lift_values_substitution_commutes
    (sigma:schema_substitution) (xs:list schema_value_expr)
    : Lemma (ensures
        (lift_schema_values 1 0 (substitute_schema_values sigma xs) ==
         substitute_schema_values (lift_schema_substitution sigma)
           (lift_schema_values 1 0 xs)))
      (decreases xs) =
  match xs with
  | [] -> ()
  | x::tail ->
      lift_value_substitution_commutes sigma x;
      lift_values_substitution_commutes sigma tail

let compose_schema_substitution (after before:schema_substitution)
    : schema_substitution =
  fun n -> substitute_schema_value after (before n)

let lift_compose_pointwise
    (after before:schema_substitution) (n:nat)
    : Lemma (ensures
        (lift_schema_substitution (compose_schema_substitution after before) n ==
         compose_schema_substitution (lift_schema_substitution after)
           (lift_schema_substitution before) n)) =
  if n = 0 then ()
  else
    lift_value_substitution_commutes after (before (n - 1))

let rec substitute_value_compose
    (after before:schema_substitution) (e:schema_value_expr)
    : Lemma (ensures
        (substitute_schema_value after
           (substitute_schema_value before e) ==
         substitute_schema_value (compose_schema_substitution after before) e))
      (decreases e) =
  match e with
  | SchemaBound _ -> ()
  | SchemaRoot -> ()
  | SchemaPort _ -> ()
  | SchemaConstant _ _ -> ()
  | SchemaUnitValue -> ()
  | SchemaBoolValue _ -> ()
  | SchemaNatValue _ -> ()
  | SchemaIntValue _ -> ()
  | SchemaPairValue a b ->
      substitute_value_compose after before a;
      substitute_value_compose after before b
  | SchemaFstValue a -> substitute_value_compose after before a
  | SchemaSndValue a -> substitute_value_compose after before a
  | SchemaConstructorValue _ xs -> substitute_values_compose after before xs
  | SchemaIndexCallValue _ xs -> substitute_values_compose after before xs

and substitute_values_compose
    (after before:schema_substitution) (xs:list schema_value_expr)
    : Lemma (ensures
        (substitute_schema_values after
           (substitute_schema_values before xs) ==
         substitute_schema_values (compose_schema_substitution after before) xs))
      (decreases xs) =
  match xs with
  | [] -> ()
  | x::tail ->
      substitute_value_compose after before x;
      substitute_values_compose after before tail

and substitute_predicate_compose
    (after before:schema_substitution) (p:schema_predicate_expr)
    : Lemma (ensures
        (substitute_schema_predicate after
           (substitute_schema_predicate before p) ==
         substitute_schema_predicate (compose_schema_substitution after before) p))
      (decreases p) =
  match p with
  | SchemaTrue -> ()
  | SchemaFalse -> ()
  | SchemaEqual a b ->
      substitute_value_compose after before a;
      substitute_value_compose after before b
  | SchemaAnd a b ->
      substitute_predicate_compose after before a;
      substitute_predicate_compose after before b

and substitute_type_compose
    (after before:schema_substitution) (t:schema_type_expr)
    : Lemma (ensures
        (substitute_schema_type after
           (substitute_schema_type before t) ==
         substitute_schema_type (compose_schema_substitution after before) t))
      (decreases t) =
  match t with
  | SchemaAtom _ -> ()
  | SchemaUnit -> ()
  | SchemaBool -> ()
  | SchemaNat -> ()
  | SchemaInt -> ()
  | SchemaProduct a b ->
      substitute_type_compose after before a;
      substitute_type_compose after before b
  | SchemaSum a b ->
      substitute_type_compose after before a;
      substitute_type_compose after before b
  | SchemaList a -> substitute_type_compose after before a
  | SchemaOption a -> substitute_type_compose after before a
  | SchemaSigma a b ->
      substitute_type_compose after before a;
      substitute_type_compose (lift_schema_substitution after)
        (lift_schema_substitution before) b;
      substitute_type_pointwise
        (compose_schema_substitution (lift_schema_substitution after)
          (lift_schema_substitution before))
        (lift_schema_substitution (compose_schema_substitution after before))
        (fun n -> lift_compose_pointwise after before n) b
  | SchemaFamily _ xs -> substitute_values_compose after before xs
  | SchemaRefine a p ->
      substitute_type_compose after before a;
      substitute_predicate_compose (lift_schema_substitution after)
        (lift_schema_substitution before) p;
      substitute_predicate_pointwise
        (compose_schema_substitution (lift_schema_substitution after)
          (lift_schema_substitution before))
        (lift_schema_substitution (compose_schema_substitution after before))
        (fun n -> lift_compose_pointwise after before n) p
