Your architecture already suggests one important design constraint: **there is no single “work graph.”** Execution dependency, artifact flow, context inheritance, verification, invalidation, retry/control, and human authority are distinct relations that become misleading when collapsed into one arrow type.  Artifacts also have persistent lineage and status independent of tasks, while human decisions create durable control state rather than ordinary worker outputs.  

So strongest alternatives below often choose **one or two underlying phenomena to make perceptually native**, while relegating other relations to inspection modes.

I rejected obvious candidates such as metro maps, conveyor systems, ordinary ecosystems-with-arrows, circuit boards, generic cities, and “rooms with different skins.” They preserve node-link thinking rather than changing representation.

---

# 1. Reaction Vessel

**Core metaphor:** workflow is chemistry. Work happens because compatible materials meet under suitable conditions.

**Mapping**

* work node → reaction
* agent / LLM continuity → catalyst; same catalyst visibly participates in many reactions without being consumed
* artifact → molecule/material, with structural composition and lineage
* dependency → required reactants and reaction conditions
* parallelism → simultaneous reactions throughout vessel
* completion / failure → stable product / failed reaction, unwanted side-product, or stalled intermediate

**Unusually intuitive:** artifact lineage, fan-in, transformation, missing prerequisites. If three artifacts must combine before work can proceed, reaction literally cannot fire until all three exist.

**Interaction model:** user manipulates *conditions rather than edges*: add catalyst, remove reagent, lower activation barrier, isolate a reaction chamber, substitute reactant, or inspect why equilibrium is stuck.

**Why different:** topology becomes secondary. Fundamental objects are **materials and transformations**, not stations.

**Example:** three research agents produce literature evidence, mathematical derivation, and numerical test. These become three molecular fragments. A synthesis reaction will not occur until all three dock; verifier acts as catalyst. Failed verification splits product back into precursor plus “counterexample” fragment.

---

# 2. Polyphonic Score

**Non-spatial**

**Core metaphor:** workflow is music unfolding through time.

**Mapping**

* work node → musical phrase/event
* agent continuity → instrument or recurring timbre
* artifact → motif/theme that can recur, transform, invert, or be quoted
* dependency → musical entry condition: phrase can begin after cadence, cue, or motif occurrence
* parallelism → simultaneous voices
* completion / failure → resolved cadence / unresolved dissonance or broken rhythm

**Unusually intuitive:** concurrency and synchronization. You immediately see one slow voice blocking ensemble while six others continue.

**Interaction model:** conduct workflow. Solo one agent, mute a branch, stretch one task, shift an entrance earlier, loop a troublesome passage, or inspect artifact transformations by highlighting one recurring motif.

**Why different:** no spatial graph traversal. Primary dimensions are **time, recurrence, rhythm, and synchronization**.

**Example:** coding agent holds long bass line while documentation and test agents enter independently. Test failure produces unresolved chord; coding voice repeats modified phrase until verifier cadence resolves it.

---

# 3. Braided Worldlines

**Weird; non-node-link**

**Core metaphor:** persistent entities are strands moving forward through time. Workflow is a braid.

**Mapping**

* work node → event where strands interact, split, merge, or change state
* agent continuity → colored worldline; identity literally cannot disappear
* artifact → separate strand, often born from interaction
* dependency → required meeting/crossing of relevant strands
* parallelism → independent strands advancing simultaneously
* completion / failure → strand terminates in accepted sink / curls backward into retry braid

**Unusually intuitive:** **identity continuity and handoffs**. If same LLM context handles tasks T2, T9, and T17, one uninterrupted strand makes this unmistakable.

**Interaction model:** grab a strand and trace its entire causal history. Cut at any point to fork context. Splice two strands for explicit state merge. Untangle braid to discover unnecessary coordination.

**Why different:** graph nodes cease being primary. **Continuity itself is first-class geometry.**

**Example:** researcher produces artifact strand A. A coding agent intersects it, producing patch P. Verifier intersects P but rejects it; coding strand loops through another interaction while research strand continues untouched.

---

# 4. Geological Stratigraphy

**Core metaphor:** computation leaves sedimentary history.

**Mapping**

* work node → depositional event or geological transformation
* agent continuity → characteristic mineral/texture signature
* artifact → fossil, mineral vein, embedded object
* dependency → lower strata that must exist before later layer can form
* parallelism → contemporaneous strata forming across different regions
* completion / failure → stable layer / fault, erosion surface, or abandoned intrusion

