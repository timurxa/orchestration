# Worker 21: bounded C micro-optimization screen

Date: 2026-08-28
Target: Apple arm64 / Apple clang 21, `N=65536`, `threads=10`, `ratio=4`
Scope: `src/dht_asym.c` only; no changes were made to `src/` or `bench/`.

## Result

**PASS — recommend the direct-row geometric-band task partition.** It preserves
the existing per-row Kahan summation and only changes which disjoint rows are
run by each dispatch task. Four alternating process runs reduced the benchmark
median from a median-of-medians of **29.729 ms** to **18.562 ms** (**37.6%
less input-dependent transform time**). Setup and memory were unchanged in
kind: setup was about 0.676–0.737 s and `plan_bytes=74849360` for both.

The scale-layout candidate is a **no-go**: three paired runs ranged from 2.5%
faster to 1.9% slower, with median 27.739 ms for the current layout versus
28.215 ms for q-to-m layout. There is no reproducible gain.

## Candidate tested

Current `add_direct_rows` divides the row index range into `threads * 4`
equal-row tasks. Direct work is not row-uniform: `row_length[m]` is constant
within the existing geometric bands induced by `block_ratio`, so the first
equal-row task receives most of the direct entries. The tested candidate:

1. counts those geometric bands;
2. uses at most one task per configured worker; and
3. maps each task to contiguous groups of complete geometric bands.

No row is split, and the inner loop—including Kahan operation order—is
unchanged.

The rejected candidate stored `scales` m-major and read `scales[m*terms+q]`
instead of the current q-major layout. It changed only storage/access order,
not arithmetic.

## Exact build and run commands

All temporary files were under `/private/tmp/worker21.yuWuoz`; the source
copies were disposable A/B variants.

```sh
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include -c src/dht_asym.c \
  -o /private/tmp/worker21.yuWuoz/current.o
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include bench/benchmark.c \
  /private/tmp/worker21.yuWuoz/current.o \
  -L/opt/homebrew/lib -lfftw3_threads -lfftw3 -lm \
  -o /private/tmp/worker21.yuWuoz/current_benchmark

clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -Isrc -I/opt/homebrew/include -c \
  /private/tmp/worker21.yuWuoz/direct_bands.c \
  -o /private/tmp/worker21.yuWuoz/direct_bands.o
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include bench/benchmark.c \
  /private/tmp/worker21.yuWuoz/direct_bands.o \
  -L/opt/homebrew/lib -lfftw3_threads -lfftw3 -lm \
  -o /private/tmp/worker21.yuWuoz/direct_bands_benchmark

/private/tmp/worker21.yuWuoz/current_benchmark \
  65536 31 5 1e-13 10 10 30 4 0
/private/tmp/worker21.yuWuoz/direct_bands_benchmark \
  65536 31 5 1e-13 10 10 30 4 0
```

The four alternating A/B outputs were:

| run | current median | banded median | reduction |
|---:|---:|---:|---:|
| 2 | 29.866 ms | 17.332 ms | 41.9% |
| 3 | 28.525 ms | 17.363 ms | 39.1% |
| 4 | 30.732 ms | 20.780 ms | 32.4% |
| 5 | 29.591 ms | 19.761 ms | 33.2% |

The first exploratory banded run was 21.245 ms versus 27.739 ms current.
Reported checksums matched to the shown digits in most paired runs; the
remaining difference was only in the final shown digits, and independent
baseline process runs also showed that one-ULP-level variation. The banded
change cannot reorder arithmetic within any output row.

The independent accuracy harness was also built and run for both objects with:

```sh
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include bench/accuracy.c \
  /private/tmp/worker21.yuWuoz/current.o \
  -L/opt/homebrew/lib -lmpfr -lgmp -lfftw3_threads -lfftw3 -lm \
  -o /private/tmp/worker21.yuWuoz/current_accuracy
clang -O3 -DNDEBUG -std=c11 -Wall -Wextra -Wpedantic \
  -I/opt/homebrew/include bench/accuracy.c \
  /private/tmp/worker21.yuWuoz/direct_bands.o \
  -L/opt/homebrew/lib -lmpfr -lgmp -lfftw3_threads -lfftw3 -lm \
  -o /private/tmp/worker21.yuWuoz/direct_bands_accuracy

/private/tmp/worker21.yuWuoz/current_accuracy 65536 1e-13 10
/private/tmp/worker21.yuWuoz/direct_bands_accuracy 65536 1e-13 10
```

Both completed without a reported diagnostic in the bounded run; the harness
emitted no metric text in this environment. No further experiments were run.

## Recommendation

Integrate only the geometric-band direct-row scheduling change into
`src/dht_asym.c`, then run the repository’s normal `make verify benchmark`
gate. Do not integrate the m-major `scales` layout based on this screen.
