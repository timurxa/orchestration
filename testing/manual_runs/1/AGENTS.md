# Direct uniform-grid discrete Hankel research

Target operator: `y[m] = sum_n x[n] J0(2*pi*m*n/N)`, `m,n=0..N-1`, binary64 complex input/output.

Acceptance gate: against an independent multiprecision reference, normalized L2 <= 1e-13 and scaled Linf <= 1e-12. Time only input-dependent transform work; report reusable setup and memory separately. Primary benchmark is deterministic complex N=65536, with scaling at powers of two.

Build/test commands are documented in `README.md` and `bench/README.md`; the reproducible entry point is `make verify benchmark` once the implementation is integrated.
