# A03 proof feasibility review

**Role:** read-only proof design; repository source and canonical state were not
changed. The only repository write is this requested report. Scratch modules
and generated artifacts were kept under `/tmp`.

## Recommended shape

- Keep the manifest as a data-only record: format version plus a list of a
  single tagged `manifest_entry` sum. Each entry stores the domain-specific
  identity and every semantically relevant version, metadata value, and
  cross-reference. Do not put `noeq` packages, closures, validators, or proof
  witnesses in the entry.
- Give each sum constructor a distinct numeric tag. Each payload uses
  length-prefixed components; each entry is itself length-framed in the
  manifest. The public decoder requires EOF. The existing `bytes = list nat`
  model proves mathematical injectivity only.
- Use a suffix-returning decoder internally. Prove
  `decode (encode x @ suffix) == Some (x, suffix)` by constructor and field
  cases. Injectivity follows by applying `decode` to both sides of equal
  encodings, rewriting by the hypothesis, and using injectivity of `Some`.
  This does not require assumptions or proof fields.
- Keep *validity* separate from the data: per-domain no-duplicate IDs,
  sorted-by-total-key, field well-formedness, and reference closure are
  predicates. Reject duplicates on the original entry list before sorting.
  Do not deduplicate.
- Define one deterministic total key `(entry_tag, encoded_identity)` and an
  insertion sort. Prove sortedness and permutation preservation, then prove
  that two sorted permutations with unique keys are equal. The canonicalizer
  should be invariant under permutation and a fixed point on already-sorted
  input. Avoid making the comparator or sort part of a trusted abstraction.
- Define exact registry identity as a nominal wrapper around the *full
  canonical manifest bytes*. A digest can index this key only if bytes are
  checked after lookup. A `{name, version, digest}` record is not injective
  over manifests.
- Define first-order projection as equality of a projection list with the
  projection of manifest entries, with exactly-once correspondence. This is
  provable in A03. The relation from real executable tables (including
  `noeq` packages and callbacks) to these rows remains A04/P0 work.

## Proof decomposition and friction

1. **Shared identity encoding.** Move the current identity suffix encoders,
   decoders, and their roundtrip lemmas from GraphCodec to Kernel, preserving
   nominal per-domain records and wrappers. Both GraphCodec and ManifestCore
   already depend on Kernel, so this prevents a duplicate source of truth
   without a module cycle. Factor the common `(string, nat, bytes)` wire shape
   into private helpers if this remains readable; keep public typed wrappers.
2. **Tagged sum.** Prove each constructor's suffix roundtrip. For injectivity,
   equal encodings imply equal first tags; distinct tags contradict equality,
   equal tags reduce to the payload decoder theorem. The toy proof verified
   this basic argument. Typed identity wrappers and nested metadata add
   mechanical cases, not a new semantic obstacle.
3. **Lists and canonical order.** Frame each item, prove list suffix roundtrip
   by induction, then manifest roundtrip. Insertion sort termination is
   structural. A small natural-key insertion-sort proof discharged in F*;
   the real comparator needs lexicographic ordering for finite `list nat` and
   a proof that equal keys imply equal tagged IDs. This is the main routine
   proof work. Do not rely on a hash or host sorting implementation.
4. **Uniqueness and closure.** Use one generic lookup by `(tag, encoded ID)`.
   Prove lookup uniqueness from `NoDuplicateIds` by list induction. Check each
   link category by a helper that asks this lookup for the expected tag; then
   prove closure by combining those checks. Duplicate rejection should be an
   explicit boolean/option result before canonical sorting.
5. **Projection.** State an exact row relation (forward and backward, with
   uniqueness) over first-order values. Prove it by list/map induction or by
   equality of finite row lists. Do not claim it connects runtime package
   closures until A04 supplies and proves that relation.

### Alternatives rejected

- **Digest/name as identity:** collision or aliasing is not ruled out by this
  model; equal digest is not equal manifest. Retain only as an optional index.
- **One untagged identity triple for all domains:** permits cross-domain
  aliasing. A typed tagged sum makes domains disjoint.
