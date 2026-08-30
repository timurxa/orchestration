# Worker 15 — large-N finalist scaling

Date: 2026-08-28

## Result

At one FFTW worker, deterministic complex `random` input, and five timed
applications, `(K=10,z0=30,ratio=4)` is the fastest median at all six sizes.
The broad speed ranking therefore does not change durably with `N`, although
the order of the three slower profiles moves around at close sizes.

`(K=12,z0=21,ratio=4)` has the smallest accounted reusable plan at every size.
At `N=131072` it is 125.799 MiB versus 147.288 MiB for the speed leader
`(10,30)`, while its median apply is 22.4% slower in this run.  Memory changes
the practical tradeoff, but does not create a new speed winner: `(12,21)` is
the best memory-constrained choice, and `(10,30)` remains the time-first
choice.

## Protocol

The repository build artifact was older than the current `src/dht_asym.c` when
the sweep started, so the benchmark was compiled into system temp from the
current `src/dht_asym.c` and `bench/benchmark.c`.  This run wrote only the
temporary executable; no file under `src/` or `bench/` was edited.  The compile
command was:

```text
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic -I/opt/homebrew/include bench/benchmark.c src/dht_asym.c -L/opt/homebrew/lib -lfftw3_threads -lfftw3 -lm -o /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current
```

In the command below, benchmark `terms` is the requested `K` and `cutoff` is
`z0`:

```text
/private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current N 5 2 1e-13 1 K z0 4 0
```

The sweep used `N=4096,8192,16384,32768,65536,131072`, two warmups, five
timed repetitions, one FFTW worker, ratio 4, tolerance `1e-13`, and case `0`
(`random`).  `setup_s` is outside the timed `dht_apply` median.  `plan_bytes`
is the source's accounted reusable plan size; it is not peak RSS and excludes
FFTW's internal plan allocation and the benchmark's input/output arrays.

## Median apply time

Values below are the reported `median_s`, converted to milliseconds.

| N | `(10,30)` | `(10,40)` | `(12,21)` | `(12,22)` |
|---:|---:|---:|---:|---:|
| 4,096 | 1.614 | 1.838 | 1.712 | 1.741 |
| 8,192 | 3.811 | 4.515 | 4.297 | 4.518 |
| 16,384 | 8.901 | 10.856 | 10.250 | 10.231 |
| 32,768 | 21.418 | 24.902 | 24.691 | 24.789 |
| 65,536 | 51.658 | 57.041 | 58.871 | 54.858 |
| 131,072 | 110.475 | 126.975 | 135.183 | 134.524 |

The fastest-to-slowest order by size was:

| N | order |
|---:|---|
| 4,096 | `(10,30)`, `(12,21)`, `(12,22)`, `(10,40)` |
| 8,192 | `(10,30)`, `(12,21)`, `(10,40)`, `(12,22)` |
| 16,384 | `(10,30)`, `(12,22)`, `(12,21)`, `(10,40)` |
| 32,768 | `(10,30)`, `(12,21)`, `(12,22)`, `(10,40)` |
| 65,536 | `(10,30)`, `(12,22)`, `(10,40)`, `(12,21)` |
| 131,072 | `(10,30)`, `(10,40)`, `(12,22)`, `(12,21)` |

The middle profiles are close at some sizes, and their order is not stable:
for example, at `N=65536`, `(12,22)` is 54.858 ms, `(10,40)` is 57.041 ms,
and `(12,21)` is 58.871 ms.  At `N=16384`, `(10,40)` has one unusually slow
sample (`0.024093` s), so the five-repetition medians should be read as a
bounded screening result rather than a precision ranking of near ties.

## Scaling

The effective exponent is
`p = log2(median_131072 / median_4096) / 5`, across five doublings.

| profile | time factor, 4,096→131,072 | effective `p` | setup factor | plan-size factor |
|---|---:|---:|---:|---:|
| `(10,30)` | 68.448× | 1.219 | 5.04× | 41.300× |
| `(10,40)` | 69.083× | 1.222 | 5.72× | 42.668× |
| `(12,21)` | 78.962× | 1.261 | 4.87× | 39.189× |
| `(12,22)` | 77.268× | 1.254 | 5.09× | 39.431× |

