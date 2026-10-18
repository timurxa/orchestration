# Final API review delta

Scope: revised design §§5–6 and static-analysis example §10 only. Signatures marked semantic F* notation; no compile, source edit, or test performed.

## Findings

- **No blocker:** `Work i o`, `Verified`, `it`, `fan`, `then_keep`, and `keep_input` signatures compose. `then_keep` result family retains first result; context supplies original input and proof-bearing intermediate. `it : Work i (fun _ -> i)` correctly returns an `i` value. §10 prime composition matches this family.
- **No blocker:** accepted output persistence has an indexed codec and requires decoder soundness/rechecking. Tagged terminal `OpOutcome` wire, accepted-branch codec, rejection/failure codecs, and explicit restore representation are covered in §6.182. Minor proof obligation: bridge accepted codec's refinement `{y:o x | p x y}` to constructor payload `(y:o x & p x y)` by explicit conversion or choose one canonical representation.
- **No blocker:** `Unknown` is correctly a durable attempt/run-status projection, not `OpOutcome`; workflow suspends at that occurrence. Only terminal `Accepted`, `Rejected`, or definite `Failed` enters result family. Reconciliation appends evidence; `Rejected` does not imply non-application. §§6.178–182 are type-consistent on this point.

## Remaining blocker: static-analysis provenance

§10's `ParseResult s r` indexes parser result by raw outcome, but `Parsed` constructor only requires `WellFormed s p` (§10.422–424). It does not prove `p` came from `r`'s accepted report bytes. Since `RawResult` includes `Rejected` and `Failed`, type also permits `Parsed` for those cases. Add a relation such as `Parses (accepted_report r) p`, with constructors possible only when `r = Accepted ...`; retain explicit parse-rejected/failed cases for other inputs.

`CheckedResult s a` likewise has unconstrained `Unverified : ParsedFindings -> CheckedResult s a` (§10.427–431), so it can claim parsed/unverified findings for any `a`, including parse failure. Index the constructor by evidence that `a` contains successful parse, or add a `HasParsed a findings` witness. Sound findings remain independently safe if `Sound s f` is proved, but provenance and failure propagation still need explicit typing.

These are the only concrete blockers found in requested sections. After tying parsed and unverified outputs to successful raw/parser evidence, no remaining type, persistence-codec, composition, or `Unknown` consistency blocker identified.