- **Proof-bearing canonical record:** proof fields complicate equality and
  persistence. Keep evidence in predicates/lemmas, data in the manifest.
- **Sort then remove duplicates:** conceals conflicting declarations. Check
  and reject duplicates first.
- **Copy current encoders into ManifestCore:** creates two encodings and
  violates the A01 ownership boundary. Kernel should be the shared owner.

## Checked scratch probes

Scratch files: `/tmp/ManifestProofProbe.fst` and
`/tmp/ManifestSortProbe.fst`; output directories were `/tmp`. No scratch code
was copied into the repository.

Command for the tagged decoder/roundtrip/injectivity probe:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m fstar.exe \
  --cache_off --warn_error @285 --include /tmp --odir /tmp \
  /tmp/ManifestProofProbe.fst
```

Result: exit 0, `Verified module: ManifestProofProbe`,
`All verification conditions discharged successfully`. It defines two tagged
constructors, a total decoder, the suffix left-inverse, and injectivity from
that left-inverse. This validates the core proof pattern only, not the real
entry fields or framing implementation.

Command for the sortedness/insertion-sort probe:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m fstar.exe \
  --cache_off --warn_error @285 --include /tmp --odir /tmp \
  /tmp/ManifestSortProbe.fst
```

Result: exit 0, `Verified module: ManifestSortProbe`,
`All verification conditions discharged successfully`. It proves insertion
sort returns a sorted list for a natural key. It does **not** prove
permutation preservation, duplicate rejection, sorted-permutation uniqueness,
or list-of-natural lexicographic ordering; those remain A03 proofs.

Scratch toolchain observed: F* 2026.03.24 (OCaml 5.3.0), Z3 4.15.4.
These probes do not replace the repository's full verifier command.

## Additional checked lexicographic order and sort probe

Scratch module: `/tmp/LexOrderProbe.fst`. It defines a non-strict
lexicographic order on `list nat` (empty is least; compare heads numerically;
recurse on equal heads), then proves reflexivity, antisymmetry, transitivity,
and totality by structural recursion. No `assume` or `admit` appears in the
module.

The `FStar.List.Tot.Properties.total_order` shape needs some care. It is a
squashed conjunction, so the checked first-class order value uses
`FStar.Classical.forall_intro`, `forall_intro_2`, `forall_intro_3`,
`move_requires_2`, `move_requires_3`, nested
`FStar.Classical.Sugar.and_intro`, and `FStar.Squash.join_squash`. This
successfully packages the four lemmas as an explicit
`total_order #bytes lex_le`, rather than relying on an opaque sort contract.

For sorting, define the comparator as `if lex_le x y then -1 else 1`. Its
`bool_of_compare` relation is definitionally `lex_le`, so the checked total
order applies directly. This comparator can return `-1` for both directions
when values are equal; that is compatible with this library's contract,
which asks that `bool_of_compare` be a total order and does not require a
three-way comparator law. The library then proves sortedness and count
preservation for `sortWith`.

Exact command:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m fstar.exe \
  --cache_off --warn_error @285 --include /tmp --odir /tmp \
  /tmp/LexOrderProbe.fst
```

Result: exit 0, `Verified module: LexOrderProbe`,
`All verification conditions discharged successfully`. The module proves:

- `lex_total_order : total_order #bytes lex_le` with the four explicit laws;
- `sortWith_sorted` for the lexicographic comparator;
- `sortWith_permutation` count preservation, and therefore equal output
  counts whenever input counts agree.

The same file was also run with the attempted sortedness statement using
`compare_of_bool lex_le` and the `FStar.List.Tot.Properties` lemmas. That
variant failed at the `sortWith_sorted` precondition: it needs a separate
transport from `total_order lex_le` to
`total_order (bool_of_compare (compare_of_bool lex_le))`. The checked
comparator above avoids that transport by making the relation definitionally
`lex_le`.

### Trust follow-up

The scratch proof above is successfully typechecked but is **not accepted** by
the current A03 trust criterion: its first-class `total_order` construction
uses Classical/Squash helpers whose transitive path reaches the admitted
F* `elim_squash` axiom. This report establishes feasibility only for ordinary
F* verification; it does not establish no-admit transitive trust. See
`stdlib_axiom_audit.md` for the concrete dependency chain and required
constructive replacement.

