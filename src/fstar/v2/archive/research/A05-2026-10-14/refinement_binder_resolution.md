# A05 refinement-binder resolution

## Finding

The schema grammar already contains `Refine(T,P)` and says its meaning is the
subset of `T` satisfying `P`, but it specified a locally nameless binder only
for `Sigma`'s second type. The schema value syntax contains `Bound(nat)`, so
without another scope rule there was no way to state which candidate value
the refinement predicate tests. The context equation's `PortRefinement` entry
implicitly substitutes the output port into that predicate, revealing the
intended candidate binder without defining it.

Independent reviews (`a03_sort_audit` and `a03_pointwise_proof_design`) found
the same issue. They also checked the A05/A06/A07 boundary and the unchanged
universal edge rule.

## Decision

`Refine(T,P)` binds one candidate value of type `T` in `P`. `T` is checked in
the outer binder context; only `P` is checked in the extended context. The
denotation is the dependent subset

```text
{ z : TypeDenote(T) | PredDenote(P, rho extended by z) }
```

The existing AST constructors remain unchanged. `SchemaBound 0` is the
nearest value binder under either `Sigma`'s codomain or `Refine`'s predicate.
Free indices reject. Lift, substitution, scope, and denotation laws apply to
both binder forms. A05 owns these syntax and semantic laws; A06 proves
refinement equality under the same candidate binder/domain; A07 consumes only
facts derived from exact declared type membership.

For `Delta`, when the instantiated output family is itself `Refine(T,P)`,
substitute its refinement candidate with that node's `Port(k)` using
capture-avoiding substitution. The fact follows from membership in the
declared output type. A refinement nested under another type constructor stays
part of that type's denotation; A05 does not flatten such facts into an
independent context table. It does not narrow `LegalEnv`: every inhabitant of
the full declared type remains quantified, including all validator-accepted
external results.

## Consequences and preserved claims

- `Refine(Nat, Equal(Bound(0), NatLit(3)))` denotes the singleton containing
  3. The same free `Bound(0)` outside a binder is ill-scoped.
- In nested `Sigma`/`Refine` syntax, the nearest enclosing binder is always
  index 0; substitution must shift outer references under either binder.
- P1/P2 still quantify over all legal graph environments and require universal
  producer-output/consumer-input compatibility. No edge proof is accepted
  from an endpoint or inferred from an observed output.
- The `Sigma n. vector n` to `vector 3` rejection remains unchanged. Only
  proof evidence already entailed by a declared refinement is available.
- No grammar tag, serialization constructor, DAG edge, or module dependency
  changes. The A05 work is clarified, not expanded beyond its existing
  scope/substitution/denotation obligations.

## Alternatives rejected

1. **Treat `P` as a closed proposition.** This cannot express the intended
   singleton refinement over the candidate and contradicts subset semantics.
2. **Interpret `Bound(0)` specially without a binder rule.** This makes
   scoping and capture avoidance ambiguous, especially under nested Sigma.
3. **Add a separate predicate parameter/function to `Refine`.** This changes
   the AST and codec unnecessarily; the existing value AST already has bound
   variables and the context equation implies the candidate substitution.

## Acceptance evidence still required

The source must prove scope rejection/preservation, substitution identity and
composition, substitution and denotation commutation under both binders, and
the singleton semantic case. A checked source-level proof is required; this
design note and the reviewer agreement are not verifier evidence.
