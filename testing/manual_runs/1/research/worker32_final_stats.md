# Worker 32 — final CSV statistics

## Status

**PASS — current CSV is complete and well-formed.** All values below are
computed from the current
`/Users/alex/areas/productive/orchestration/testing/manual_runs/1/bench/results.csv`.
Timing statistics use the raw semicolon-separated `samples_s` values. The
robust spread is the interquartile range, `IQR = Q3 - Q1`, with inclusive
quartile interpolation.

| Check | Result |
|---|---:|
| Physical lines | 17 |
| CSV records including header | 17 |
| Header columns | 21 |
| Header matches current 21-column schema | yes |
| Data rows | 16 |
| Malformed rows | 0 |
| Non-finite values | 0 |
| Sample-count mismatches | 0 |
| Winner-case rows | 5 |
| Finalist comparison rows | 5 |
| N-scaling rows | 6 |

The five winner rows contain 155 raw samples, the five finalist rows contain
255, and the six scaling rows contain 66. Recomputed row medians, minima, and
maxima exactly match the stored `median_s`, `min_s`, and `max_s` values at the
CSV's displayed precision.

## Winner five-case sweep

Profile: `blocked_asym_fft`, `N=65536`, `reps=31`, `warmups=5`, `threads=10`,
`terms=10`, `z0=30`, `block_ratio=4`. Times are seconds; `plan_bytes` is
reusable plan memory.

| CSV line | Case | Q1 (s) | Median (s) | Q3 (s) | IQR (s) | Min (s) | Max (s) | Setup (s) | Plan bytes |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 2 | random | 0.016763500 | 0.018330000 | 0.020095500 | 0.003332000 | 0.014137000 | 0.023359000 | 0.702071000 | 74,849,448 |
| 3 | gaussian | 0.015047500 | 0.016729000 | 0.019807000 | 0.004759500 | 0.014019000 | 0.039761000 | 0.699535000 | 74,849,448 |
| 4 | compact_bump | 0.014986500 | 0.015922000 | 0.016971500 | 0.001985000 | 0.013996000 | 0.027214000 | 0.683312000 | 74,849,448 |
| 5 | oscillatory | 0.014897500 | 0.015944000 | 0.016755000 | 0.001857500 | 0.014117000 | 0.018821000 | 0.682544000 | 74,849,448 |
| 6 | dynamic | 0.014197000 | 0.015576000 | 0.016662500 | 0.002465500 | 0.013745000 | 0.022593000 | 0.681350000 | 74,849,448 |

Pooled across the five cases: 155 raw samples; Q1 `0.015040500` s, median
`0.016309000` s, Q3 `0.018220000` s, IQR `0.003179500` s, minimum
`0.013745000` s, maximum `0.039761000` s. Setup median/min/max are
`0.683312000/0.681350000/0.702071000` s; plan memory is fixed at
`74,849,448` bytes.

## Finalist comparison rows

All five rows are `random`, `N=65536`, `reps=51`, `warmups=7`, `threads=10`,
and `block_ratio=4`.

| CSV line | Terms | z0 | Q1 (s) | Median (s) | Q3 (s) | IQR (s) | Min (s) | Max (s) | Setup (s) | Plan bytes |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 7 | 12 | 21 | 0.016898000 | 0.017957000 | 0.019685000 | 0.002787000 | 0.015131000 | 0.025540000 | 0.653617000 | 64,366,904 |
| 8 | 11 | 23 | 0.015372500 | 0.016263000 | 0.020340500 | 0.004968000 | 0.014682000 | 0.028501000 | 0.774897000 | 65,676,496 |
| 9 | 10 | 30 | 0.016432000 | 0.019069000 | 0.021901500 | 0.005469500 | 0.013677000 | 0.039740000 | 0.706185000 | 74,849,448 |
| 10 | 10 | 40 | 0.017864000 | 0.020206000 | 0.025682500 | 0.007818500 | 0.015559000 | 0.058162000 | 0.777565000 | 89,679,144 |
| 11 | 12 | 22 | 0.016338500 | 0.017578000 | 0.020409500 | 0.004071000 | 0.015490000 | 0.030171000 | 0.674959000 | 66,328,376 |

By row median, the current finalist ordering is `(11,23)` at `0.016263000` s,
`(12,22)` at `0.017578000` s, `(12,21)` at `0.017957000` s, `(10,30)` at
`0.019069000` s, and `(10,40)` at `0.020206000` s. Pooled across these rows:
255 raw samples; Q1 `0.016386000` s, median `0.018478000` s, Q3
`0.021314500` s, IQR `0.004928500` s, minimum `0.013677000` s, and maximum
`0.058162000` s. Setup median/min/max are
`0.706185000/0.653617000/0.777565000` s; plan memory ranges from
`64,366,904` to `89,679,144` bytes.

## N scaling

Scaling profile: `blocked_asym_fft`, `case=random`, `reps=11`, `warmups=3`,
`threads=10`, `terms=10`, `z0=30`, `block_ratio=4`. The final column is the
current row median divided by the preceding power-of-two row median.

| CSV line | N | Q1 (s) | Median (s) | Q3 (s) | IQR (s) | Min (s) | Max (s) | Median ratio | Setup (s) | Plan bytes |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 12 | 4,096 | 0.000946500 | 0.001024000 | 0.001158000 | 0.000211500 | 0.000853000 | 0.001300000 | — | 0.212399000 | 3,739,544 |
| 13 | 8,192 | 0.001934500 | 0.002020000 | 0.002614500 | 0.000680000 | 0.001713000 | 0.004272000 | 1.972656250 | 0.336699000 | 7,775,392 |
| 14 | 16,384 | 0.003032000 | 0.003094000 | 0.003122500 | 0.000090500 | 0.002924000 | 0.003494000 | 1.531683168 | 0.454367000 | 16,835,104 |
| 15 | 32,768 | 0.006608000 | 0.006793000 | 0.007219000 | 0.000611000 | 0.006466000 | 0.008349000 | 2.195539754 | 0.728080000 | 34,855,848 |
| 16 | 65,536 | 0.014530000 | 0.014937000 | 0.016130000 | 0.001600000 | 0.014038000 | 0.016708000 | 2.198881201 | 0.695624000 | 74,849,448 |
| 17 | 131,072 | 0.044255500 | 0.048270000 | 0.049298000 | 0.005042500 | 0.038786000 | 0.052034000 | 3.231572605 | 1.041887000 | 154,442,288 |

Pooled across all six sizes: 66 raw samples; Q1 `0.002042750` s, median
`0.005369000` s, Q3 `0.014863750` s, IQR `0.012821000` s, minimum
`0.000853000` s, and maximum `0.052034000` s. This pooled spread is
descriptive only because the samples span six different problem sizes.
Setup median/min/max are `0.574995500/0.212399000/1.041887000` s; plan
memory grows from `3,739,544` to `154,442,288` bytes.

## Integrity conclusion

Strict CSV parsing produced 16 data records, each with exactly 21 fields. All
expected profile rows are present (`5 + 5 + 6 = 16`), every `samples_s` list
has the declared repetition count, and all timing values are finite. No
source, benchmark, or CSV file was edited for this report.
