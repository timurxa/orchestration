#let gradient = $nabla$

- It's bad to pretend agent will do things perfectly, interface should be designed for good human guidance
- Self improvement is mandatory. Editing prompts, etc, should be done within a session and partially persist to future sessions as well
- More derived autonomy
- Self improvement is essential and in fact all problems should be recorded and be used to learn from
- Need to narrow down infinite dimensional action space to finite dimensional options
- Moving away from DAG is still mildly questionable, wouldn't be surprised if the structure still exists somewhere
- Token usage limits are definitely good and something that should be cared about more
- Need to think about human intervention substrates
- POET seems quite interesting
- Use automated theorem proving systems as references
- QD reasoning archive is just a fairly simple way to keep multiple unique families alive, but still requires extra pruning and such
- Catalyst idea is actually interesting because it improves stigmergic communication
  - Neural cellular automata approaches this via local signals and such
- Stigmergic decaying artifact field for information storage and management
- Artifact hypergraph local rewrite might be part of scheduler
- Failure detection
- Parallel tempered reasoning replicas might be an interesting consideration
- Epistemic value should be counted
- sequential monte carlo strong scheduler yes
- useful human interaction substrate still important
- backprop

A given orchestration system $cal(O)$ is in state $q_n$ and advances $q_n -> q_(n + 1)$ until reaching a final state $q_f$ from an initial state $q_i$. The initially given human prompt is just encoded via the initial state $q_i$, and human modifications are similarly just changes of state.

Technically, if we only care about improving a system, we do not need to handle our own value vector $cal(V)$ if for example an LLM can determine the gradient for us. However this is prone to issues and the lack of specificity immediately discards this approach.

Then, should $cal(V)$ be of the same structure for every problem? The benefits of having this consistency is easy comparison between multiple problems. However if for example the problem is some math research and we want to see if it succeeded more via proving a theorem, gaining genuine deeper knowledge, etc, those are different criteria than if code structure fits a certain desired architecture for a code synthesis problem. Thus, $cal(V)$ will be of a different shape for every problem. This means it also has additional semantic data attached to it.

We can denote an orchestration system $cal(O)_alpha$ as one with hyperparameters $alpha$. Then essentially we're doing gradient descent:
$
  alpha_(n + 1) = alpha + eta dot.o gradient_alpha cal(V)
$
which clearly uses very abstract notions of multiplication and differentiation, as some of the hyperparameters are prompts, which do not have a standard notion of multiplication on them.

So what is the actual system we will use? Our prompts are mostly difficult research or engineering type problems, and thus we need some sort of mechanism for proposing, testing, choosing solutions. We also want to have token restrictions, at the very least on the granularity of a single run. Human input is again also important.

Human input is important partially because we want to make sure the model isn't destroying our computer, but it also may genuinely be a blocker. If the model realizes it doesn't actually know what it's doing then that's going to lead to huge issues. Essentially this is an alignment problem.

Going guns blazing and detecting misalignment is token expensive and not really a scalable solution. Instead, having authority data which tells the model what it can and can't do is almost certaily the best path forward. This can be tuned via the top level optimizer, which also means the top level optimizer is going to need human input.

To get rid of this multilayer structure, perhaps the top level optimizer should just be viewed as a run of this model? It wouldn't really be that hard; the same diagnostic data that the model saves as it runs is just passed to itself and it makes the right changes. Seems like most consistent path forward. Idk we'll see.

Authority doesn't just mean what files can be edited, it defines what decisions have been made by the user and what decisions the model itself needs to make. This is basically also an instruction clarification. This part is relatively the same from my work graph implementation idea, which isn't particularly surprising since it's a fairly basic assumption.

So human intervention is needed if the model needs to make a decision outside of its authority (underspecification) or finds a contradition. This blocks that and its dependencies. So in the final orchestration system we will still have something that lets us have human input, which is again not surprising because it's a fairly generic concept.

Knowledge persistence is an important topic. Really though, a stigmergic artifact graph seems like the first basic storage unit. It should just be a DAG and be pretty pointer heavy.

Any sort of idea selection or refinement algorithm needs to incorporate the fact that research probably needs to be done even before plan generation. So to even start having a bunch of candidates to allocate tokens between, a lot of choices need to be made. However something we're going to do here is say that the entire structure is not going to be recursive, and will in fact have proper controls. This will make hyperparameter optimization and token control easier.

We're going to go for a modified tree search algorithm. We need an initial tree search size. We'll call $m_0$ the initial branching amount. 
