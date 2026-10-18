# S2-11 adapter, identity, codec, and resource refinement audit

**Result: PASS after two consistency fixes.** This review checked concrete P13
coverage of P0, P7, optional P9, P10, and P14.

P13 now requires the concrete loader to resolve each journal-pinned identity
to the same complete canonical manifest and exact package implementation
across restart. Compiled/interpreted LocalWork and GenerateWork, the
`validate_reply` function, and exact-index codecs must refine their pinned F*
semantics. Each `CallOutcome` uses the pinned validator at the reconstructed
input and projects the canonical event fields from the same P7 receipt via
`persist_x`. Run IDs are unique in the shared adapter-key namespace; if an
identity uses a digest, its collision/uniqueness premise is explicit.

The concrete adapter must preserve exact request/resume binding and key for
each committed intent; overlapping retries across restarts refine P7's stable
terminal tuple and one logical effect/reconciliation law. Distinct keys may
remain nondeterministic. Any dependency on remote deduplication, status lookup,
or effect semantics is an explicit proof-bearing environment contract. P14
response/retry fairness remains separate. When P9 is supplied, P13 also proves
typed publication, immutable object/version identity, and same-logical-object
resolution after restart; absent P9, no physical resource guarantee is
claimed.

The initial P13 dependency range `P0-P12` accidentally included P9 as
mandatory. Both the theorem table and P13 conclusion now list P9 only when
persistent resource identity is claimed. Follow-up review identified that
the concrete `validate_reply` implementation was not explicitly named; §6
now covers extraction refinement and binds `CallOutcome` to that exact
validator and receipt projection.

Reviewer: `/root/s211_adapter_identity_refinement`. No source or F* proof was
performed.
