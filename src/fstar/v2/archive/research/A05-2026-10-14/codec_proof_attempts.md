# A05 codec proof attempts

## Current source

`WorkflowV2.SchemaCodec.fst` remains the committed concatenated-child format.
Its encoders/parsers cover every current AST constructor, but only sample
roundtrips and accepted-byte canonicality are proved. No generic AST roundtrip,
injectivity, or completeness result is established in source.

## Framed-child scratch attempt

The scratch alternative length-frames every recursive AST child and each
argument value. This makes child boundaries explicit and appears to simplify
the structural decoder theorem. It is not integrated and has not established
general codec laws.

The worker's bisection with F* 2026.03.24 and
`--cache_off --warn_error @285` found:

- The framed module through its list-parser equation helper verifies.
- Adding `dec_schema_value_fuel_equation`, which states the recursive parser's
  one-step equation, causes F* itself to crash with
  `Failure("Parse error: </labels> not found")` in the flat dotted module
  file `/tmp/a05stable/WorkflowV2.SchemaCodecFramed.fst`.
- A module-shaped path was initially claimed to verify but did not load the
  module matching its declared dotted name. That result is invalid and is
  withdrawn.
- Rewriting the equation proof body to split on `fuel` avoids the internal
  crash but leaves its postcondition unproved. The generic roundtrip proof
  group is therefore not verified.

The worker later verified two narrower results against a clean flat module:

- the framed codec definitions and local child/int/pair proofs through line
  462 verify with cache disabled;
- a fixed-fuel `SchemaRoot` suffix roundtrip verifies.

These do not establish symbolic recursive fuel behavior, all constructors,
predicate/type syntax, or list recursion. They do not unblock integration.

## Relational grammar alternative

`/tmp/A05SchemaValueParseGrammar.fst` verifies a mutual suffix-parse relation
over the actual Kernel AST: all 13 schema-value constructors, value lists,
all 4 predicate constructors, and all 12 type constructors. It indexes each
parse by the exact unread suffix. Cache-off command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src /tmp/A05SchemaValueParseGrammar.fst
```

This relation gives structural induction over the AST and avoids unfolding a
recursive fuel parser in the induction theorem. It is not yet connected to
the executable codec. Still required: prove encoder output belongs to the
relation, prove relation determinism, and prove executable decoder soundness
and completeness with respect to the relation (including the argument-list
fuel/count helpers). Therefore it does not yet prove generic roundtrip,
injectivity, or canonical decoder behavior. `/tmp/A05CodecDirect.fst` also
confirms that a direct roundtrip lemma over the current fuel parser still
fails at recursive unfolding/length reasoning. Treat this as the leading
proof route, not integrated or complete evidence.

This is a proof-engineering blocker, not an irreducible contract ambiguity.
Do not weaken the codec theorem or accept a stale/partially loaded F* result.
Continue by testing formulations that avoid a standalone recursive-equation
lemma, or a structural parser whose termination and induction principles line
up directly. Any accepted format still needs all-constructor suffix roundtrip,
injectivity, malformed/trailing rejection, and accepted-byte canonicality.

## Complete framed-codec proof — 2026-10-14

A fresh proof route in `/tmp/A05full/WorkflowV2/SchemaCodecFramed.fst` now
discharges all codec laws for the complete current Kernel schema AST. It uses
structural AST depth as recursive fuel and prefixes each recursive child and
each argument with `enc_seq` framing. The wire format preserves the existing
tags and scalar encodings but is not byte-compatible with the committed flat
concatenation format.

Verified claims include:

- value roundtrip for all 13 constructors and recursive value lists;
- predicate roundtrip for all 4 constructors;
- type roundtrip for all 12 constructors;
- public complete-input decode roundtrip and encoder injectivity for all
  three AST sorts;
- rejection of trailing data and non-image malformed inputs;
- accepted-byte canonicality: every accepted byte sequence equals the
  encoding of the decoded AST.

Exact command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp/A05full \
  /tmp/A05full/WorkflowV2/SchemaCodecFramed.fst
```

Result: all verification conditions discharged successfully (one warning
originates in `FStar.UInt`). The prototype has no `assume` or `admit` and does
not edit repository source. The older framed attempt described above remains
accurately recorded as a failed proof route; this is a new proof formulation,
not a correction of that invalid module-path result.

At this point in the exploration, framing raised a compatibility question:
the manifest has a resolver-language version slot, but the system does not yet
bind that slot to an encoding migration/legacy-recovery policy. The question
was resolved by proving the existing unframed decoder directly, so framing is
not installed under the existing resolver identity. The adopted choice is
recorded below.

## Existing unframed codec proof — 2026-10-14

The compatibility-preserving route is now verified in
`/tmp/A05unframed/WorkflowV2/SchemaCodecUnframedTry.fst`. It is a copy of the
existing `WorkflowV2.SchemaCodec.fst` with only its module name changed, plus
proof lemmas; the encoders and parsers are unchanged.

Cache-off command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp/A05unframed \
  /tmp/A05unframed/WorkflowV2/SchemaCodecUnframedTry.fst
