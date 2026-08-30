# Worker 31 — accuracy-evidence wording audit

Date: 2026-08-28

## Bottom line

**No profile is certified for an arbitrary binary64 complex vector at
`N=65536`.** The retained evidence has three different scopes that must not be
merged:

1. full-vector MPFR comparisons at small `N`;
2. selected-row MPFR comparisons for non-delta large-`N` inputs; and
3. full-vector endpoint delta controls at large `N`.

The residual-sign tests are especially important because they deliberately
align the scalar asymptotic remainder. They reject several profiles that pass
the ordinary dense suite. A passing selected-row result, including a passing
residual-sign result, is screening evidence rather than an arbitrary-vector
`N=65536` acceptance certificate.

The current on-disk default observed during this audit is
`(terms, cutoff, ratio) = (10, 30, 4)`. Older reports describe `(11,23,4)` or
`(12,21,4)` as the default; those statements belong to earlier workspace
snapshots and must not be used to identify the current default.

## What the current harnesses actually test

### `bench/accuracy.c`

The current dense reference (`bench/accuracy.c:87-112`) evaluates every output
row and every input column with 256-bit MPFR `mpfr_j0`, 256-bit MPFR
accumulation, and final rounding to binary64. The main loop
(`bench/accuracy.c:289-307`) runs five deterministic complex input families at
`N=32,64,128,256,512` by default: 25 full-vector cases in total.

The large-`N` part is materially weaker than the dense part:

* `check_large_rows` (`bench/accuracy.c:221-259`) evaluates only the fixed
  nine-row set `{0,1,2,3,7,31,1024,32768,65535}` for the random input.
* It prints `max_row_rel`, not the required normalized L2 and scaled Linf,
  and accepts a maximum row-relative error of `1e-11` (`line 251`). This is a
  diagnostic, not the project gate of `1e-13` / `1e-12`.
* `check_delta_full` (`bench/accuracy.c:261-287`) does compare all output rows
  for `at=1` and `at=N-1`, but those are single-column controls. In the current
  source, the imaginary delta reference is formed as `-0.375 * ref[m].re`
  after the real MPFR value has been rounded (`lines 143-157`); describe this
  accurately as an MPFR-generated Bessel-column control, not as a general
  arbitrary-vector complex matvec.
* There is no residual-sign input in this harness.

The post-fix negative test documented by Worker 23 shows that an explicit
dense gate failure now returns nonzero. Do not repeat the older Worker 17
false-green finding as a current harness defect; the coverage limitation, not
failure propagation, is the remaining accuracy issue.

### `research/adversarial_k12.c`

The checked-in residual driver constructs signs from an MPFR asymptotic-minus-
`J0` residual (`lines 57-83`) and compares the complete output vector with a
256-bit MPFR reference (`lines 85-124`). Its main loop is only
`N=32,64,128,256,512` and defaults to `(12,18,4)` (`lines 126-152`). It has no
large-`N` path and does not exercise the current `(10,30,4)` default unless
explicit profile arguments are supplied. Its phase offset uses the binary64
`M_PI/4` constant inside the MPFR evaluator; this is suitable for a targeted
screening input, but it is not a substitute for a separately archived,
profile-general full acceptance driver.

The retained `worker10_k12_validation.c` and
`worker3_followup_adversarial.c` are stronger, profile-specific independent
drivers: they use MPFR accumulation for the full small vectors and selected
large rows, and explicitly label the large non-delta scope.

## Evidence ledger

Here `E2` means normalized L2 and `Einf` means the required scaled Linf,
`max(error)/max(reference)`. Both must satisfy `E2 <= 1e-13` and
`Einf <= 1e-12`.

### Full-vector small-`N` MPFR evidence

These results are valid full-vector gates at the stated small sizes. They do
not become a full-vector `N=65536` result by extrapolation.