**Unusually intuitive:** provenance, supersession, retries, historical reconstruction, stale state.

**Interaction model:** drill cores through workflow history; peel layers; compare two historical epochs; expose “fault lines” where a later change invalidated earlier work.

**Why different:** normal graph privileges current state. Stratigraphy privileges **irreversible accumulation and historical evidence**.

**Example:** architecture decision forms foundational layer. Five downstream tasks deposit above it. Human later changes requirement -> visible fault slices through those strata; affected work is displaced while unaffected region remains intact.

---

# 5. Deforming Energy Landscape

**Weird**

**Core metaphor:** workflow is a dynamical system moving through potential landscape.

**Mapping**

* work node → basin, saddle point, or transition
* agent continuity → particle trajectory through landscape
* artifact → object that locally reshapes potential
* dependency → energy barrier that drops when prerequisite becomes available
* parallelism → multiple particles traversing landscape
* completion / failure → stable low-energy basin / trapping in metastable state

**Unusually intuitive:** blockers, difficulty, convergence, retries, and local minima.

**Interaction model:** user changes landscape rather than commanding exact routes. Increase budget -> flatten barrier. Add evidence -> open pass. Pin goal -> deepen target basin. Kill bad strategy -> raise its local potential.

**Why different:** neither edges nor explicit routes dominate. Work follows **affordances and constraints encoded as a scalar field**.

**Example:** two approaches to proof descend toward different basins. One gets trapped behind theorem-strength lemma. Its basin visibly becomes metastable; another route acquires evidence, its barrier drops, and agents naturally migrate toward it.

---

# 6. Morphogenetic Embryo

**Weird**

**Core metaphor:** workflow develops like organism from initially undifferentiated structure.

**Mapping**

* work node → differentiation or developmental event
* agent continuity → cell lineage
* artifact → produced tissue, signaling molecule, or organ structure
* dependency → morphogen/signaling threshold
* parallelism → simultaneous organogenesis
* completion / failure → mature functional tissue / malformed region, apoptosis, or regeneration

**Unusually intuitive:** dynamic decomposition. Plans do not need to exist fully at start; substructure **differentiates when local conditions demand it**.

**Interaction model:** adjust developmental signals. Increase verification signal in risky region, inhibit unnecessary specialization, trace lineage of any final structure back to ancestor tasks.

**Why different:** factory presupposes stations. Embryo metaphor treats **task structure itself as emergent**.

**Example:** broad “implement renderer” cell divides into text, clipping, image, and benchmark lineages only after initial analysis reveals them. Clipping lineage later differentiates further when nested regions appear.

---

# 7. Tapestry / Generative Weaving

**Core metaphor:** workflow creates one evolving fabric.

**Mapping**

* work node → weaving operation
* agent continuity → colored thread
* artifact → persistent motif or woven patch
* dependency → required warp/weft structure already present
* parallelism → distant areas woven concurrently
* completion / failure → closed motif / knot, tear, loose end

**Unusually intuitive:** tightly coupled work versus fragmentation. Closely interacting concerns literally form dense weave; excessive indirection creates long wandering threads.

**Interaction model:** pull one thread to see everything depending on one agent/context/assumption. Cut thread to invalidate its contributions. Reweave local patch without rebuilding whole fabric.

**Why different:** unlike braid, objective is not identity through time but **structural cohesion of finished state**.

**Example:** one invariant threads through parser, optimizer, tests, and proof. Highlighting its thread instantly reveals every place where that invariant matters.

---

# 8. Weather System

**Core metaphor:** tasks are atmospheric phenomena driven by pressure, fronts, moisture, and instability.

**Mapping**

* work node → storm cell/front/pressure event
* agent continuity → tracked air mass
* artifact → moisture/energy packet or persistent weather feature
* dependency → atmospheric preconditions
* parallelism → multiple weather systems
* completion / failure → dissipated stable front / runaway storm or stalled system

**Unusually intuitive:** emergent contention, unstable interactions, workload hotspots, and uncertainty.

**Interaction model:** forecast rather than inspect only present state. Toggle simulated futures; inject resources as energy; create high-pressure exclusion zones around protected branches.

