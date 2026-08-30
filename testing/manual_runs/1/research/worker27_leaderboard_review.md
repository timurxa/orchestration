# Worker 27 — finalist leaderboard review

## Status

**No profile is certified.** The retained evidence contains no independent
full-vector arbitrary-complex-input MPFR result at `N=65536`. Large-`N`
non-delta checks are selected-row checks; the full-vector checks are delta
controls. Therefore every leaderboard entry below is **provisional**, even
when its reported metrics pass.

## Recommended leaderboard

Times are warmed `dht_apply` medians from the one-thread Worker 15 sweep unless
noted. `plan_bytes` is accounted reusable plan storage, not peak RSS; it
excludes FFTW internals and caller buffers.

| use | profile `(terms,z0,ratio)` | `N=65536` timing / plan | strongest completed evidence | disposition |
|---|---|---:|---|---|
| Speed-first | `(10,30,4)` | `51.658 ms` / `74,849,368 B` | Worker 13: independent 400-bit MPFR, full small vectors plus every active band and selected rows through `N=65536`; worst reported target-row relative error `1.09e-14`. Worker 19: selected-row random/alternating/high-dynamic maximum `4.228e-15 / 8.391e-15` (L2/Linf), but unfinished adversarial cases. | **Strongest speed-supported profile; provisional.** |
| Balanced default | `(12,21,4)` | `58.871 ms` / `64,366,824 B` | Worker 7 residual-sign: full small-N worst `2.545e-14 / 2.665e-14`; `N=65536` selected-row worst `2.524e-14 / 2.628e-14`. Worker 19 common selected-row maximum `9.296e-15 / 1.622e-14`. | **Recommended cautious fallback; provisional.** |
| Margin-first | `(10,40,4)` | `57.041 ms` / `89,679,064 B` | Worker 7 residual-sign: full small-N `3.635e-15 / 4.964e-15`; high-N selected rows `3.119e-15 / 3.792e-15`. Worker 3 independently reports a similar pass. | **Best observed accuracy margin; provisional and memory-heavy.** |
| Fast but narrow | `(12,20.25,4)` | `53.14 ms` / `62,857,704 B` | Worker 7 residual-sign pass: high-N selected `6.923e-14 / 7.793e-14`; full small-N `6.121e-14 / 6.899e-14`. | **Do not promote:** only about `1.45x` L2 headroom at the selected large-N probe. |

Other positive screening survivors are `(12,24,4)` and `(8,48,4)` (Worker 7,
including residual-sign checks), but neither has a stronger speed/memory case
than the three leading choices. The Worker 21 direct-row band scheduler is the
fastest observed implementation variant: `18.562 ms` at 10 threads versus
`29.729 ms` for its control. It was tested in a temporary source copy, was not
integrated, and its accuracy harness emitted no metrics; treat that speed claim
as provisional optimization evidence, not a certified leaderboard result.

## Explicit exclusions and caveats

- `(12,18,4)` is rejected. Workers 7 and 10 reproduce residual-sign failure:
  full small-N normalized L2 is about `3.12–3.19e-13`, and the `N=65536`
  selected-row L2 is `3.237e-13`. `(12,20,4)` also fails the residual-sign
  gate. Lower-work `(8,32)`, `(8,34)`, `(8,40)`, and `(6,64)` are rejected;
  `(11,23)` has a selected target row above the `1e-12` Linf limit.
- Worker 19 stopped after `250.44 s` before chirp and residual-sign cases, so
  its three-profile ranking is explicitly incomplete. Its source hash also
  predates a later on-disk source change.
- Worker 20 passes timing-scope and setup/memory accounting, but fails the
  reproducibility/integrity gate: seeds and full input/output identities are
  not recorded, sample fields are mislabeled as checksums, and documented
  verify/benchmark profile selection is inconsistent. Worker 12 likewise finds
  that `research/archive.csv` stops at H1–H9 and does not archive finalist
  identities. The archive's H2 `validated_baseline` row is therefore not a
  current certification.
- Worker 22 finds the signs, normalization, partner-bin reconstruction, and
  product-safe partition mathematically sound; this does not establish
  binary64 end-to-end accuracy. Worker 23's API/UBSan and harness regression
  passes cover small dense cases, selected large rows, and delta controls, not
  the missing full arbitrary-vector `N=65536` gate.

**Recommendation:** retain `(10,30,4)` as the speed-first candidate and
`(12,21,4)` as the cautious default pending one frozen-source, explicitly
profiled full-vector MPFR gate. Do not label either “winner” or “validated”
until that run and self-identifying benchmark record are archived.
