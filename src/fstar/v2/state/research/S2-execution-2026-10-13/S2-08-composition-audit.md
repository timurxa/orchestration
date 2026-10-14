# S2-08 P8/P9 composition audit

Read-only review of S2-08 dependencies against S2-04 through S2-07 and
P10/P15/P16; no source changes.

P8 composes with S2-04 plan bounds, S2-05 deterministic event transitions,
S2-06 serial append authorization, and S2-07 receipt settlement. No parallel
journal writes or extra work primitive are needed. P7 owns truthful adapter
charge; P8 owns conservation and one-time settlement.

P9 is orthogonal to logical replay. Keep P3 replay independent from external
store availability: it validates canonical reference syntax and type
metadata, while P9 authorization witnesses establish publish-before-commit
and post-restart resolution. P10 proves exact journal prefixes and needs no
change. P9 remains optional for the base logical P16 theorem, and is required
when the composite theorem claims stable physical-resource identity.

The P15 candidate/append path must carry or rebuild the P9 publication
witness. P15 exposes a reference to dependent work only after its event
commits. P11/P14 may add resource-store progress premises only for workflows
whose enabled work actually needs resource resolution.