```

All verification conditions discharge. The proof covers suffix roundtrip and
public `decode(encode x) = Some x` for all 13 value constructors, all 4
predicate constructors and all 12 type constructors, including recursive
value lists; encoder injectivity for all three sorts; trailing-suffix
rejection; pointwise non-image rejection; and accepted-byte canonicality.
Structural AST depth/fuel bounds and the existing parser's recursive cases
are proved directly; no relation-to-parser bridge is needed. No `admit` or
`assume` occurs. The proof uses the same Kernel primitive/string trust
boundary as the current codec.

**Provisional design preference at this point:** keep unframed bytes if a
configured-source proof can be completed. The integration audit below showed
that the scratch proof route is not yet usable in the configured flat module;
no codec-format or proof-integration decision is complete. The framed result
remains a comparison artifact because it needs a resolver-version/recovery
policy.

## Configured-source integration audit — 2026-10-14

The preceding scratch proof result is valid as a standalone verifier result,
but its claim that integration is straightforward was premature. I copied the
proof body into the canonical source and ran the configured full verifier. It
failed in `uvalues_count_bound` with F* Error 19 (incomplete quantifiers). A
count-lemma refactor and generic/specialized list roundtrip lemmas moved the
failure to later recursive-list VCs but did not discharge them in the flat
dotted-module path. Raising fuel/rlimit did not fix the issue.

The nested-path control is not a valid integration result. F* resolves the
file by basename in that layout and emits an implicit-namespace warning; a
consumer importing `WorkflowV2.SchemaCodec` fails with `No modules in
namespace WorkflowV2.SchemaCodec`. A renamed nested scratch file has the same
module-resolution issue. The scratch body can check standalone, but it is not
proved as the configured project module. Flat dotted paths preserve imports
and fail on the real recursive-list VC. The source proof block
was removed after confirming the configured baseline again passes all eleven
modules. The current `SchemaCodec.fst` therefore still has checked examples,
not generic all-constructor roundtrip/injectivity proofs.

Exact baseline restoration command:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 \
  verify BUILD_DIR=/tmp/fstar-v2-a05-restored-baseline
```

Result: exit 0; all eleven modules verified and all VCs discharged under
F* 2026.03.24 / Z3 4.13.3 / OCaml 5.3.0. This is a passing partial-source
baseline only; it does not discharge the codec law acceptance. Investigate a
source-layout-compatible proof decomposition or another executable-decoder
proof route before claiming codec integration. Keep the wire-format choice
unframed only as a current design preference; framing/migration remains an
alternative if it materially simplifies the verified integration.

## First-order parser refactor — 2026-10-14

A scratch refactor replaces the higher-order `parse_value` callback with a
mutually recursive first-order value/argument-list parser. Its parser
implementations typecheck and verify in the configured module shape; the
unframed encoder is unchanged. It demonstrates that the callback itself is
not essential to the public codec. The generic encoder/decoder theorem is
still open: the direct parser's recursive equations are opaque to the
roundtrip induction, and broad unfolding produced incomplete-quantifier VCs.

A second scratch at `/tmp/A05firstorder` factors fuel wrappers from
constructor dispatch and reaches the two generic value/list roundtrip VCs
without changing the tracked source. Small base and dispatch equations verify;
app constructor/index-call composition remains the proof boundary. A helper
route should expose tag-specific step equations and require the exact list
roundtrip fact, then compose it with the wrapper equation. Parser fuel is
currently provisioned as `8 * length(input) + 8`; this is a scratch bound,
not a source/API decision. Establish its adequacy formally, or derive a
smaller bound, before integration. Do not credit scratch parser checks as
A05 codec laws.


## Generic value-codec proof in configured module shape — 2026-10-14

`/tmp/A05StepEq/WorkflowV2.SchemaCodec.fst` contains a callback-free, mutually
recursive value/list parser and a generic theorem covering every
`schema_value_expr` constructor. It proves suffix-preserving parse of each
encoded value and argument list, then public `decode_schema_value`
roundtrip. Constructor and index-call branches use explicit append
associativity and the exact recursive argument-list result. The parser uses
input-derived fuel; the scratch proves the value AST measure fits that budget.

Exact cache-off command from the repository root:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp/A05StepEq \
  --odir /tmp/A05StepEq/reverify \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  /tmp/A05StepEq/WorkflowV2.SchemaCodec.fst
```

Result: exit 0; both `WorkflowV2.Kernel` and the flat dotted-path
`WorkflowV2.SchemaCodec` verified, all VCs discharged. F* emitted warning 349
for one proof split that succeeds only after localization. This validates the
proof in the project module shape, unlike the earlier nested-path experiment,
but it remains a `/tmp` scratch result. The tracked source is unchanged.
The same scratch now also proves predicate and type suffix/public roundtrips,
all three encoder-injectivity theorems, and rejection of a nonempty suffix by
each public decoder. The cache-off `--split_queries always` re-verification
passed against the repository Kernel and flat dotted module. Source
integration and the full eleven-module verification after integration remain
open.


## Source integration and full configured proof — 2026-10-14

The verified callback-free parser and codec laws are now integrated in
`src/WorkflowV2.SchemaCodec.fst`. Existing encoder clauses, unframed wire
tags, and public `enc_*`, `dec_*`, and `decode_*` signatures are preserved.
The low-level fuel interprets parser transitions differently, but a source
search found no in-repository callers relying on its old budget. The parser
uses `8 * length(input) + 8`; checked structural bounds prove sufficient fuel
for every encoded Value/Predicate/Type AST. The old argument-count versus
payload-length early guard is removed; malformed inputs remain bounded by
fuel and public canonical re-encoding/full-input checks.

Full configured project command:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 \
  verify BUILD_DIR=/tmp/fstar-v2-a05-codec-integrated \
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'
```

Result: exit 0; all eleven configured modules verified and all VCs discharged
under F* 2026.03.24 / Z3 4.13.3. Only existing warning 328 in
`GraphCodec.nodes_decode_encoding` remains. The changed codec contains no
`assume` or `admit`; `git diff --check` passes. This closes A05's codec
subtask only. Typed denotation, exact package adequacy, semantic substitution,
and full-prefix `LegalEnv` remain required.

Source and synchronized evidence commit: `115fd0bf057f403c32ceeeba57c615b1385de381`.
