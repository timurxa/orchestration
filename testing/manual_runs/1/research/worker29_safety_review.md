# Worker 29 — final C safety review

## Recommendation

**FAIL.** The current `src/dht_asym.c` is not yet safe for all accepted
constructor inputs. Do not promote it until Findings 1 and 2 are fixed and
the FFTW lifecycle decision in Finding 3 is made explicit.

## Actionable findings

1. **Unchecked allocation-byte multiplication can wrap (P1).**
   `build_weights_and_scales()` checks `terms*n` but not the subsequent
   `nk * sizeof(double)` allocations, nor `terms * sizeof(double)` for
   `coeff` (lines 227–229). The scratch allocation repeats the unchecked
   `nk * sizeof(fftw_complex)` product (line 294). Accepted profile limits
   allow `terms*n` to be representable while either byte product is not; a
   wrapped non-NULL allocation can then be overrun by the fill loops. The
   row-array `calloc` sizes (lines 283–284), `memset` size (line 406), and
   all aggregate arithmetic in `dht_plan_bytes()` (lines 488–493) have the
   same missing checked-byte/checked-add discipline. Add checked multiply
   and checked addition helpers, use them for every allocation and reported
   byte total, and reject before allocating. Validate `n` against
   `INT_MAX`, the type actually used in the FFTW `int` argument.

2. **A finite extreme cutoff still reaches an out-of-range float-to-integer
   conversion (P1).** `create_profile()` rejects non-finite `cutoff`, but
   `add_asym_block()` casts `ceil(threshold / lo)` to `size_t` before checking
   it against `n` (line 416). A finite value such as `DBL_MAX` overflows the
   intermediate `cutoff*n` to `+Inf`; the accepted plan then reaches the
   cast during `dht_apply`, which is undefined behavior when the value is not
   representable. Apply the same pre-cast clamp used by
   `build_direct_region()` (or a shared safe threshold-to-index helper),
   testing the floating value against `n` before converting it.

3. **FFTW thread initialization failure and cleanup are not handled (P2).**
   The return value of `fftw_init_threads()` is ignored (line 299), and no
   `fftw_cleanup_threads()` is performed after the last plan is destroyed.
   Check initialization success and unwind on failure. Because FFTW thread
   state is process-global, use a one-time/refcounted lifecycle and clean it
   only after all plans are gone, or explicitly document and enforce a
   process-lifetime initialization policy.

4. **Non-finite tolerance values remain accepted (P2 API-safety gap).**
   `tol` is stored and returned without validation; `dht_plan_create()` and
   the profile constructors accept `NaN` and infinities. The current code
   falls back to a profile and does not immediately exhibit memory UB, but
   this contradicts a finite-parameter contract and makes the tolerance
   metadata false. Reject `!isfinite(tol)` (and document the allowed domain)
   before constructing a plan.

## Completed evidence

- Existing post-fix API/UBSan evidence (`research/worker23_postfix_api.md`)
  confirms `N=1`, null handling, invalid non-finite cutoffs, oversized
  `terms`/`threads`/`N`, repeated application, and the documented small-size
  checks passed. Those tests do not cover the finite-extreme-cutoff cast or
  wrapped allocation-byte products above.
- The dispatch schedule has the necessary ratio and loop-progress checks for
  the accepted `n`/`block_ratio` domain; no separate reproducible schedule
  bounds defect was found.
- Plan destruction orders `fftw_destroy_plan()` before `fftw_free()` and frees
  all explicit arrays, including partial-construction failures. The remaining
  lifecycle issue is FFTW's global thread state, not an observed per-plan
  free-order error.