**Why different:** execution is presented as **field dynamics**, not discrete paths.

**Example:** ten cheap analysis tasks produce rapidly moving small cells. Three converge around architecture decision and create high-uncertainty storm. Human intervention dissipates it and clears downstream forecast.

---

# 9. Holographic Projection Chamber

**Weird; largely non-spatial graph**

**Core metaphor:** true workflow is a high-dimensional object. Any normal diagram is only one projection.

**Mapping**

* work node → feature of underlying latent object
* agent continuity → one basis/component of object
* artifact → persistent geometric feature
* dependency → visible only under “causal” projection
* parallelism → visible under temporal projection
* completion / failure → coherent / fractured regions

**Unusually intuitive:** impossibility of one perfect graph layout. Different semantics become **orthogonal projections**, not overloaded visual encodings.

**Interaction model:** rotate semantic basis:

* causal projection
* artifact lineage projection
* agent continuity projection
* authority projection
* context-sharing projection
* uncertainty projection

Objects morph continuously instead of switching dashboards.

**Why different:** visualization explicitly admits graph has many incompatible relational dimensions.

**Example:** one cluster looks tightly connected in execution projection but falls apart under context projection, revealing tasks that depend on outputs without needing predecessor transcripts—exactly distinction your architecture makes. 

---

# 10. Orbital Mechanics

**Core metaphor:** workflow is a miniature celestial system governed by attraction and orbital capture.

**Mapping**

* work node → planet/moon/Lagrange region
* agent continuity → spacecraft trajectory
* artifact → payload or satellite
* dependency → gravitational capture condition
* parallelism → many independent trajectories
* completion / failure → stable orbit/landing / escape, collision, unstable orbit

**Unusually intuitive:** cost of context switching and handoffs. Moving persistent agent between semantically distant tasks costs visible “delta-v.”

**Interaction model:** schedule via orbital transfer. Move task timing until cheap transfer window appears; station an agent in orbit around a cluster where its context remains valuable.

**Why different:** unlike factory movement, distance is not decorative—**movement has conserved cost and inertia**.

**Example:** physics-specialist context remains orbiting derivation cluster. Sending it to documentation has huge transfer cost, making cheaper fresh agent visibly preferable.

---

# 11. Go-Like Constraint Territory

**Non-node-link**

**Core metaphor:** execution is gradual occupation of a discrete possibility field.

**Mapping**

* work node → legal move
* agent continuity → stone signature/color
* artifact → persistent shape or territory
* dependency → move legality determined by existing configuration
* parallelism → independent local fights
* completion / failure → secured territory / captured group

**Unusually intuitive:** global consequences emerging from local moves, especially invalidation and resource contention.

**Interaction model:** user does not manipulate arrows. They make or forbid moves, designate protected regions, explore variations, rewind to branch point.

**Why different:** dependency is encoded by **rules of legal state transition**, not explicit relation drawing.

**Example:** architectural choice places a stone that makes several implementation moves legal while making another family impossible. User can examine alternative variation as ghost stones without mutating canonical run.

---

# 12. Immune Repertoire

**Weird**

**Core metaphor:** system treats problems and failures as antigens; agents form adaptive responses.

**Mapping**

* work node → challenge/antigen encounter
* agent continuity → immune clone lineage
* artifact → antibody/memory cell
* dependency → recognition compatibility
* parallelism → polyclonal response
* completion / failure → neutralization / escaped threat or autoimmune response

**Unusually intuitive:** retries and learning from recurring failure modes. Successful handling produces persistent “memory.”

**Interaction model:** inspect repertoire: “What failures can system now recognize?” Promote successful verifier pattern into memory. Suppress overactive agent family producing false positives.

**Why different:** work graph becomes **adaptive competency memory**, not work locations.

**Example:** compiler error family recurs in three branches. First branch requires expensive diagnosis; resolution becomes memory object. Later encounters trigger near-immediate specialized response.

---

# 13. Choreographic Stage / Labanotation

**Non-node-link**

**Core metaphor:** agents are performers executing coordinated choreography.

**Mapping**

* work node → gesture/action phrase
* agent continuity → dancer
* artifact → prop that can change hands
* dependency → cue, contact, or pose prerequisite
* parallelism → ensemble choreography
* completion / failure → synchronized tableau / missed cue or collision

