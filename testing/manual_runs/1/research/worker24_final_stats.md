# Worker 24 — final benchmark statistics

## Machine-readable status

```yaml
status: INCOMPLETE_STALE_SNAPSHOT
source: /Users/alex/areas/productive/orchestration/testing/manual_runs/1/bench/results.csv
results_mtime: "2026-08-28 11:38:57 -0700"
current_writer_mtime: "2026-08-28 11:44:51 -0700"
physical_lines: 12
csv_records_including_header: 12
data_rows_present: 11
stored_header_columns: 19
current_writer_columns: 21
expected_data_rows_current_run_winner: 16
winner_case_rows: 5
winner_case_raw_samples: 155
scaling_rows: 6
scaling_raw_samples: 66
finalist_profile_rows_present: 0
finalist_profile_rows_expected: 5
malformed_rows: 0
exact_duplicate_rows: 0
overlapping_candidate_case_N_keys: 1
finality_check: FAIL
```

The snapshot is stable and had no open writer, but it is not final under the
current `bench/run_winner.sh`: the current script runs 5 input cases, 5
profile-comparison rows, and 6 scaling rows (16 data rows total). The stored
file has only the 5 input-case rows and 6 scaling rows. Its 19-column legacy
header also disagrees with the current 21-column writer: it has
`checksum_re,checksum_im` where the current writer emits
`input_hash,output_hash,sample_re,sample_im`.

## Timing summaries

All timing statistics below use the semicolon-separated `samples_s` values;
setup and plan memory are reported separately. Q1/Q3 use Python
`statistics.quantiles(..., n=4, method="inclusive")`.

Pooled raw-repetition summaries:

| Scope | Rows | Raw samples | Q1 (s) | Median (s) | Q3 (s) | Min (s) | Max (s) |
|---|---:|---:|---:|---:|---:|---:|---:|
| Winner: five input cases | 5 | 155 | 0.026798000 | 0.028135000 | 0.031899500 | 0.024403000 | 0.049222000 |
| N scaling: random | 6 | 66 | 0.003535000 | 0.010125500 | 0.029206250 | 0.001090000 | 0.064436000 |
| Finalist/profile comparison | 0 | 0 | — | — | — | — | — |

Per-row summaries (seconds):

| Scope | CSV line | Case | N | Reps | Q1 | Median | Q3 | Min | Max | Setup | Plan bytes |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| winner case | 2 | random | 65536 | 31 | 0.027054000 | 0.029739000 | 0.032179000 | 0.024892000 | 0.049222000 | 0.638582000 | 64366816 |
| winner case | 3 | gaussian | 65536 | 31 | 0.028913500 | 0.032022000 | 0.034661500 | 0.024782000 | 0.044442000 | 0.698338000 | 64366816 |
| winner case | 4 | compact_bump | 65536 | 31 | 0.026800500 | 0.027308000 | 0.027945500 | 0.025132000 | 0.035943000 | 0.665946000 | 64366816 |
| winner case | 5 | oscillatory | 65536 | 31 | 0.027597500 | 0.029633000 | 0.032187500 | 0.024591000 | 0.037420000 | 0.676023000 | 64366816 |
| winner case | 6 | dynamic | 65536 | 31 | 0.025956000 | 0.026709000 | 0.027500000 | 0.024403000 | 0.036725000 | 0.640917000 | 64366816 |
| N scaling | 7 | random | 4096 | 11 | 0.001557000 | 0.001776000 | 0.002593000 | 0.001090000 | 0.006989000 | 0.244061000 | 3366016 |
| N scaling | 8 | random | 8192 | 11 | 0.003110000 | 0.003167000 | 0.003612000 | 0.002902000 | 0.004824000 | 0.332378000 | 6930368 |
| N scaling | 9 | random | 16384 | 11 | 0.005631000 | 0.005980000 | 0.006498000 | 0.004908000 | 0.007484000 | 0.484026000 | 14777632 |
| N scaling | 10 | random | 32768 | 11 | 0.013941000 | 0.014148000 | 0.015120000 | 0.012767000 | 0.016450000 | 0.785919000 | 30349280 |
| N scaling | 11 | random | 65536 | 11 | 0.027628500 | 0.029581000 | 0.034416000 | 0.026006000 | 0.043047000 | 0.656482000 | 64366816 |
| N scaling | 12 | random | 131072 | 11 | 0.061381500 | 0.063263000 | 0.063622000 | 0.059573000 | 0.064436000 | 0.966989000 | 131910272 |

Reusable setup summaries are: winner-case setup median/min/max
`0.665946000/0.638582000/0.698338000` seconds, and scaling setup
median/min/max `0.570254000/0.244061000/0.966989000` seconds. Plan memory is
`64366816` bytes for all winner-case rows and varies with N as shown above for
scaling.

## Finalist/profile coverage

The current script expects these five N=65536, random, 51-repetition,
7-warmup profile rows; none is present:

| Terms | z0 | Rows present |
|---:|---:|---:|
| 12 | 21 | 0 |
| 11 | 23 | 0 |
| 10 | 30 | 0 |
| 10 | 40 | 0 |
| 12 | 22 | 0 |

Therefore no finalist comparison can be summarized from this CSV.

## Integrity checks and flags

- `csv.reader(strict=True)` parsed all 12 records; every data row has 19
  fields matching the stored header. No malformed rows, non-finite values, or
  sample-count errors were found.
- Recomputed row medians, minima, and maxima from `samples_s` agree with the
  stored timing columns within `5e-10` seconds.
- Exact duplicate data rows: 0.
- The semantic key `(candidate, case, N)` overlaps once:
  `blocked_asym_fft,random,65536` occurs on lines 2 and 11. This is not an
  exact duplicate: it is the five-case protocol (31 reps, 5 warmups) and the
  scaling protocol (11 reps, 3 warmups), but it must not be combined as one
  observation. Their legacy checksum fields differ by about 1 ulp
  (`4.4e-16` real and `2.2e-16` imaginary), so the overlap is flagged for
  review rather than silently treated as identical.
- The stale 19-column schema, missing five profile rows, and 11-versus-16 row
  count make this an incomplete final benchmark artifact. The available
  winner/scaling timing rows are internally consistent, but this file cannot
  support a complete finalist comparison or a final winner claim.

## Commands and tools used

Read-only commands/tools used:

```sh
stat -f '%N|bytes=%z|mtime=%Sm' -t '%Y-%m-%d %H:%M:%S %z' bench/run_winner.sh bench/benchmark.c bench/results.csv
sleep 1
lsof -- bench/results.csv
nl -ba bench/results.csv
nl -ba bench/run_winner.sh
nl -ba bench/benchmark.c | sed -n '160,172p'
python3 - <<'PY'   # inline read-only validator
```

The validator used only Python 3 standard-library modules `csv`, `math`,
`statistics`, `pathlib`, and `collections`; it checked CSV shape/types,
sample counts, derived median/min/max, quartiles, duplicate keys, expected
row coverage, and group summaries. No benchmark was rerun, and no source or
benchmark file was edited.
