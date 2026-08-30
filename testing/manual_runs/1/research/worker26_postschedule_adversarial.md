# Worker 26 — post-scheduling residual-sign validation

Date: 2026-08-28

## Status

**INCOMPLETE — interrupted before driver output.** The current source and the
retained pre-scheduling object both linked successfully with the retained
independent MPFR driver. The requested K=10, `z0=30`, ratio-4 run was then
started, but it was still running when the user stopped the task. It produced
no completed stdout, exit status, metrics, or full-vector byte comparison.
The K=12, `z0=21` optional run was not started.

## Completed evidence

Current-source build:

```sh
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include research/adversarial_k12.c src/dht_asym.c \
  -L/opt/homebrew/lib -lmpfr -lgmp -lfftw3_threads -lfftw3 -lm \
  -o build/worker26_adversarial_current
```

The comparison build used the retained pre-scheduling object
`/private/tmp/worker25_packaging.Ca56YL/canonical/dht_asym.o` and completed
with the same link warnings only (deployment target newer than the requested
macOS target). The post-scheduling executable was launched as:

```sh
/usr/bin/time -p build/worker26_adversarial_current 10 30
```

The driver source uses `dht_plan_create_profile_ex(..., threads=1, ratio=4)`
and checks the complete vectors at `N=32,64,128,256,512` against its
independent 256-bit MPFR reference. No `src/` or `bench/` files were edited.

## Verdict boundary

Because the run was interrupted before any case completed, this record does
not establish a clean post-scheduling pass, a reproducible numerical failure,
or whether scheduling changed output bytes or errors. The prior archival
reports are not substituted for this requested post-scheduling run.