**Unusually intuitive:** delegation, handoff, coordination burden, and idle waiting.

**Interaction model:** scrub performance in time; ghost future movements; reroute a prop handoff; assign understudy; freeze one performer while others continue.

**Why different:** unlike score, primary semantics are **ownership, handoff, synchronization, and embodied action**, not rhythm.

**Example:** research agent hands evidence prop to implementation agent, but retains its own context. Verification agent enters only after patch prop reaches center stage.

---

# 14. Origami State Space

**Weird**

**Core metaphor:** workflow is repeated folding of one high-dimensional sheet.

**Mapping**

* work node → fold/transformation
* agent continuity → crease family/signature
* artifact → emergent geometric feature
* dependency → folds physically possible only after prior folds
* parallelism → commuting folds on independent regions
* completion / failure → target form / impossible or self-intersecting configuration

**Unusually intuitive:** path dependence and irreversible commitments.

**Interaction model:** unfold partially. Ask “which decisions made current state possible?” Compare alternate fold sequences that reach equivalent output. Detect two operations that commute because their regions do not interfere.

**Why different:** graph is represented by **reachable state manifold**, not by connectivity.

**Example:** choosing data representation early folds design space. Later API requirement reveals target impossible without unfolding that decision; UI visually shows exactly which downstream folds must be undone.

---

# 15. Spectrogram / Interference Field

**Non-node-link, weird**

**Core metaphor:** work is signal energy distributed over time and semantic frequency.

**Mapping**

* work node → localized pulse
* agent continuity → persistent frequency/timbre band
* artifact → recurring harmonic signature
* dependency → phase-lock or resonance condition
* parallelism → superposed frequencies
* completion / failure → coherent resonance / destructive interference or noise

**Unusually intuitive:** duplicated work, agent agreement/disagreement, and coordination overhead.

**Interaction model:** filter frequencies, isolate one agent, detect correlated duplicated reasoning, “notch out” noisy retry loops, identify emergent synchronized activity.

**Why different:** individual tasks can disappear at overview scale. User perceives **patterns of computation statistically**, similar to listening to workload.

**Example:** four agents independently exploring effectively identical strategy produce strong redundant frequency band. UI reveals duplication instantly despite different task wording.

---

# 16. Double-Entry Work Ledger

**Non-spatial**

**Core metaphor:** every operation must balance semantic accounts.

**Mapping**

* work node → transaction
* agent continuity → account/operator signature
* artifact → durable asset
* dependency → liability/obligation that must be discharged
* parallelism → concurrent independent journals
* completion / failure → balanced close / unresolved liability or reconciliation error

**Unusually intuitive:** obligations, verification debt, assumptions, budgets, and unresolved handoffs.

**Interaction model:** query “show all unpaid obligations created by artifact A” or “what work claims completion but still carries verification liability?”

**Why different:** representation is not geometric. It exposes **conservation and accountability**.

**Example:** worker produces patch asset but simultaneously incurs test obligation and API-compatibility obligation. Task cannot truly close until corresponding verification entries zero them out.

This maps particularly well onto structured handoffs containing artifact + evidence + unresolved issues rather than treating output production as completion. 

---

# 17. Living Manuscript / Palimpsest

**Core metaphor:** entire orchestration is one manuscript continuously annotated by many hands.

**Mapping**

* work node → edit, annotation, deletion, commentary, or illumination
* agent continuity → handwriting/ink style
* artifact → textual/diagrammatic object embedded in manuscript
* dependency → reference, marginal mark, or unresolved annotation
* parallelism → simultaneous writing on different leaves
* completion / failure → accepted clean passage / struck-through or disputed passage

**Unusually intuitive:** claims, assumptions, revisions, supersession, and human decisions.

**Interaction model:** time-scrub any region; reveal erased undertext; accept/reject marginalia; promote annotation into canonical body; view one agent’s handwriting everywhere.

**Why different:** unlike geological strata, history remains **semantically editable and argumentative**, not merely accumulated.

**Example:** mathematical lemma begins as pencil hypothesis, gets red verifier annotations, gains numerical evidence in margin, then is inked into canonical manuscript.

---

# 18. Storyworld / Dramatic Causality

**Core metaphor:** workflow is represented as evolving narrative, not infrastructure.

**Mapping**

