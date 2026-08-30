# Worker 17 — API and edge-case audit

Date: 2026-08-28

Status: **FAIL**. Normal small-N behavior and documented API preconditions are
mostly coherent, but the current snapshot has an unchecked profile-input UB,
an undocumented `N=1` rejection, and a verification harness that can report
failure while exiting successfully.

No production files were edited by this worker.

## Commands and observed results

- `make all`: completed.
- `make verify`: exit 0. With the current default `(terms=12, cutoff=21,
  ratio=4)`, all five dense complex cases at `N=32,64,128,256,512` printed
  `PASS`; selected large rows and both full delta controls at `N=65536` also
  printed pass/diagnostic-pass. This is not a full arbitrary-vector
  `N=65536` certification.
- The custom current-source edge harness covered
  `N={1,2,3,4,5,7,8,15,16,31,32,33,63,64,65,127,128,129}` with arbitrary
  complex input, zero input, plan reuse, metadata, null calls, and profile
  validation. All `N>=2` cases returned `0` and matched a dense binary64
  `j0` reference; zero output and repeated application were stable. `N=1`
  returned `NULL`.
- `build/dht_benchmark 65 1 0 1e-13 T` for `T=0,1,2,8`: all returned 0 and
  produced the identical checksum
  `(-1.408452040996834,-0.26672095953873354)`. `terms`/`threads` above
  `INT_MAX` and `N>INT32_MAX` returned `NULL`. C++ header/linkage smoke test
  also passed.
- `build/dht_accuracy 32 1e-13 1 1 1 32 2; echo $?`: every dense case
  printed `FAIL` (for example `rel_l2=1.4959e-02`), but the final exit was
  `0`.
- UBSan build/run of an explicit `cutoff=INFINITY` profile:
  `dht_plan_create_profile_ex(5,1e-13,1,INFINITY,1,2)` returned non-NULL,
  then `dht_apply` triggered
  `src/dht_asym.c:329:21: runtime error: inf is outside the range of
  representable values of type 'unsigned long'`.

## Findings and minimal recommendations

1. **Profile-input UB (current defect).** `cutoff=INFINITY` is accepted by
   `create_profile`, but `add_asym_block` casts `ceil(threshold/lo)` to
   `size_t` before checking whether it is at least `n`. Reject non-finite or
   overflowing cutoffs, or perform the `>= n` check before the cast.

2. **`N=1` API gap.** `dht_plan_create(1,...)` and the profile constructors
   return `NULL`, although the documented operator is well-defined for
   `N=1` (`y[0]=x[0]`). Either add a one-point special case or state an
   explicit `N>=2` precondition in `dht.h`, `README.md`, and the harness.

3. **False-green accuracy target.** `bench/accuracy.c` prints metric
   `PASS`/`FAIL` but `check_case`, `check_large_rows`, and `check_delta_full`
   return success after printing; `main` therefore does not propagate metric
   failures. Make the checks return the gate result and make `main` fail on
   any `L2 > 1e-13` or scaled-Linf `>1e-12`.

4. **Benchmark recipe mismatch.** Current source/README/`run_winner.sh`
   identify `(12,21,4)`, while `Makefile:31` runs explicit `(10,30,4)`;
   `make benchmark` consequently reports `terms=10 z0=30.0`. Align the
   recipe or label it as an intentional alternate profile.

5. **Tolerance-domain ambiguity.** `dht_plan_create` accepts `tol=0`, a
   negative value, `NaN`, and `Inf`, stores that value in metadata, and uses
   the default `(12,21)` profile. Reject invalid tolerances or document this
   fallback; otherwise `dht_tolerance()` is potentially misleading.

Normal null handling is coherent: `dht_apply` returns `-1` for null plan/input/output,
null metadata getters return the documented sentinel-like values, and
`dht_plan_destroy(NULL)` is safe. The current header explicitly disallows
overlapping input/output and concurrent use of one plan, so those are caller
preconditions rather than unresolved API defects. `dht_plan_bytes()` was
stable for tested plans, but is accounted reusable storage only; it excludes
FFTW internal allocations and caller buffers.

The workspace was modified concurrently during this bounded audit. Findings
above refer to the final source/header state observed after the last rebuild;
freeze the tree before applying fixes or quoting final accuracy/benchmark
results.