| profile | full-vector result | defensible interpretation |
|---|---|---|
| Current/default `(10,30,4)` | The Worker 25 reproduction run reports all 25 ordinary dense MPFR cases through `N=512` passing. Worker 23 reports maxima `E2=5.5634e-15`, `Einf=1.8104e-14` for its post-fix run. | Ordinary dense small-`N` evidence only. Attribute the maxima to that reported build/run; do not call them a large-`N` certificate. |
| `(12,18,4)` | Worker 10 residual-sign full vectors fail at every tested `N=64,128,256,512`; at `N=64`, `E2=3.19267630336555019e-13`, `Einf=5.47311324551836609e-13`. | Reject the profile. The L2 failure alone is decisive. |
| `(8,32)`, `(8,34)`, `(8,40)`, `(6,64)` | Worker 3 reports full-vector residual-sign failures. Worst-small pairs are respectively `1.1623595668e-12/1.5213414457e-12`, `4.3768907790e-13/5.4021931677e-13`, `1.1677035488e-13/1.3068389906e-13`, and `2.0737016460e-12/2.8098534363e-12`. | Reject these profiles at the stated gate. |
| `(12,21,4)` | Worker 7 residual-sign full-small maximum: `E2=2.545e-14`, `Einf=2.665e-14`. | Passed the tested small adversarial screen, not certified at `N=65536`. |
| `(10,40,4)` | Worker 7 residual-sign full-small maximum: `3.635e-15/4.964e-15`; Worker 3 independently reports a comparable pass. | Strongest observed small-`N` residual margin, still only screening evidence. |
| `(12,20.25,4)` | Worker 7 full-small residual-sign maximum: `6.121e-14/6.899e-14`. | Passes the recorded small screen narrowly; do not promote on this margin. |

For `(12,18,4)`, the full-vector failure is reproduced by independent reports:
Worker 10 gives the exact `N=64` result above, while Worker 7 reports a small-
`N` worst normalized L2 of about `3.193e-13`. This is stronger evidence than
the ordinary dense passes and should be prominent in the final report.

### Selected-row large-`N` MPFR evidence

All non-delta large-`N` numbers in the retained reports are selected-row
metrics. They are useful for locating transition and block-boundary failures,
but they are not metrics over the full output vector.

The strongest completed screening numbers worth quoting are:

| profile | `N=65536` selected-row evidence | status |
|---|---|---|
| `(10,30,4)` | Worker 13 reports a residual-sign screening maximum of approximately `E2=1.05e-14`, `Einf=1.09e-14` across its completed full-small/selected-large checks. Worker 19's completed random/alternating/high-dynamic subset is lower at `4.227842977020306e-15 / 8.390958148569461e-15`. | Provisional only; no full arbitrary-vector large-`N` result. |
| `(12,21,4)` | Worker 7 residual-sign selected-row maximum `2.524e-14/2.628e-14`; Worker 19's completed common-input selected-row maximum is `9.295350566856474e-15/1.621670421464423e-14`. | Provisional only. |
| `(10,40,4)` | Worker 7 residual-sign selected-row maximum `3.119e-15/3.792e-15`; Worker 3 independently reports `1.3317280913e-15/1.3704642939e-15` for its selected set. | Best observed screening margin, not certification. |
| `(12,24,4)` | Worker 7 residual-sign selected-row maximum `3.292e-14/5.840e-14`. | Screening pass only. |
| `(8,48,4)` | Worker 7 residual-sign selected-row maximum `3.500e-14/3.233e-14`; Worker 3 reports `2.9257650070e-14/3.0745548930e-14` on its selected set. | Screening pass only. |
| `(12,18,4)` | Worker 10 reports `3.75294118699974419e-13/5.18535214979909280e-13` on selected `N=65536` rows; Worker 7 independently reports `3.237e-13` L2 on a different 23-row set. | Reject; this is also a large selected-row failure, but not a full-vector `N=65536` result. |

Do not relabel a target-row relative error as the project scaled Linf. For
example, Worker 13 reports a `(11,23)` target-row relative error of
`1.114e-12`; that exceeds the target-row `1e-12` comparison, but its selected-
row aggregate uses the maximum reference over the selected set. It is a
strong no-margin warning, not by itself a correctly computed full-vector
scaled-Linf failure.

Worker 19 is a useful independent 400-bit checker, but its run completed only
the `random`, `alternating`, and `high_dynamic` common cases for its three
profiles. It stopped after 250.44 seconds before `chirp` and all residual-sign
cases. Its report also records that the source hash predates a later on-disk
source change. Use its numbers as incomplete historical selected-row evidence,
not as validation of the final source.

### Full-vector delta controls

The delta controls compare all `65,536` output rows, but they test one input
column at a time and therefore cannot establish accuracy for arbitrary
complex input. The documented current-harness reports give the following
conservative values at `N=65536`:

| input | normalized L2 | scaled Linf | wording |
|---|---:|---:|---|
| `x[1]=1-0.375i` | `1.6267e-16` | `2.7990e-16` | full-vector endpoint control passed |
| `x[N-1]=1-0.375i` | `1.1394e-15` in the later Worker 25 report | not retained in that report | full-vector endpoint control passed |

