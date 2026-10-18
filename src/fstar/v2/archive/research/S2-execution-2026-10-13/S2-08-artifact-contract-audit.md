# S2-08 P9 artifact and resource audit

Read-only independent review of P9 in `implementation_spec.md` and
`key_correctness_theorems.md`; no F* source was changed.

## Gap

`ArtifactRef` was unindexed and abstract, events stored untyped lists, and
“same typed object” had no defined relation. P9 therefore could not prove the
stated resource-identity result from the current declarations.

## Required contract

- A reference is typed or existentially packaged with a pinned artifact-type,
  schema, canonical reference-codec, and store identity. Its stable logical
  identity includes an immutable version; exact byte layout remains open.
- A typed resource codec/schema supplies a canonical projection enumerating
  every resource reference in a typed value. The event artifact manifest is
  exactly that projection; it cannot omit a reference, add a conflicting one,
  or become a second authority.
- An authorization witness proves every newly published reference's complete
  backing object is durable before the journal append linearization point.
  Crash after publication but before append may leave an unreachable orphan.
- At every supported restart, resolving a committed reference under the
  pinned store and codec returns a handle denoting the same typed logical
  object and immutable version. This means same logical resource, not the
  same OS pointer or process-local handle.
- A reachable version cannot be overwritten, deleted, or reused for different
  contents. Publication is idempotent or rejects conflicting reuse. Concurrent
  resolution after event commit sees a complete object, never a partial tree.
- Replay checks only canonical reference syntax and pinned type resolution; it
  does not query the external artifact store. P9 physical witnesses are
  carried in `SemWF` and checked before append. P15 exposes references to
  consumers only after commit; P10 remains a journal-prefix theorem.

Immutable files, BlobTrees, and object-store snapshots fit the general law.
Mutable databases or network sessions must pin a snapshot/version or supply a
durable reopen/continuation relation. A socket or cursor cannot be promised to
survive as the same process-local handle.
