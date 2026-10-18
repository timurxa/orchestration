# V2-03 PairWire codec decision

**Decision:** `PairWire` is structural: it carries two child wires and no
codec identity. Its dependent pair type is derived from the exact typed child
witnesses. A consuming Work's input codec handles a pair input; a graph output
pair is reassembled from its already-durable sources.

## Alternatives considered

1. **Keep one exact `PairFamilyRef` per environment and left family.** This
   matches the first draft literally, but a registry entry has type
   `IndexedCodec (dtuple2 env left) right` for one exact `env`. Dynamic graph
   prefixes change the port-environment type, so a finite pinned registry
   cannot supply entries for arbitrary generated prefixes. The codec is also
   not called by `PairWireTyping`; it duplicates the child-derived type.
2. **Keep an identity for a polymorphic pair-codec provider.** A useful
   provider can be composed from the left and right codecs. Persistence is
   handled by the consuming Work's input codec, so a separate provider
   identity in every wire is not needed by the core.
3. **Use structural pair construction.** The left child supplies `A env`; the
   right child is typed at `B env (left_value env)`; the pair witness is
   `dtuple2 (A env) (B env)`. No pair-family package or registry lookup is
   required. Fst/Snd reuse that witness.

The third form has fewer identity sources and supports any finite generated
prefix shape. It does not remove artifact interpretation: when a node accepts
a pair of file handles, resource handles, or other adapter-interpreted values,
the selected Work's input codec owns their serialization/materialization. A
library can provide pair codecs when a concrete adapter needs them. A graph
output pair is reconstructed from its durable sources, not encoded again.

## Proof effect

The graph codec still proves syntax round-trip and canonicality for every
descriptor; the canonical PairWire form is now tag plus two child encodings.
Resolver construction proves the dependent pair family from the children.
This eliminates only pair-codec identity resolution. It does **not** solve
work/constant type transport or the universal edge obligation
`forall env. source_type env == target_input`; V2-03 remains open until those
and generator admission are constructive.

Evidence: the exact `PairWireTyping` constructor in `WorkflowV2.Graph.fst`
builds `Mkdtuple2` from the child evaluations and never invokes the family
codec. The old `pair_family_ref` specialized a codec to an exact environment
type. The independent review artifact is recorded in the V2-03 run log.