Related earlier runs retain the pair `1.1401e-15/7.9047e-16` for `at=N-1`,
but they used older profile/source snapshots. Do not present that pair as a
same-run current-default result; the conservative cross-report statement is
that the control passed and its reported normalized L2 was about `1.14e-15`.

Worker 10/7 independently report the rejected `(12,18,4)` profile's full delta
controls as approximately `1.635e-16/2.776e-16` at `n=1` and
`3.188e-15/3.908e-15` at `n=N-1`. These are profile/source-specific control
results and must not be mixed with the current-default figures.

The Worker 16 numbers (`dense 4.4139e-14/4.8016e-14`, selected-row
`4.3026e-14`, delta `2.3187e-14/2.8431e-14`) belong to a research-only
batched-FFT prototype. They are not production accuracy results and should
not be transferred to `src/dht_asym.c`.

## Interrupted and stale evidence

The following records must remain visibly incomplete:

* **Worker 19:** interrupted before chirp and residual-sign cases; no profile
  is certified from that run.
* **Worker 13:** stopped during the `(12,22)` large-`N` sweep; some candidate
  profiles and large checks were never completed. Its `(10,30)` recommendation
  is a screening recommendation.
* **Worker 26:** the requested post-scheduling current-source `(10,30,4)`
  residual run was interrupted before any case completed. It produced no
  stdout, exit status, metrics, or byte comparison; the optional `(12,21,4)`
  run was not started. This is no evidence for either pass or fail.
* **Worker 24:** `INCOMPLETE_STALE_SNAPSHOT` describes an older 11-data-row
  `bench/results.csv` snapshot. A later on-disk CSV has finalist rows, but
  timing CSV contents do not cure the missing full arbitrary-vector MPFR gate.
* **Worker 7:** its independent residual driver and CSV were kept in
  `/private/tmp`, not archived under `research/`; treat the report as
  corroborative but not repository-replayable.

## Copy-ready final-report wording

Use this as the main accuracy paragraph:

> Against an independent MPFR reference, the implementation passes the
> complete-vector dense tests exercised at `N=32,64,128,256,512` for the five
> deterministic input families. At `N=65536`, the retained non-delta evidence
> compares selected output rows only; the complete-vector results are limited
> to the two endpoint delta controls. The repository's large-row check is a
> diagnostic over nine random-input rows with a `1e-11` maximum row-relative
> threshold, not the required normalized-L2/scaled-Linf acceptance gate.
> Therefore no profile is certified for an arbitrary binary64 complex input
> vector at `N=65536`.

Use this to document the decisive rejection:

> The `(terms,cutoff,ratio)=(12,18,4)` profile is rejected by an independent
> MPFR residual-sign construction. Its full-vector `N=64` error is
> `E2=3.19267630336555019e-13` and `Einf=5.47311324551836609e-13`, failing the
> normalized-L2 limit. At `N=65536`, the same construction reports
> `E2=3.75294118699974419e-13` and `Einf=5.18535214979909280e-13` on the
> selected rows; this confirms the failure mode but is not a full-vector
> large-`N` result.

Use this for the remaining candidates:

> Profiles `(10,30,4)`, `(12,21,4)`, `(10,40,4)`, `(12,24,4)`, and `(8,48,4)`
> passed the completed screening cases reported here, with the numerical
> margins listed by scope. Those results are provisional: the non-delta
> `N=65536` checks are row-selected, and the current-source post-scheduling
> `(10,30,4)` residual run was interrupted before producing metrics. They must
> not be labeled certified or universally accurate without a frozen-source
> full-vector arbitrary-input MPFR comparison.

## Wording to avoid

Do not write any of the following:

* “The implementation passes the `N=65536` MPFR accuracy gate.”
* “The random/dynamic/residual-sign `N=65536` error is `X`” without saying
  “selected rows.”
* “Full `N=65536` accuracy was verified” when the inputs are only deltas.
* “The current default is certified” based on the source comment, dense small-
  `N` passes, or the delta controls.
* “`scaled Linf`” for `max_row_rel`, a target-row relative error, or any metric
  using a different denominator.
* “Worker 19 completed the large-N adversarial run” or “Worker 26 confirmed
  the post-scheduling result.” Both statements are false.

The strongest defensible final status is therefore: **small-vector dense and
residual-sign behavior is measured, endpoint delta columns pass, several
profiles are promising screening candidates, but arbitrary-vector accuracy at
the primary `N=65536` size remains uncertified.**
