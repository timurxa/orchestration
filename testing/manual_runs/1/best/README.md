# Validated winner

The winner is the product-safe ratio-4 blocked asymptotic/FFT transform. The
canonical implementation is [`src/dht_asym.c`](../src/dht_asym.c), with its
public API in [`src/dht.h`](../src/dht.h). The forwarding files in this
directory make the selected implementation easy to consume while preserving
the repository's `best/` and `src/` sibling layout:

- `best/dht_asym.c` includes the canonical implementation.
- `best/dht.h` includes the canonical public header.

For the target `tol=1e-13`, the retained profile is `terms=10`, `cutoff=30`,
and `block_ratio=4`; use `dht_plan_create(n, 1e-13, threads)` for the default
or `dht_plan_create_profile_ex` to select it explicitly. The validated
accuracy claim is empirical and applies to this release profile; the public
`tol` argument selects a conservative built-in profile but is not a general
formal error guarantee.

The supported C entry points are `dht_plan_create`, `dht_apply`,
`dht_plan_destroy`, and the read-only metadata accessors. The two profile
constructors are experimental tuning interfaces. A repository-layout build is:

```sh
cc -O3 -DNDEBUG -std=c11 -I/opt/homebrew/include \
  -Ibest -c best/dht_asym.c -o dht_asym.o
```

Link `dht_asym.o` with `-L/opt/homebrew/lib -lfftw3_threads -lfftw3 -lm`.

The plan is reusable for sequential calls. Input and output arrays must not
overlap, and concurrent calls on one plan are unsupported because the FFT
scratch is shared.
