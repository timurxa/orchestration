# Worker 13 — ratio-4 finalist profile screening

Date: 2026-08-28

## Bounded conclusion

**Recommended finalist: `(K=10, z0=30, ratio=4)`.** It is the fastest profile
supported by the retained timing evidence and has the largest observed
bandwise residual-sign margin among the profiles with complete large-N
coverage.

This is a screening recommendation, not a new final certification: the user
stopped the sweep while `(K=12,z0=22)` was partway through `N=16384`, before
any large-N checks for `(K=8,z0=48)`. No additional computation was started
after interruption.

## Accuracy verdict

The driver used an independent 400-bit MPFR evaluator for both `J0` and the
K-term asymptotic expansion, ratio 4, and the acceptance metrics from the
repository (`normalized L2 <= 1e-13`, `scaled Linf <= 1e-12`). Small cases
were full-vector references at `N=64,128,256,512`. Large cases used the
selected rows `{0,1,3,4,15,16,63,64,255,256,1023,1024,4095,4096,16383,
16384,32768,N/2,N-1}` where in range. For each profile, a residual-sign input
was generated independently for every active ratio-4 band lower endpoint.

| profile | completed evidence | formal gate | worst observed target-row relative error | disposition |
|---|---|---|---:|---|
| `(10,30)` | full small N; all active bands and selected rows at 1024, 4096, 16384, 65536 | **PASS** | `1.09e-14` | **recommend** |
| `(11,23)` | full small N; all active bands and selected rows at 1024, 4096, 16384, 65536 | PASS, but no rowwise margin | `1.114e-12` | **reject for finalist** |
| `(12,20.5)` | full small N; all active bands and selected rows at 1024, 4096, 16384, 65536 | **PASS** | `2.08e-13` | pass screening |
| `(12,22)` | full small N; all bands through 4096; `N=16384` through target rows 4 and 16 | **PASS on completed checks** | `1.31e-13` | provisional only |
| `(8,48)` | full small N; all active bands | **PASS on completed checks** | `3.35e-14` | large-N evidence missing |

The `(11,23)` formal selected-row aggregate passes because its denominator is
the maximum reference magnitude over the selected set, but the adversarial
target row itself exceeds `1e-12` at some bands (`1.114e-12` at `N=65536`,
`m=16384`; also slightly above `1e-12` at smaller checkpoints). It therefore
does not have the requested safety margin.

For `(10,30)`, the worst completed full/selected aggregate was approximately
`1.05e-14` normalized L2 and `1.09e-14` scaled Linf, with the worst target-row
relative error also about `1.09e-14`. The largest completed `(12,20.5)` values
were approximately `4.90e-14` and `5.22e-14`, respectively. These are the
reasons `(10,30)` is preferred over the lower-order `(11,23)` despite its
larger direct region.

## Speed, setup, and memory

The worker13 timing run was intentionally not started before interruption.
The retained same-host ratio-4 scaling sweep in
[`worker15_scaling.md`](/Users/alex/areas/productive/orchestration/testing/manual_runs/1/research/worker15_scaling.md)
measured `(10,30)` as the fastest profile at every tested size; at `N=65536`
its warmed input-dependent apply median was `51.658 ms`, versus `54.858 ms`
for `(12,22)` (one FFTW worker, five repeats, deterministic random complex
input). Thus the speed claim here is inherited screening evidence, not a new
worker13 timing measurement for every candidate.

Completed worker13 plan metadata at `N=65536`:

| profile | direct entries | accounted plan bytes |
|---|---:|---:|
| `(10,30)` | `6,603,633` | `74,849,368` |
| `(11,23)` | `5,194,869` | `65,676,416` |
| `(12,20.5)` | `4,678,977` | `63,646,440` |

The prior timing sweep reports `(10,30)` setup `0.673506 s` and the same
`74,849,368` plan bytes at `N=65536`; setup is reusable and excluded from the
apply median. Setup times for the unfinished worker13 candidates were not
measured and are not inferred.

## Reproducibility and stopping point

The isolated driver is
[`worker13_profile_sweep.c`](/Users/alex/areas/productive/orchestration/testing/manual_runs/1/research/worker13_profile_sweep.c).
It was compiled against the unchanged `src/dht_asym.c`; no `src/` or `bench/`
file was edited. The live run completed all `(10,30)`, `(11,23)`, and
`(12,20.5)` checks listed above, plus the stated partial `(12,22)` checks,
then was stopped with SIGINT. The `(8,48)` large-N selected-row checks and the
remaining `(12,22)` large-N band checks are intentionally absent.