* work node → scene/event
* agent continuity → character
* artifact → object, clue, or knowledge carried through story
* dependency → narrative precondition
* parallelism → intercut storylines
* completion / failure → resolved arc / failed quest, contradiction, unresolved subplot

**Unusually intuitive:** “why does this task exist?” Every task needs narrative motivation from goal/constraint.

**Interaction model:** inspect character arcs, unresolved plot threads, Chekhov’s guns (artifacts created but never used), deus-ex-machina events (tasks without justification), or alternate endings.

**Why different:** makes **goal justification and scope drift** perceptual rather than structural.

**Example:** side branch keeps spawning work but contributes to no final objective. It appears as increasingly long subplot with no connection to central arc—strong visual warning of scope drift.

---

# 19. Quantum-Like Branching State

**Weird; non-spatial**

Not claiming physical quantum equivalence—the metaphor uses superposition and collapse deliberately.

**Core metaphor:** unresolved alternatives coexist as weighted possibilities until evidence eliminates or selects them.

**Mapping**

* work node → operation on candidate-state amplitudes
* agent continuity → labeled evolution operator/history
* artifact → information correlated across alternatives
* dependency → prerequisite condition for branch amplitude
* parallelism → literal coexistence of alternatives
* completion / failure → branch selected / amplitude reduced to zero

**Unusually intuitive:** speculative work, uncertainty, alternative hypotheses, and delayed commitment.

**Interaction model:** user can keep alternatives “uncollapsed,” allocate compute according to branch weight, ask verifier to eliminate branches, or let human decision collapse only semantic choice while independent branches continue.

**Why different:** normal graphs materialize every branch as equally real. This depicts **degree of commitment** as primary state.

**Example:** three implementation strategies exist at 0.50, 0.35, 0.15 plausibility. Cheap experiments annihilate one; benchmark shifts weights; architecture choice remains unresolved until user commits.

---

# 20. Cellular Automaton / Local Rewrite Language

**Abstract new visual language**

**Core metaphor:** no explicit graph exists onscreen. There is a field of typed glyphs governed by local rewrite rules.

**Mapping**

* work node → rewrite rule firing
* agent continuity → persistent moving token/state marker
* artifact → stable glyph structure
* dependency → pattern match required before rewrite becomes legal
* parallelism → simultaneous independent rewrites
* completion / failure → stable normal form / oscillation, deadlock, or forbidden pattern

**Unusually intuitive:** execution semantics themselves. Waiting means no applicable local rule. Retry means repeating rewrite family with changed local state. Deadlock is visually obvious as frozen nonterminal pattern.

**Interaction model:** edit rewrite laws, seed tokens, step execution, run continuously, inspect why a rule is disabled, or prove local invariants.

**Why different:** this is not visualization *of* work graph. It is potentially a **visual programming language whose execution is graph orchestration**.

**Example:** `[artifact][ready-task][agent]` locally rewrites into `[artifact][running-task(agent)]`; later result creates two output glyphs, immediately enabling two distant rules in same tick.

---

# Five strongest directions

## 1. Braided Worldlines — exposes **continuity**

Most orchestration UIs make persistent agent identity incidental metadata. Braid makes it fundamental. Context forks, continuation, handoffs, merges, and repeated intervention become geometric operations.

Especially valuable because your system cares about persistent contexts but does not want to confuse task identity with agent identity.

## 2. Reaction Vessel — exposes **artifact-driven causality**

This may fit architecture best. Your agents act against shared artifacts, and structured artifacts persist independently from task conversations.  Chemistry naturally says:

> Work becomes possible when required state exists.

Not “because arrow points here.”

It could make fan-in, transformation, verification, missing input, provenance, and side effects unusually legible.

## 3. Holographic Projection Chamber — exposes **multiplicity of graph semantics**

Probably strongest answer to fundamental visualization problem.

No layout can simultaneously optimize:

* task dependency,
* artifact provenance,
* context flow,
* agent continuity,
* invalidation,
* human authority,
* temporal execution.

Instead of fighting this, make **semantic projection itself interaction primitive**.

This aligns directly with architectural reason for separating those edge types. 

## 4. Energy Landscape — exposes **execution pressure and convergence**

Normal DAG shows what *may run*. It poorly conveys why system is stuck, which path is attractive, how expensive alternatives are, or whether several agents are converging toward same solution.

Landscape turns:

* difficulty,
* uncertainty,
* resource allocation,
* blockers,
* local minima,
* convergence

into immediate shape.

## 5. Work Ledger — exposes **obligation and correctness debt**

Least visually spectacular, possibly one of most valuable.

Work systems often confuse “produced result” with “finished task.” Ledger can encode:

[
\text{result creation}
\neq
\text{obligations discharged}.
]

Every assumption, verification need, unresolved decision, budget expenditure, and downstream promise remains visibly outstanding until reconciled.

This is particularly compatible with explicit verification policies and human-controlled goal changes in your architecture. 

---

# Three hybrids

## Hybrid A — **Reaction Manifold**

### Reaction Vessel × Energy Landscape

Instead of reaction network drawn as arrows, entire environment is free-energy landscape populated with reactants and catalysts.

A transformation requires both:

1. correct artifacts to meet;
2. enough activation energy/resource/authority to cross barrier.

This creates new interaction model:

* artifacts reshape landscape;
* stronger model = more energetic catalyst;
* verifier lowers barrier to canonical promotion;
* uncertainty raises barrier;
* human approval opens otherwise forbidden saddle;
* repeated failure can carve alternate reaction pathway;
* cheap agents naturally handle low-barrier work while expensive agents become worthwhile only at high barriers.

You could literally visualize routing policy as physics.

**Unique value:** unifies **state availability + computational difficulty + model allocation**.

---

## Hybrid B — **Braided Score**

### Braided Worldlines × Polyphonic Score × Choreography

Horizontal axis = time.

Agent contexts are persistent strands/voices. Artifact motifs appear on strands, then transfer between them. Simultaneous tasks form chords. Handoffs are crossings. Human intervention is conductor cue. Waiting is held note. Retry is repeated phrase.

Unlike normal timeline, you can grab context strand and:

* fork it into two voices,
* merge branches,
* delay one entrance,
* substitute agent,
* preserve one voice while rewriting another,
* hear/see synchronization problems.

At high zoom: overall rhythm of operation.
At medium zoom: agent continuity.
At low zoom: individual task/handoff semantics.

**Unique value:** unifies **time + concurrency + agent identity + handoff** without node-link graph.

This feels especially plausible as alternative to factory for persistent-context visualization.

---

## Hybrid C — **Holographic Stratigraphy**

### Holographic Projection × Geological Stratigraphy × Living Manuscript

Underlying workflow is immutable event/provenance history.

User first moves through **time layers**:

* what existed yesterday?
* what became invalidated?
* where did branch diverge?
* which assumptions were canonical at this point?

Then rotates semantic projection of selected historical slice:

* execution dependencies,
* artifact lineage,
* human authority,
* context inheritance,
* verification,
* uncertainty.

Finally, within selected feature, palimpsest mode exposes edits, rejected hypotheses, raw evidence, and replacement artifacts.

This gives interaction unavailable to graph UI:

> “Show system exactly as it existed before decision D17, project only artifact provenance, then reveal everything downstream that would change if D17 were replaced.”

**Unique value:** unifies **history + multidimensional semantics + counterfactual inspection**.

---

## A direction I would investigate first

Not one representation for everything.

I would experiment with **two complementary perceptual regimes**:

**Operational view:** Braided Score or Reaction Manifold
→ what is happening, what is waiting, who retains context, what can fire next.

**Structural/debugging view:** Holographic Stratigraphy
→ why state exists, where it came from, what would invalidate it, which semantic relation is being inspected.

Factory concept remains potentially strong as explorable “world” view, but these representations expose properties factory has trouble making native:

[
\begin{array}{c|c}
\text{Representation} & \text{native phenomenon}\
\hline
\text{Factory} & ownership/location/activity\
\text{Braid} & identity continuity\
\text{Chemistry} & artifact transformation\
\text{Score} & temporal concurrency\
\text{Landscape} & difficulty/convergence\
\text{Stratigraphy} & provenance/history\
\text{Ledger} & obligations\
\text{Hologram} & multiple relation systems\
\text{Quantum-like} & unresolved alternatives\
\text{Rewrite field} & executable orchestration semantics
\end{array}
]

Most interesting design space may therefore be **not finding better substitute for graph**, but letting work graph have several perceptually incompatible representations and making transformations between those representations smooth enough that user builds one coherent mental model.