The final `65536→131072` time factors were 2.139×, 2.226×, 2.296×, and
2.452× respectively.  This is broadly near the `N log N` expectation of
`2 × 17/16 = 2.125×`; small-size planning/cache effects and the short timed
sample make the fitted exponents non-identical.  There is no sustained
large-`N` reversal of the speed ordering.

## Setup and reusable memory

Each cell is `setup_s / plan_bytes`, with bytes also shown in MiB
(`2^20` bytes):

| N | `(10,30)` | `(10,40)` | `(12,21)` | `(12,22)` |
|---:|---:|---:|---:|---:|
| 4,096 | 0.205897 s / 3.566 MiB | 0.197987 s / 4.152 MiB | 0.194392 s / 3.210 MiB | 0.193984 s / 3.297 MiB |
| 8,192 | 0.241563 s / 7.415 MiB | 0.259424 s / 8.685 MiB | 0.246227 s / 6.609 MiB | 0.248646 s / 6.813 MiB |
| 16,384 | 0.359059 s / 16.055 MiB | 0.401052 s / 18.994 MiB | 0.380546 s / 14.093 MiB | 0.370401 s / 14.501 MiB |
| 32,768 | 0.551052 s / 33.241 MiB | 0.580818 s / 39.513 MiB | 0.565439 s / 28.943 MiB | 0.545359 s / 29.877 MiB |
| 65,536 | 0.673506 s / 71.382 MiB | 0.717299 s / 85.525 MiB | 0.639857 s / 61.385 MiB | 0.641263 s / 63.256 MiB |
| 131,072 | 1.038107 s / 147.288 MiB | 1.133401 s / 177.151 MiB | 0.946604 s / 125.799 MiB | 0.986469 s / 130.011 MiB |

At `N=131072`, memory order is `(12,21)` < `(12,22)` < `(10,30)` <
`(10,40)`.  Relative to `(12,21)`, the other plans use 3.3%, 17.1%, and
40.8% more accounted plan memory respectively.  Direct-entry counts at the
same endpoint are 9,935,157, 10,487,221, 13,800,225, and 17,714,433 in that
memory order.  Setup rises from about 0.20 s at `N=4096` to 0.98–1.13 s at
`N=131072`; it remains reusable and is excluded from the apply medians.

Thus memory can change the selection if the budget is near the 130–150 MiB
range: `(12,21)` buys the smallest footprint, at a measured 22.4% speed
penalty versus `(10,30)` at the endpoint.  `(12,22)` is only 3.3% larger than
`(12,21)` and is 0.5% faster at `N=131072` in this run, so those two remain a
near-tie on time but not on memory.  `(10,40)` is 14.9% slower than `(10,30)`
at the endpoint while using 20.3% more plan memory, so memory does not rescue
its ranking here.

## Raw command outputs

The following is the retained sweep output verbatim.  The `samples=` field is
the five individual timed applies used to form each median.

