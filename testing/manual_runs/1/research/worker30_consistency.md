# Worker 30 — consistency audit

## Discrepancies and exact corrections

1. **README accuracy command selects the wrong profile.** `README.md:24`
   invokes `(terms,z0,ratio)=(12,21,4)`, while the retained source default and
   both Makefile recipes use `(10,30,4)` at `tol=1e-13`.

   Correction: replace the command with:

   ```sh
   ./build/dht_accuracy 65536 1e-13 10 10 30 512 4
   ```

2. **Benchmark documentation overstates the CSV and accuracy harness.**
   `bench/README.md:3` says the CSV records the derived seed and performs
   adversarial large-N checks. `bench/benchmark.c` emits the seed only in
   non-CSV output; the CSV emits `input_hash,output_hash,sample_re,sample_im`.
   `bench/accuracy.c` performs fixed selected-row large-N diagnostics and full
   delta-column checks; residual-sign adversarial inputs are handled by the
   separate `research/` driver.

   Correction: change the sentence to:

   > The random stream is derived from the fixed base seed `0x8f3c2d1e7a6b5948`, `N`, and case number; the CSV records full input/output FNV-1a digests but does not record the derived seed. Correctness uses dense direct evaluation at small N plus an independent multiprecision reference, selected-row large-N diagnostics, and full large-N delta-column checks; residual-sign adversarial validation is separate under `research/`.

   `bench/README.md:5` also calls `run_winner.sh` a selected-profile sweep,
   although it runs the five-case retained-profile sweep, five finalist
   comparison rows, and six scaling rows. Replace it with:

   > Run the retained profile's five-case/scaling sweep and finalist profile comparison with:

3. **The archive CSV has one malformed record.** `research/archive.csv:5`
   (H4) has 16 fields because of an extra final comma, while its 15-field
   header and every other record have 15 fields.

   Correction: replace the row ending
   `rejected,0.0877,,1.99e-14,` with
   `rejected,0.0877,,1.99e-14`.

4. **H3's complexity formula omits the repeated full-FFT factor.**
   `research/archive.csv:4` says `O(K N log N/log 4 + N log N)`. The source
   executes a length-N, `terms`-batched FFT once per active ratio-4 band, and
   there are `Theta(log_4 N)` bands.

   Correction: replace the `predicted_complexity` field with
   `O(K N (log N)^2/log 4 + N log N)`.

5. **The archive does not identify the current retained profile.** H2 is
   marked `validated_baseline` without a profile/N/source identity, and H3 is
   marked `rejected` even though the current source is the ratio-4 H3-family
   implementation; the recorded H3 failure is specifically `(terms,z0,ratio)
   =(12,18,4)`.

   Correction: change H2's status to `historical_baseline`, change H3's status
   to `profile_specific_rejection`, scope its failure text to
   `(12,18,4)`, and append this 15-field H10 record:

   ```csv
   H10,"H3; finalist sweep","grouped ratio-4 masked FFT","Retained profile terms=10,z0=30,ratio=4 with product-safe suffix masks and direct near field","O(K N (log N)^2/log 4 + N log N)","O(KN+N log N)","60 length-N FFT executions/apply; 6,603,633 direct entries; 74,849,448 accounted plan bytes at N=65536","small-N dense and selected-row residual-sign screening","no full arbitrary-vector N=65536 MPFR certificate","current retained speed-first profile","run frozen-source full-vector MPFR gate and profile benchmark",provisional,,,
   ```

6. **The research log names a rejected historical profile as current.**
   `research/log.md:43-50` calls `(K=12,z0=18,r=4)` the current performance
   candidate, even though the same paragraph records its residual-sign failure.
   At the target tolerance, `src/dht_asym.c:44-51,313-317` selects
   `(terms,z0,block_ratio)=(10,30,4)`.

   Correction: change “The current performance candidate” to “The former
   performance candidate,” and add the following current-source statement:

   ```text
   The current retained speed-first profile is (terms=10,z0=30,block_ratio=4): 60 full-length FFT executions per apply, 6,603,633 precomputed direct entries, and 74,849,448 accounted reusable plan bytes at N=65536. This is a provisional screening selection; the required full arbitrary-vector N=65536 MPFR gate is not archived.
   ```

7. **Winner wording overclaims validation.** `best/README.md:1,3` says
   “Validated winner” and “The winner is,” and `best/dht_asym.c:1` says
   “Stable winner entry point.” The repository acceptance gate is not met for
   an arbitrary complex vector over all output rows at `N=65536`; current
   evidence is small-N full-vector, selected-row large-N, and delta-control
   evidence.

   Correction: use `# Selected implementation (provisional)`, replace “The
   winner is” with “The selected speed-first implementation is,” and replace
   the wrapper comment with `/* Selected implementation entry point; keep the implementation in src/ as canonical. */`.
   Add: “It is not certified for an arbitrary binary64 complex vector at
   N=65536.”

8. **Current-default claims in later worker reports are stale.**
   `research/worker12_audit.md:138-140,158,188,210-212`,
   `research/worker17_api_audit.md:15-16,58-66`,
   `research/worker18_citation_audit.md:37`, and
   `research/worker20_benchmark_integrity.md:101-121` describe `(11,23,4)`
   or `(12,21,4)` as the current source/default or recommend commands that
   exercise those profiles. Those are earlier snapshots.

   Correction: where the text means the current source/default, replace the
   profile with `(10,30,4)` and use
   `./build/dht_accuracy 65536 1e-13 10 10 30 512 4` plus
   `./build/dht_benchmark 65536 31 5 1e-13 10 10 30 4 0 csv`. Otherwise prefix
   the passage with `In the earlier source snapshot` and do not call it current.

9. **Current-facing plan-byte figures in research reports are stale.**
   `research/worker13_profile_sweep.md`, `worker15_scaling.md`,
   `worker19_large_accuracy.md`, `worker20_benchmark_integrity.md`, and
   `worker27_leaderboard_review.md` quote pre-current accounting while
   describing current-source/leaderboard data. The current source's exact
   N=65536 metadata is:

   | `(terms,z0,ratio)` | direct entries | `plan_bytes` |
   |---|---:|---:|
   | `(10,30,4)` | 6,603,633 | 74,849,448 |
   | `(12,21,4)` | 4,769,025 | 64,366,904 |
   | `(11,23,4)` | 5,194,869 | 65,676,496 |
   | `(10,40,4)` | 8,457,345 | 89,679,144 |
   | `(12,22,4)` | 5,014,209 | 66,328,376 |
   | `(12,20.25,4)` | 4,580,385 | 62,857,784 |
   | `(12,20.5,4)` | 4,678,977 | 63,646,520 |
   | `(12,18,4)` | 4,104,957 | 59,054,360 |

   Correction: replace any current-facing values in those reports with this
   table. Preserve raw historical measurements only if explicitly labeled as
   pre-current-source snapshots; do not use them for the current leaderboard.
