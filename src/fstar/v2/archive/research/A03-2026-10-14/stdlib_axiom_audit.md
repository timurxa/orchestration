# A03 proof trust and standard-library audit

**Date:** 2026-10-14
**Status:** constructive sort, opaque-token migration, and scoped source/call-
path review complete.

## Rejected initial sorting path

The source snapshot in commit `38f8e62` used `FStar.Classical.forall_intro*`,
`move_requires*`, and `FStar.Squash.join_squash` to construct the first-class
`total_order` required by `sortWith_sorted`. Inspection of the installed
F* 2026.03.24 sources found this helper path:

```text
ManifestCore total_order construction
  -> FStar.Classical / FStar.Squash proof packaging
  -> FStar.IndefiniteDescription.elim_squash
  -> axiom whose implementation uses admit ()
```

That imported helper was not acceptable for the project theorem path. The
proof was replaced by a local structurally recursive insertion sort, with
local sortedness, count-preservation, uniqueness, permutation, and fixed-point
proofs. The replacement preserves the same canonical order and rejection
behavior; it does not deduplicate rows.

The integrated `WorkflowV2.ManifestCore` has no source references to
`FStar.Classical`, `FStar.Squash`, `FStar.IndefiniteDescription`,
`total_order`, or `sortWith`; it has no local `assume`, `admit`, or
`assume_val`. Its insertion-sort lemmas use `bytes_lex_total` and
`bytes_lex_transitive` directly. The independent sort audit confirmed that
count preservation holds even with duplicates, while canonical uniqueness and
fixed-point results correctly require no-repeats, established before sorting
by tagged identity uniqueness.

## `--report_assumes` experiments

The first audit incorrectly treated this command as evidence of the specific
Classical/Squash dependency:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 --report_assumes error \
  --include src/fstar/v2/src --include /tmp/fstar-v2-a03-strict \
  --odir /tmp/fstar-v2-a03-strict \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst
```

It fails at `Prims.fst:663` because cache-off mode rechecks F*'s own
`Prims.admit` declaration. A minimal module containing only
`let trivial : Lemma (1 + 1 = 2) = ()` fails identically. With the normal F*
caches, strict reporting passes both the constructive source and the
preserved old Classical/Squash snapshot. Therefore this option is not a
transitive-trust oracle: it neither isolates project dependencies in cache-off
mode nor reports all imported-helper dependencies in cached mode. The old
sorting route was rejected by direct source/call-path inspection, not by this
flag. Record its output as a diagnostic only.

## Primitive text boundary

The initial Kernel codec also encoded identity names through `FStar.String`
and `FStar.Char`. Its proof path used the standard-library declarations
`FStar.Char.char_of_u32_of_char` and
`FStar.String.string_of_list_of_string`, which are interface-level primitive
laws rather than locally checked lemma bodies. To keep A03 identity codec
roundtrips constructive and avoid adding these library contracts to the
project theorem path, the active DAG now uses opaque `identity_token = bytes`
values for identities and manifest labels. The A03 migration removes `FStar.String` and
`FStar.Char` imports and proves the framed-sequence roundtrip from Kernel's
own list decoder. The abstract system makes no UTF-8 or host-text claim; a
host may supply display-name conversion at the later refinement boundary.

This representation choice does not prove or depend on a Unicode mapping.
Switching to a refined Unicode scalar list is an alternative, but it would
impose a text meaning not present in the normative spec and require an
additional host text-refinement theorem. Opaque tokens are the smaller formal
boundary. In the current kernel, `bytes` is modeled as `list nat`; an eventual
octet-level implementation must supply its concrete refinement separately.

## Verification evidence

Before the token migration, the constructive insertion sort passed the full
eight-module build:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m \
  make -C src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a03-constructive
```

F* 2026.03.24, Z3 4.13.3, OCaml 5.3.0. All eight modules verified and all
VCs were discharged. Warning 328 (unused recursive `GraphCodec` helper)
remains; warning 271 no longer appears after the token migration. The token
codec also passed in scratch copies with `--report_assumes error` and normal
caches. The integrated full build now passes:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m \
  make -C src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a03-integrated
```

This ran with F* 2026.03.24/Z3 4.13.3/OCaml 5.3.0; all eight configured
modules and all VCs passed. A separate cached `--report_assumes error` run on
Kernel and ManifestCore also passed. The full project source audit finds no
project-owned `assume`, `admit`, or unchecked declaration in Kernel,
ManifestCore, or GraphCodec, and no Classical/Squash/IndefiniteDescription
path in the manifest proof. The full build uses `--cache_off`; strict
`--report_assumes error --cache_off` is not a viable trust oracle because it
fails on F*'s own `Prims.admit`, even for a minimal lemma.

The imported-list-helper audit inspected the actual helper bodies in the
installed F* 2026.03.24 source. `FStar.List.Tot.Base` defines the used
`length`, `count`, `mem`, `noRepeats`, `hd`, append, and `bool_of_compare`
functions structurally (`FStar.List.Tot.Base.fst:36-40, 71-76, 96-102,
117-124, 235-242, 405-412, 511-520`). The used Properties helpers
`mem_count`, `noRepeats_nil`, `noRepeats_cons`, and `sorted` have corresponding
checked F* bodies (`FStar.List.Tot.Properties.fst:96-104, 430-433, 455-469`)
for their `.fsti` declarations. Scoped source search found no `assume`,
`admit`, `assume_val`, `unsafe_coerce`, or `magic` in those definitions.
Unrelated admission-bearing declarations elsewhere in the F* standard library
are not used by this A03 path. The F* checker, logical/core prelude, and SMT
remain the declared trusted base; this is not a claim that legacy
`WorkflowV2.Graph` or `ChainProof` is admission-free.

The no-escape-hatch acceptance rule is source scoped: no project-owned
`assume`/`admit`, no unchecked application declaration, and no use of a
helper theorem whose implementation relies on admission. The F* checker,
logical prelude, and SMT solver are the explicit trusted base; the source audit
must name any other primitive contracts that the theorem path uses.