```text
# host
Darwin Rogers-MacBook-Pro.local 25.5.0 Darwin Kernel Version 25.5.0: Tue Jun  9 22:18:58 PDT 2026; root:xnu-12377.121.10~1/RELEASE_ARM64_T6000 arm64
# compiler
Apple clang (temp build from current src/dht_asym.c and bench/benchmark.c)
# executable
/private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 4096 5 2 1e-13 1 10 30 4 0
N=4096 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=30.0 direct=295377 setup_s=0.205897 median_s=0.001614 min_s=0.001594 max_s=0.001820 plan_bytes=3739480 checksum=-1.4914623407437941,1.5038461373211889 samples=0.001614000;0.001606000;0.001594000;0.001619000;0.001820000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 4096 5 2 1e-13 1 10 40 4 0
N=4096 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=40.0 direct=372129 setup_s=0.197987 median_s=0.001838 min_s=0.001823 max_s=0.001953 plan_bytes=4353496 checksum=-1.4914623407437952,1.5038461373211893 samples=0.001953000;0.001838000;0.001832000;0.001871000;0.001823000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 4096 5 2 1e-13 1 12 21 4 0
N=4096 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=21.0 direct=215925 setup_s=0.194392 median_s=0.001712 min_s=0.001684 max_s=0.001741 plan_bytes=3366024 checksum=-1.4914623407437939,1.5038461373211889 samples=0.001723000;0.001684000;0.001690000;0.001712000;0.001741000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 4096 5 2 1e-13 1 12 22 4 0
N=4096 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=22.0 direct=227337 setup_s=0.193984 median_s=0.001741 min_s=0.001709 max_s=0.001795 plan_bytes=3457320 checksum=-1.4914623407437944,1.5038461373211891 samples=0.001795000;0.001744000;0.001717000;0.001709000;0.001741000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 8192 5 2 1e-13 1 10 30 4 0
N=8192 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=30.0 direct=627825 setup_s=0.241563 median_s=0.003811 min_s=0.003810 max_s=0.003936 plan_bytes=7775320 checksum=-1.3873861009957829,1.8032720627033554 samples=0.003810000;0.003811000;0.003810000;0.003936000;0.003858000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 8192 5 2 1e-13 1 10 40 4 0
N=8192 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=40.0 direct=794241 setup_s=0.259424 median_s=0.004515 min_s=0.004463 max_s=0.004604 plan_bytes=9106648 checksum=-1.3873861009957824,1.8032720627033556 samples=0.004604000;0.004515000;0.004463000;0.004576000;0.004475000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 8192 5 2 1e-13 1 12 21 4 0
N=8192 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=21.0 direct=456669 setup_s=0.246227 median_s=0.004297 min_s=0.004209 max_s=0.004437 plan_bytes=6930376 checksum=-1.3873861009957822,1.8032720627033567 samples=0.004209000;0.004437000;0.004337000;0.004297000;0.004292000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 8192 5 2 1e-13 1 12 22 4 0
N=8192 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=22.0 direct=483349 setup_s=0.248646 median_s=0.004518 min_s=0.004475 max_s=0.004922 plan_bytes=7143816 checksum=-1.3873861009957831,1.803272062703356 samples=0.004518000;0.004516000;0.004922000;0.004475000;0.004648000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 16384 5 2 1e-13 1 10 30 4 0
N=16384 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=30.0 direct=1416225 setup_s=0.359059 median_s=0.008901 min_s=0.008598 max_s=0.009048 plan_bytes=16835032 checksum=-1.7796975055757511,1.1866669218681991 samples=0.008945000;0.008901000;0.008598000;0.009048000;0.008752000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 16384 5 2 1e-13 1 10 40 4 0
N=16384 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=40.0 direct=1801425 setup_s=0.401052 median_s=0.010856 min_s=0.010451 max_s=0.024093 plan_bytes=19916632 checksum=-1.7796975055757511,1.1866669218681991 samples=0.010645000;0.010451000;0.024093000;0.010856000;0.011683000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 16384 5 2 1e-13 1 12 21 4 0
N=16384 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=21.0 direct=1027977 setup_s=0.380546 median_s=0.010250 min_s=0.010013 max_s=0.011039 plan_bytes=14777640 checksum=-1.7796975055757507,1.1866669218681998 samples=0.010018000;0.011039000;0.010531000;0.010013000;0.010250000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 16384 5 2 1e-13 1 12 22 4 0
N=16384 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=22.0 direct=1081449 setup_s=0.370401 median_s=0.010231 min_s=0.009967 max_s=0.010319 plan_bytes=15205416 checksum=-1.7796975055757511,1.1866669218681993 samples=0.010231000;0.010194000;0.010301000;0.009967000;0.010319000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 32768 5 2 1e-13 1 10 30 4 0
N=32768 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=30.0 direct=2980689 setup_s=0.551052 median_s=0.021418 min_s=0.021096 max_s=0.022134 plan_bytes=34855768 checksum=-1.4367201662548612,1.2728439749409268 samples=0.021346000;0.021762000;0.021418000;0.021096000;0.022134000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 32768 5 2 1e-13 1 10 40 4 0
N=32768 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=40.0 direct=3802785 setup_s=0.580818 median_s=0.024902 min_s=0.024506 max_s=0.026100 plan_bytes=41432536 checksum=-1.4367201662548614,1.2728439749409266 samples=0.025508000;0.024653000;0.024902000;0.024506000;0.026100000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 32768 5 2 1e-13 1 12 21 4 0
N=32768 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=21.0 direct=2155233 setup_s=0.565439 median_s=0.024691 min_s=0.024198 max_s=0.024972 plan_bytes=30349288 checksum=-1.4367201662548623,1.2728439749409253 samples=0.024653000;0.024198000;0.024860000;0.024972000;0.024691000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 32768 5 2 1e-13 1 12 22 4 0
N=32768 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=22.0 direct=2277601 setup_s=0.545359 median_s=0.024789 min_s=0.023971 max_s=0.025348 plan_bytes=31328232 checksum=-1.4367201662548619,1.272843974940925 samples=0.023971000;0.024789000;0.024324000;0.024979000;0.025348000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 65536 5 2 1e-13 1 10 30 4 0
N=65536 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=30.0 direct=6603633 setup_s=0.673506 median_s=0.051658 min_s=0.048512 max_s=0.053047 plan_bytes=74849368 checksum=-2.0513742075942591,0.96422834125848211 samples=0.051658000;0.050010000;0.053047000;0.052905000;0.048512000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 65536 5 2 1e-13 1 10 40 4 0
N=65536 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=40.0 direct=8457345 setup_s=0.717299 median_s=0.057041 min_s=0.055543 max_s=0.059467 plan_bytes=89679064 checksum=-2.0513742075942596,0.964228341258482 samples=0.056142000;0.059467000;0.057451000;0.057041000;0.055543000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 65536 5 2 1e-13 1 12 21 4 0
N=65536 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=21.0 direct=4769025 setup_s=0.639857 median_s=0.058871 min_s=0.058125 max_s=0.061208 plan_bytes=64366824 checksum=-2.0513742075942596,0.96422834125848267 samples=0.061208000;0.058534000;0.058125000;0.058871000;0.059686000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 65536 5 2 1e-13 1 12 22 4 0
N=65536 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=22.0 direct=5014209 setup_s=0.641263 median_s=0.054858 min_s=0.054282 max_s=0.055946 plan_bytes=66328296 checksum=-2.05137420759426,0.96422834125848234 samples=0.054282000;0.054857000;0.054858000;0.055062000;0.055946000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 131072 5 2 1e-13 1 10 30 4 0
N=131072 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=30.0 direct=13800225 setup_s=1.038107 median_s=0.110475 min_s=0.110136 max_s=0.111527 plan_bytes=154442200 checksum=-2.0271412283410744,0.91474280440547096 samples=0.111187000;0.110475000;0.110136000;0.110179000;0.111527000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 131072 5 2 1e-13 1 10 40 4 0
N=131072 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=10 z0=40.0 direct=17714433 setup_s=1.133401 median_s=0.126975 min_s=0.126415 max_s=0.127788 plan_bytes=185755864 checksum=-2.0271412283410735,0.91474280440546996 samples=0.127788000;0.126748000;0.126975000;0.127695000;0.126415000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 131072 5 2 1e-13 1 12 21 4 0
N=131072 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=21.0 direct=9935157 setup_s=0.946604 median_s=0.135183 min_s=0.129643 max_s=0.138745 plan_bytes=131910280 checksum=-2.0271412283410739,0.91474280440546951 samples=0.136536000;0.135183000;0.129643000;0.129708000;0.138745000

$ /private/tmp/worker15_scaling_current.tx95yP/dht_benchmark_current 131072 5 2 1e-13 1 12 22 4 0
N=131072 case=random reps=5 warmups=2 threads=1 ratio=4 tol=1.000e-13 terms=12 z0=22.0 direct=10487221 setup_s=0.986469 median_s=0.134524 min_s=0.129204 max_s=0.138032 plan_bytes=136326792 checksum=-2.0271412283410744,0.91474280440546996 samples=0.138032000;0.134524000;0.133269000;0.137122000;0.129204000
```