### Exact remaining permutation-invariance lemma

The library provides `sortWith_permutation`, which proves equality of
`count x` for every element before/after a sort. It does not provide a theorem
that two sorted lists with equal counts and no repeated keys are equal. Thus
we have verified permutation-invariance of the *multiset/counts*, but not yet
of the resulting ordered list. A03 should prove a local theorem of the shape:

```fstar
val sorted_counts_unique : xs:list key -> ys:list key
  -> sorted lex_le xs -> sorted lex_le ys
  -> noRepeats xs -> noRepeats ys
  -> (forall k. count k xs == count k ys)
  -> Lemma (xs == ys)
```

For manifest rows, sort by the full canonical entry encoding: its prefix is
the tagged identity order, and the remaining metadata gives a deterministic
tie-break even for duplicate-ID rows before validation rejects them. Encoder
injectivity transports antisymmetry on bytes back to entry equality. The
local theorem can be proved by induction: find the first
list's head in the other list from positive count; sortedness makes both
heads the least key; antisymmetry plus no repeated keys identifies/removes
that head; recurse with count decremented. `sortWith_permutation` supplies
the count premise, while roundtrip-derived encoder injectivity supplies the
key/no-repeat correspondence. This is a focused proof gap, not a missing
primitive or an obstacle to the API.


## Verbatim checked F* scratch module

This is the exact `/tmp/LexOrderProbe.fst` source used by the
successful command above. It includes the lexicographic law proof,
the explicit `total_order` value for the sort comparator, sortedness,
and count-level permutation invariance.

