# S2-08 P8 charge and fuel audit

Read-only independent review of the S2-08 charge/fuel contract in
`implementation_spec.md`; no F* source was changed.

## Result

The allocation and settlement arithmetic composes under the existing guards.
Root plans fit the initial totals; `GraphCommitted` replaces one generator's
pool by bounded child pools; `CallIntent` reserves the exact external maximum;
`CallOutcome` settles the reservation once; and fuel is derived from committed
plans. Serial journal appends make each ledger transition atomic, so arbitrary
completion order does not change conservation.

## Required clarifications

1. **One charge unit:** all charges are `nat`, but the spec did not say whether
   one operation reports tokens and another money. Add one pinned
   `ChargeMetricIdentity` to `RunBudget` and every operation package. An
   operation maximum, receipt charge, and nested charge pool must all use that
   run's metric. A future vector ledger is possible, but is not needed for the
   minimal scalar system.
2. **Derived ledger projections:** state that totals, `allocated`, `reserved`,
   `spent`, and `free` are exact projections from the pinned budget, canonical
   occurrence maps, and committed settlements. They are not separately
   mutable sources of truth. The same applies to fuel totals and projections.
3. **Static allocation policy:** unused charge returned to `free` and root
   fuel left unassigned remain unallocated; no later action draws from them.
   A generated graph can use only its already committed parent pool. Thus “no
   budget-blocked action” means every action in a valid admitted plan fits its
   committed allowance.
4. **Safe arithmetic:** root-plan, graph-plan, and receipt inequalities are
   checked before natural subtraction: `A_c <= total_charge`, `C <= c`,
   `sum(child_fuels) <= b`, and `q <= maximum_charge`.
5. **Theorem split:** P3/P4 establish deterministic replay and allocation
   transition premises; P7 proves a reported receipt charge is truthful and
   bound to the logical call; P15 proves once-only serialization under
   concurrent completions. P8 proves aggregate conservation and composes these
   claims.

P8 accounts only for the declared charge metric and graph-expansion fuel. It
does not claim to meter CPU, memory, wall time, retries, or other resources
that are not represented by these ledgers.