```fstar
module LexOrderProbe
open FStar.List.Tot
open FStar.List.Tot.Properties

type bytes = list nat
let rec lex_le (xs ys:bytes) : Tot bool (decreases xs) =
  match xs, ys with
  | [], _ -> true
  | _::_, [] -> false
  | x::xt, y::yt -> if x < y then true else if y < x then false else lex_le xt yt
let rec lex_reflexive (xs:bytes) : Lemma (ensures lex_le xs xs) (decreases xs) =
  match xs with | [] -> () | _::tl -> lex_reflexive tl
let rec lex_antisymmetric (xs ys:bytes)
  : Lemma (requires lex_le xs ys /\ lex_le ys xs) (ensures xs == ys) (decreases xs) =
  match xs, ys with
  | [], [] -> ()
  | [], _::_ -> ()
  | _::_, [] -> ()
  | x::xt, y::yt ->
    if x < y then () else if y < x then () else begin
      lex_antisymmetric xt yt;
      ()
    end
let rec lex_transitive (xs ys zs:bytes)
  : Lemma (requires lex_le xs ys /\ lex_le ys zs) (ensures lex_le xs zs) (decreases xs) =
  match xs, ys, zs with
  | [], _, _ -> ()
  | _::_, [], _ -> ()
  | _::_, _::_, [] -> ()
  | x::xt, y::yt, z::zt ->
    if x < y then begin
      if y < z then ()
      else if z < y then assert False
      else ()
    end else if y < x then assert False
    else begin
      assert (x == y);
      if y < z then ()
      else if z < y then assert False
      else begin
        assert (lex_le xt yt);
        assert (lex_le yt zt);
        lex_transitive xt yt zt;
        ()
      end
    end
let rec lex_total (xs ys:bytes) : Lemma (ensures (lex_le xs ys \/ lex_le ys xs)) (decreases xs) =
  match xs, ys with
  | [], _ -> ()
  | _::_, [] -> ()
  | x::xt, y::yt ->
    if x < y then () else if y < x then () else lex_total xt yt
let lex_reflexive_all () : Lemma (ensures (forall xs. lex_le xs xs)) =
  FStar.Classical.forall_intro lex_reflexive
let lex_antisymmetric_all () : Lemma (ensures (forall xs ys. lex_le xs ys /\ lex_le ys xs ==> xs == ys)) =
  FStar.Classical.forall_intro_2
    (fun x y -> FStar.Classical.move_requires_2 lex_antisymmetric x y)
let lex_transitive_all () : Lemma (ensures (forall xs ys zs. lex_le xs ys /\ lex_le ys zs ==> lex_le xs zs)) =
  FStar.Classical.forall_intro_3
    (fun x y z -> FStar.Classical.move_requires_3 lex_transitive x y z)
let lex_total_all () : Lemma (ensures (forall xs ys. lex_le xs ys \/ lex_le ys xs)) =
  FStar.Classical.forall_intro_2 lex_total
let lex_first_two :
  ((forall xs. lex_le xs xs) /\
   (forall xs ys. lex_le xs ys /\ lex_le ys xs ==> xs == ys)) =
  FStar.Squash.join_squash (FStar.Classical.Sugar.and_intro
    (forall xs. lex_le xs xs)
    (fun _ -> forall xs ys. lex_le xs ys /\ lex_le ys xs ==> xs == ys)
    (fun () -> lex_reflexive_all (); ())
    (fun _ -> lex_antisymmetric_all (); ()))
let lex_first_three :
  (((forall xs. lex_le xs xs) /\
    (forall xs ys. lex_le xs ys /\ lex_le ys xs ==> xs == ys)) /\
   (forall xs ys zs. lex_le xs ys /\ lex_le ys zs ==> lex_le xs zs)) =
  FStar.Squash.join_squash (FStar.Classical.Sugar.and_intro
    ((forall xs. lex_le xs xs) /\
     (forall xs ys. lex_le xs ys /\ lex_le ys xs ==> xs == ys))
    (fun _ -> forall xs ys zs. lex_le xs ys /\ lex_le ys zs ==> lex_le xs zs)
    (fun () -> FStar.Squash.return_squash lex_first_two)
    (fun _ -> lex_transitive_all (); ()))
let lex_total_order : total_order #bytes lex_le =
  FStar.Squash.join_squash (FStar.Classical.Sugar.and_intro
    (((forall xs. lex_le xs xs) /\
      (forall xs ys. lex_le xs ys /\ lex_le ys xs ==> xs == ys)) /\
     (forall xs ys zs. lex_le xs ys /\ lex_le ys zs ==> lex_le xs zs))
    (fun _ -> forall xs ys. lex_le xs ys \/ lex_le ys xs)
    (fun () -> FStar.Squash.return_squash lex_first_three)
    (fun _ -> lex_total_all (); ()))

let compare_bytes (x y:bytes) : Tot int = if lex_le x y then -1 else 1
let cmp_rel (x y:bytes) : Tot bool = compare_bytes x y < 0
let cmp_reflexive (xs:bytes) : Lemma (ensures (cmp_rel xs xs)) =
  lex_reflexive xs
let cmp_antisymmetric (xs ys:bytes)
  : Lemma (requires cmp_rel xs ys /\ cmp_rel ys xs) (ensures xs == ys) =
  assert (lex_le xs ys);
  assert (lex_le ys xs);
  lex_antisymmetric xs ys
let cmp_transitive (xs ys zs:bytes)
  : Lemma (requires cmp_rel xs ys /\ cmp_rel ys zs) (ensures cmp_rel xs zs) =
  assert (lex_le xs ys);
  assert (lex_le ys zs);
  lex_transitive xs ys zs
let cmp_total (xs ys:bytes) : Lemma (ensures (cmp_rel xs ys \/ cmp_rel ys xs)) =
  lex_total xs ys
let cmp_reflexive_all () : Lemma (ensures (forall xs. cmp_rel xs xs)) =
  FStar.Classical.forall_intro cmp_reflexive
let cmp_antisymmetric_all () : Lemma (ensures (forall xs ys. cmp_rel xs ys /\ cmp_rel ys xs ==> xs == ys)) =
  FStar.Classical.forall_intro_2
    (fun x y -> FStar.Classical.move_requires_2 cmp_antisymmetric x y)
let cmp_transitive_all () : Lemma (ensures (forall xs ys zs. cmp_rel xs ys /\ cmp_rel ys zs ==> cmp_rel xs zs)) =
  FStar.Classical.forall_intro_3
    (fun x y z -> FStar.Classical.move_requires_3 cmp_transitive x y z)
let cmp_total_all () : Lemma (ensures (forall xs ys. cmp_rel xs ys \/ cmp_rel ys xs)) =
  FStar.Classical.forall_intro_2 cmp_total
let cmp_first_two :
  ((forall xs. cmp_rel xs xs) /\
   (forall xs ys. cmp_rel xs ys /\ cmp_rel ys xs ==> xs == ys)) =
  FStar.Squash.join_squash (FStar.Classical.Sugar.and_intro
    (forall xs. cmp_rel xs xs)
    (fun _ -> forall xs ys. cmp_rel xs ys /\ cmp_rel ys xs ==> xs == ys)
    (fun () -> cmp_reflexive_all (); ())
    (fun _ -> cmp_antisymmetric_all (); ()))
let cmp_first_three :
  (((forall xs. cmp_rel xs xs) /\
    (forall xs ys. cmp_rel xs ys /\ cmp_rel ys xs ==> xs == ys)) /\
   (forall xs ys zs. cmp_rel xs ys /\ cmp_rel ys zs ==> cmp_rel xs zs)) =
  FStar.Squash.join_squash (FStar.Classical.Sugar.and_intro
    ((forall xs. cmp_rel xs xs) /\
     (forall xs ys. cmp_rel xs ys /\ cmp_rel ys xs ==> xs == ys))
    (fun _ -> forall xs ys zs. cmp_rel xs ys /\ cmp_rel ys zs ==> cmp_rel xs zs)
    (fun () -> FStar.Squash.return_squash cmp_first_two)
    (fun _ -> cmp_transitive_all (); ()))
let cmp_total_order : total_order #bytes cmp_rel =
  FStar.Squash.join_squash (FStar.Classical.Sugar.and_intro
    (((forall xs. cmp_rel xs xs) /\
      (forall xs ys. cmp_rel xs ys /\ cmp_rel ys xs ==> xs == ys)) /\
     (forall xs ys zs. cmp_rel xs ys /\ cmp_rel ys zs ==> cmp_rel xs zs))
    (fun _ -> forall xs ys. cmp_rel xs ys \/ cmp_rel ys xs)
    (fun () -> FStar.Squash.return_squash cmp_first_three)
    (fun _ -> cmp_total_all (); ()))
let cmp_total_order_exact : total_order #bytes (bool_of_compare compare_bytes) = cmp_total_order
let sort_bytes (xs:list bytes) : Tot (list bytes) = sortWith compare_bytes xs
let sort_bytes_sorted (xs:list bytes) : Lemma
  (ensures (sorted (bool_of_compare compare_bytes) (sort_bytes xs))) =
  let order_evidence : total_order #bytes (bool_of_compare compare_bytes) = cmp_total_order_exact in
  sortWith_sorted #bytes compare_bytes xs
let sort_count_invariant (xs ys:list bytes)
  (h:(forall x. count x xs == count x ys)) : Lemma
  (ensures (forall x. count x (sort_bytes xs) == count x (sort_bytes ys))) =
  sortWith_permutation #bytes compare_bytes xs;
  sortWith_permutation #bytes compare_bytes ys
```

## Superseding result: local insertion sort

The manifest's first verified implementation used the `total_order`/`sortWith`
construction above. That proof path was rejected because its Classical/Squash
packaging reaches the admitted `elim_squash` helper. It was replaced with
structural insertion sort and pointwise count callbacks. The new scratch
prototype and integrated repository source verify sortedness, count
preservation, no-repeat preservation, sorted-permutation uniqueness,
permutation invariance, fixed points, and canonicalization idempotence. The
full eight-module result is recorded in the A03 run log.

Trust-tool correction: `--report_assumes error --cache_off` fails on
`Prims.admit` even for a trivial lemma; without `--cache_off` it passes both
the old Classical/Squash file and the constructive file. This flag is not
evidence for or against this specific dependency. The rejection above follows
from direct source/call-path inspection of the imported helper implementation.
See `stdlib_axiom_audit.md` for the full experiment and current token
representation decision.
