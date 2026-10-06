#import "@preview/physica:0.9.8": *

=== A common bounded hypervolume archive

The overall goal is to construct a meta-optimizer $cal(M)$ that maps each
problem $p in cal(P)$ to an orchestration program
$cal(O)_p = cal(M) (p)$.

Both levels use the same construction. For optimization level $a$, let
$cal(X)_a$ be its candidate space, $cal(T)_a subset.eq cal(X)_a$ its finite
tested set, and $n_a$ its quality-vector dimension. Each candidate $x in cal(X)_a$
has raw quality vector
$bold(q)_a (x) in RR^(n_a)$
and binary gate score $g_a (x) in {0, 1}$. Define acceptance by
$ 
  cal(G)_a (cal(T)_a) =
    {x in cal(T)_a | g_a (x) = 1}.
$

Orient all quality coordinates so that larger values are better. Let
$
  bold(z)_a (x) = bold(phi)_a (bold(q)_a (x)) in [0, 1]^(n_a)
$
be the normalized quality vector, with each coordinate map strictly increasing.
For gated candidates $x_i, x_j$, define Pareto dominance by
$
  x_i succ_a x_j <==>
  (forall k in {1, ..., n_a}, z_(a, k)(x_i) >= z_(a, k)(x_j))
    and (exists l, z_(a, l)(x_i) > z_(a, l)(x_j)).
$

The tested nondominated set is
$
  cal(N)_a (cal(T)_a) =
  {x in cal(G)_a (cal(T)_a) |
    exists.not y in cal(G)_a (cal(T)_a), y succ_a x}.
$

Each candidate defines a dominated box from the zero vector
$
  cal(B)_a (x) =
    product_(j=1)^(n_a) [0, z_(a, j)(x)].
$
The dominated region and its scalar hypervolume are
$
  cal(D)_a (A) =
    union.big_(x in A) cal(B)_a (x),
  quad
  h_a (A) = mu_(n_a)(cal(D)_a (A)),
$
where $mu_(n_a)$ denotes $n_a$-dimensional Lebesgue measure.

For archive budget $K_a$, define the bounded representative archive
$
  cal(A)_(a, K_a) (cal(T)_a) in
    arg max_(
      A subset.eq cal(N)_a (cal(T)_a), |A| <= K_a
    ) h_a (A).
$

The full nondominated set $cal(N)_a$ preserves all discovered information;
$cal(A)_(a, K_a)$ is its bounded hypervolume-maximizing representation.

=== Finding solutions to $p$

At the problem level, instantiate the common construction with
$a = p$, $cal(X)_p = cal(S)_p$, $x = s$, and $n_p = N_p$. Thus
$cal(O)_p$ searches the solution space $cal(S)_p$ and returns a bounded archive
$cal(A)_(p, K_p) (cal(T)_p)$ under its compute budget.

=== Finding good $cal(O)$

Let $cal(O)$ be the space of candidate orchestration programs and let
$cal(T)_M subset.eq cal(O)$ be the finite set of programs tested by the
meta-optimizer $cal(M)$. Because $cal(P)$ may be too large to materialize, let
$cal(R)_t subset.eq cal(P)$ be the finite problem portfolio evaluated at time
$t$. For $o in cal(O)$ and $p in cal(R)_t$, let $o (p)$ be the orchestration
program produced for $p$, and define its object-level result by
$
  J_p (o) =
    h_p (
      cal(A)_(p, K_p) (cal(T)_p^f (o (p)))
    ).
$
The meta-level raw quality vector is then
$
  bold(q)_M (o) = (J_p (o))_(p in cal(R)_t)
    in RR^(n_M),
  quad n_M = abs(cal(R)_t).
$
Thus the meta-level is another instance of the common construction, with
$a = M$, candidate $x = o$, and archive budget $K_M$. Its normalized quality
vector is $bold(z)_M (o) = bold(phi)_M (bold(q)_M (o))$, and its bounded archive is
$
  cal(A)_(M, K_M) (cal(T)_M) in
    arg max_(
      A subset.eq cal(N)_M (cal(T)_M), |A| <= K_M
    ) h_M (A).
$

At the meta-level, admissibility means constraint-respecting behavior on the
evaluated portfolio: $g_M (o) = 1$ iff, for every $p in cal(R)_t$, $o (p)$
either produces no response or produces an output satisfying all constraints
specified by $p$. Otherwise $g_M (o) = 0$. Thus only orchestration programs
that behave correctly across the portfolio can enter the meta-level
nondominated set and hypervolume archive.

The complete meta-objective is therefore hypervolume maximization over the
bounded archive of orchestration programs, where each coordinate measures the
hypervolume produced on one problem in $cal(R)_t$. The archive budgets $K_p$
bound solution search within each problem, while $K_M$ bounds the retained
orchestration programs. Any aggregation across successive portfolios
$cal(R)_t$, or any stopping rule for problem generation, is specified separately.

We use a continuous-learning setting: a user submits $p$ to $cal(M)$ and
receives $o (p)$, while the autonomous mechanism proposes additional problems
in a broader useful space $circle(cal(P))$. The generation and evaluation costs
of $o (p)$ are subject to a shared budget $B$. If $epsilon (o; cal(M))$ is the
cost of constructing $o$ and $iota (p; o (p))$ is the cost of evaluating it on
$p$, then an evaluated portfolio must satisfy
$
  epsilon (o; cal(M)) +
    sum_(p in cal(R)_t) iota (p; o (p)) <= B.
$
Global hypervolume guides selection, while failure logs, raw facts, and
provenance provide separate local signals for mutation and feature refinement.

The intended state of $cal(M)$ is a bounded archive of incumbent orchestration
programs, together with the knowledge needed to generate and refine them. This
preserves diverse research directions without requiring a separate incumbent
program for every problem in $cal(P)$. The hyperparameter $K_M$ is likely specific
to $cal(P)$ and can roughly be viewed as the number of niches in $cal(P)$. This
does not mean we have to collapse to $K_M = 1$ if $cal(P)$ is very targeted;
increasing it leads to better diversity, so the definition of a "niche" is specific
to $cal(P)$ and the desire of the user.

POET traditionally evolves ancestor problems (those that are "easier") alongside the
difficult problems. However does this account for meaningful improvement via
backtransfer? The logic is this: if we are solving a problem $p$, our current
orchestration program is $o_i$, we do a run $r_i$, then get history $cal(h)_i$.
With this program we're trying to get better and better at $p$, and so we have a
landscape over all orchestration programs and their $J_p$. We can generate a failure
response in a fairly straightforward manner:
$
  o'_i = "address_failure"(o_i, cal(h)_i, p)
$
which lets us do a very simple form of local optimization. A question is whether we
need a sort of "mutation" mechanism on top of what we do with problems. For
simplicity and computational cost, the goal is to avoid this.

Diversity instead should be done via novel problem generation. Enhanced POET
introduces a very interesting metric, PATA-EC which basically measures the difference
in ordering of performances by systems.

This can be understood by considering what it would mean for a problem to yield a
similar performance ordering for two different problems. If for a space of problems
we define a metric which somehow genuinely measures how semantically similar problems
are, it's reasonable to assume that a small $delta p$ would lead to a small
$delta #h(0em)"score"$. Our overall gole here is to find problems that are genuinely
semantically different, and thus finding a large change in score can potentially be a
good heuristic for this. Something to consider with this model though is that it makes
sense locally, but globally it's not so obvious because the exact notion of "problem
novelty" becomes strained.

Taking a step back, recall that the overarching goal of this mechanism is to get out of
local minima. Semantic feedback empirically seems to converge to a local minimum in the
sense of solution quality. POET takes the approach that it's very difficult or not
really possible to make leaps out of local minima by just looking for a different
solution. Instead, we can make this process much easier by introducing new problems to
solve, which have different optimization landscapes. Thus the local minima of one
problem might not be a minima at all for another problem. Then potentially a solution
of another problem might be a better solution to the original problem, which creates
another avenue for optimization.

From this we can gather that we should slow down the optimization of problems once
we're getting close to a local minimum.

Overall we have a branching (branching because a solution might continue to evolve even
after offshoots have been generated) path through solution space. How do we choose
these branches though? And importantly, we have to remember that different paths are
solving different problems at a given time. Our end goal seems actually relevant to
materialize here so let's go back to the specification of our exact problem.

We want to find the nondominated set of orchestration programs $cal(A)_(M, K_M)$ that
maximizes the hypervolume $h_M$ which essentially takes the hypervolume of the quality
in each problem and take the volume of that. This means that actually the paths of
several programs matter at the same time which is an interesting twist on POET. For
maximization of $h_M$ of course the ideal is to reach a single solution that scores
near-perfectly on all the benchmarks. However this is not realisitic in the slightest.
If we say to simply prevent clustering, then we risk getting an actual very small
hypervolume as solutions are developed to address maximally different problems. If we
say to avoid having "empty space" in the AABB that covers the solutions then we
incentivize clustering very heavily. A nicer overall approach might be to simply
explore undiscovered areas, or simply locally maximize unexplored $h_M$.

Our local adaptations are just optimizing on a single problem so they're likely a
fairly linear path through quality-space and thus not really interacting much with the
broader $h_M$ ideas. However, problem selection is what we can really control. How do
we estimate then which "problem", as it's being solved, would maximize uncovered $h_M$?
For local adaptation to be able to do this effectively we need it to not be at a local
minima at the location of a branch's current particular solver. This just means
choosing a problem that it's not that good at for now but hopefully is not a dead end.
Note that the problems we choose are in general from $circle(cal(P))$.

It's very likely that, due to the high dimensionality of the problem space, that the
direction that best maximizes hypervolume is one that is novel compared to other
explored directions. In general our solutions are embedded in a high-dimensional space
and testing them on various problems is simply projecting them onto that vector. Novel
problem generation overall is expensive but really potentially rewarding. The question
here is sort of, how can we know what's actually in $circle(cal(P))$? The whole point
is this is difficult.

We need to consider uncertainty since evaluation is expensive. LLM feedback is
unreliable, but for evaluations we do have objective ways to measure the _results_ of
generated orchestration systems. Something we need to clarify is whether, when given
a problem set $P$ to optimize, is this actually a problem set given to us or just a
semantic description of one? Since a problem set can probably be generated from a
semantic description, let's say we are actually given $P$. Then we truly can evaluate
orchestration systems objectively, even with limited samples.

Thus when looking at how to apportion resources to problem solving, we can take into
account the rate of improvement on that specific problem, and additionally
transferability. With a formalization of this we can hopefully figure out how to do
this in a concrete way.

=== Bayesian perspective on attacking uncertainty

The target problem set $P$ is given and fixed: for this objective, the earlier
coordinate set $cal(R)_t$ is $P$ and $n_M=|P|$. We seek orchestration programs whose
stochastically generated solutions yield high expected hypervolume on $P$, subject
to a fixed budget. Evaluation, refinement, and problem generation share one
structure: interpret the accumulated evidence, predict an action's outcome, and
update the state after executing it. Compact interpretations approximate information
needed for prediction; they do not replace the evidence.

#let to-define(title, body) = block(
  width: 100%,
  fill: rgb("fff8eb"),
  stroke: (left: 2pt + rgb("c08a38")),
  inset: 9pt,
  radius: 3pt,
  breakable: false,
)[
  #text(weight: "semibold", fill: rgb("825820"))[To define: #title]
  #linebreak()
  #body
]

==== Evidence and score belief

Let $cal(C)_t$ be the catalog of constructed programs, $Q_t$ the auxiliary problems,
and $cal(H)_t$ the complete action history, including execution traces, program
lineage, each lineage's active version, and incurred costs. The persistent state is
$
  S_t = (cal(C)_t, Q_t, D_t, cal(H)_t).
$
An execution $r$ of program $o$ on problem $p in P union Q_t$ produces
$
  s_(o,p,r) = sans(s)_p (o; xi_(o,p,r)),
  quad y_(o,p,r) = J_p (s_(o,p,r)) in (0,1).
$
Solution generation is stochastic; $J_p$ is a deterministic scalar score. The raw
execution records $D_t$ retain $(o,p,r,s_(o,p,r),y_(o,p,r))$. Repeated executions
remain distinct observations. All histories and solutions remain available to the
action procedures, even when their predictors use only derived features.

For each pair, let $theta_(o,p) = (b_(o,p),v_(o,p))$ be its unknown score mean and
variance. Use a beta likelihood for individual scores:
$
  Y_(o,p) | theta_(o,p) ~ cal(Beta)(b_(o,p) kappa_(o,p),
    (1-b_(o,p)) kappa_(o,p)),
  quad kappa_(o,p) = b_(o,p) (1-b_(o,p)) / v_(o,p) - 1.
$
Write its density as $f_(o,p) (y | theta_(o,p))$. For an unrelated pair, initialize
with the proper prior
$
  pi_"base" (b,v) = 1 / (b(1-b))
  quad "for" quad 0 < b < 1, quad 0 < v < b(1-b),
$
and zero elsewhere. This is uniform in the mean and, conditional on the mean,
uniform over feasible variance. It expresses neutrality in these chosen
coordinates; there is no parameterization-independent uniform prior.

#block(breakable: false)[
Let $Theta$ collect score parameters and the latent refinement variables defined
below. Write $Pi_t (Theta)=pi(Theta | S_t)$ for their joint posterior and
$pi_t (theta)$ for its score-parameter marginal. An observed score $y$ updates the
whole joint belief:
$
  Pi_(t+1) (Theta) prop f_(o,p) (y | theta_(o,p)) Pi_t (Theta).
$
]
Execution scores are conditionally independent given $theta$. Initial priors and
child kernels factorize by problem, with no shared latent score parameters across
problems. Parent-informed beliefs couple programs on the same problem, so the joint
posterior need not factorize over programs. Score belief uses the beta likelihood;
traces remain available to the action procedures and predictors.

==== A common action interface

Use sans-serif Greek letters for the action types $k in
{sans(alpha),sans(beta),sans(gamma)}$. For a candidate action $a$ of type $k$, define
$
  bold(x)_(k,t) (a) = psi_k (S_t,a),
  quad M_(k,t) (dif e | S_t,a) approx
    hat(M)_(k,t) (dif e | bold(x)_(k,t) (a)).
$
Here $e$ is the observable outcome, $M_(k,t)$ its full-state predictive law, and
$hat(M)_(k,t)$ a compact approximation including outcome and model uncertainty.
The ansatz is that these features preserve enough information for useful decisions;
they are not assumed sufficient for all future behavior.

The shared update is
$
  S_(t+1) = T_k (S_t,a,e),
  quad B_(t+1) = B_t-c_k (S_t,a).
$
$T_k$ records the outcome, updates catalogs and model beliefs, and recomputes
interpretations from the retained records and derived returns. One action
executes at a time. Lookahead applies this transition to virtual states, preserving
the distinction between predictions and observed evidence. The induced successor-state
law, for any set $U$ of states, is
$
  Q_k (U | S,a) = integral
    bold(1)_(T_k (S,a,e) in U) M_k (dif e | S,a).
$

#table(
  columns: (0.8fr, 2.1fr, 2.1fr),
  inset: 6pt,
  stroke: 0.4pt + rgb("d8dee5"),
  fill: (x, y) => if y == 0 { rgb("edf3f6") },
  [*Action*], [*Outcome and persistent update*], [*Interpretation and prediction*],
  [$sans(alpha) (o,p)$],
  [Generate $s$, score $y=J_p(s)$; retain trace, append data, update $pi_t$.],
  [Score belief and decision relevance; beta posterior predictive for the score.],
  [$sans(beta) (o,p)$],
  [Refine the active version on $p$ using history; advance its lineage and retain code, trace, and versioned data.],
  [Propagate joint lineage belief through the log-odds gain transition; inherit Beta concentration.],
  [$sans(gamma)$],
  [Generate auxiliary $p'$; add to $Q_t$, record trace. Target $P$ stays fixed.],
  [PATA-EC-inspired signatures predict useful behavioral distinctions between problems.],
)

Evaluation and refinement have global constant costs
$c_(sans(alpha))>0$ and $c_(sans(beta))>0$. Generation has positive cost
$c_(sans(gamma)) (S_t,a)$, still unspecified. Refinement and generation produce no
observed score. Generation can improve the target objective through later
evaluation, refinement, and transfer; it leaves the target coordinates unchanged.

Writing $pi_(t,o,p)$ for the corresponding marginal parameter density, the score
component of the evaluation outcome law is already specified:
$
  M_(sans(alpha),t) (dif y | S_t,sans(alpha)(o,p)) =
    (integral f_(o,p) (y | theta_(o,p))
      pi_(t,o,p) (theta_(o,p)) dif theta_(o,p)) dif y.
$
Interpretations are recomputed from execution evidence and action history. Learned
action models also use observed action outcomes and any attributed derived returns.

#to-define[Action models][
  $psi_(sans(alpha))$ and $psi_(sans(gamma))$: exact features and availability.
  $psi_(sans(beta))$: numerical representation of the lineage belief below.
  Full observable-outcome models $hat(M)_(k,t)$, including code and trace summaries,
  remain unspecified. Also the refinement and generation procedures, their history
  inputs, and generation cost; evaluation and refinement costs are constant.
]

==== Refinement along a lineage

A stable identity $ell$ has successive versions
$o_(ell,0) -> o_(ell,1) -> dots$. Refinement uses the active version,
$
  o_(ell,n+1) = "Refine"(o_(ell,n),p,cal(H)_t;zeta),
$
where $zeta$ is fresh generation randomness. The procedure may inspect execution
traces and semantically analyze weaknesses. Its predictor uses a compact lineage
belief as an ansatz for the relevant history. Refinement advances the active
version; previous code and execution records remain version-specific evidence.
Evaluation alone does not advance the version index.

For a sequence refined on the same focal problem $p$, use
$"logit"(b)=log[b/(1-b)]$ and define
$
  z_(ell,n,p) = "logit"(b_(o_(ell,n),p)),
  quad d_(ell,n,p) = z_(ell,n,p)-z_(ell,n-1,p) quad (n>=1).
$
Each lineage--problem pair has persistent parameters
$lambda_(ell,p) in [0,1]$ and $tau_(ell,p)^2>0$. For $n>=1$, use the transition
$
  d_(ell,n+1,p) | d_(ell,n,p),lambda_(ell,p),tau_(ell,p)^2
    ~ cal(N)(lambda_(ell,p) d_(ell,n,p),tau_(ell,p)^2),
$
$
  z_(ell,n+1,p) = z_(ell,n,p)+d_(ell,n+1,p),
  quad kappa_(o_(ell,n+1),p) = kappa_(o_(ell,n),p) = kappa_(ell,p).
$
The expected gain decays through repeated application:
$
  EE[d_(ell,n+j,p) | d_(ell,n,p),lambda_(ell,p),tau_(ell,p)^2]
    = lambda_(ell,p)^j d_(ell,n,p).
$
This is decay of log-odds gain, not of raw-score gain. The first refinement uses
an initial gain prior for $d_(ell,1,p)$. Root performance follows the existing base
prior, transformed into log-odds and concentration coordinates. A prior favoring
small $tau_(ell,p)$ expresses the assumption that gains are fairly predictable.

The child mean and execution variance are
$
  b_(o_(ell,n+1),p) = 1 / (1+exp(-z_(ell,n+1,p))),
  quad v_(o_(ell,n+1),p) =
    b_(o_(ell,n+1),p) (1-b_(o_(ell,n+1),p)) / (kappa_(ell,p)+1).
$
Thus concentration is a shared uncertain parameter, not an independent copy of a
parent estimate; raw variance changes with the mean. $tau_(ell,p)^2$ describes
variation between refinement gains, whereas $v_(o_(ell,n),p)$ describes variation
between executions of one version. The Gaussian transition concerns latent gains;
individual scores retain their beta likelihood.

For $n>=1$, write $L=(z,d,kappa,lambda,tau^2)$ for the current
lineage--problem latent state.
The displayed transition defines $K_(sans(beta)) (dif L' | L)$, with $lambda$ and
$tau^2$ unchanged. The inherited predictive belief is
$
  Pi^-_(ell,p,t+1) (dif L') = integral
    K_(sans(beta)) (dif L' | L) Pi_(ell,p,t) (dif L).
$
Here $Pi_(ell,p,t)$ is the corresponding joint posterior marginal. Its components
are not assumed independent. The full joint extension retains parent--child
dependence; subsequent beta score likelihoods update version performance, latent
gains, concentration, decay, and refinement variation together. Predicted gains
are not counted as observed improvement. No repeated refinements of an unchanged
parent are needed to learn from this sequence.

This propagation is both performance prediction and inheritance. Action value is
derived through future evaluations and decisions, rather than through a separate
fitted child-value model. Birth adds a child and its prior, not an observed latent
performance. Under this compact ansatz, generated code does not itself provide an
additional performance likelihood. Lookahead may use a symbolic child with its
lineage and belief; sampled latent parameters remain hidden from the simulated
policy, which sees only the belief and observable outcomes.

#to-define[Refinement details][
  Proper priors for the first gain, $lambda_(ell,p)$, and $tau_(ell,p)^2$, and their
  numerical joint inference. The numerical summary $psi_(sans(beta))$ and the
  refinement procedure's trace selection and semantic analysis. The transition
  above is for a fixed focal problem: effects on other problems and changes of
  focal problem remain unspecified. Conditioning the transition on actual edit
  summaries is also not yet defined.
]

==== Behavioral interpretation of problems

For generation, use a PATA-EC-inspired interpretation of existing evaluation data:
compare relative program performance on a common reference panel
$cal(C)_"ref" subset.eq cal(C)_t$. One tentative signature is
$
  bold(chi)_t (p) = EE [rho((Y_(o,p))_(o in cal(C)_"ref")) | S_t],
$
where $rho$ is a common rank or relative-performance transformation. The summary
is deterministic given belief, while its underlying signature remains uncertain.
A distance between signatures can inform predicted transition value, reusing
evaluation data without a separate novelty action or a bonus to the objective. A
new problem's signature requires uncertain prediction or evaluation evidence.

#to-define[Problem signatures][
  $cal(C)_"ref"$, $rho$, and the novelty distance: reference-panel updates, missing
  data, and uncertainty. Optional similarity weighting across program versions
  belongs to the interpretation; their identities in $D_t$ are preserved. Priors
  for scores on generated problems and their generation model remain unspecified.
]

==== Predictive hypervolume and sequential decisions

#block(breakable: false)[
For a finite portfolio $A subset.eq cal(C)_t$, let $bold(y)$ contain one realized
score per $(o,p) in A times P$. The existing construction gives
$
  bold(z)_M (o;bold(y)) = bold(phi)_M ((y_(o,p))_(p in P)),
  quad H_M (A;bold(y)) = h_M (cal(A)_(M,K_M) (A;bold(y))).
$
]
This selects the bounded Pareto archive and computes hypervolume deterministically
for the realized scores. The posterior predictive law and its expectation are
$
  p_t (bold(y) | A) = integral
    product_(o in A,p in P) f_(o,p) (y_(o,p) | theta_(o,p))
    pi_t (theta) dif theta,
$
$
  U(A | S_t) = EE [H_M (A;bold(Y)^*) | S_t]
    = integral H_M (A;bold(y)) p_t (bold(y) | A) dif bold(y).
$
The product expresses conditional independence of fresh execution noise; the joint
$pi_t$ preserves lineage dependence. This averages over both execution randomness
and uncertainty about score distributions. Historical repetitions update belief;
they are not extra programs or extra entries in the future realized archive.

Let $cal(F)(S)$ contain the portfolios eligible at stopping, including the empty
portfolio with zero hypervolume, and set
$
  R(S) = sup_(A in cal(F)(S)) U(A | S).
$
With remaining budget $B$, the sequential decision value is
$
  V(S,B) = max {R(S),
    sup_(a in cal(L)(S), c_k (S,a) <= B)
      integral V(T_k (S,a,e),B-c_k (S,a)) M_k (dif e | S,a)},
$
where $cal(L)(S)$ contains available actions and $k$ is the type of $a$.
Stop if no affordable action offers greater continuation value. Approximate
lookahead substitutes $hat(M)_k$ and a tractable continuation-value estimate.
A practical approximation shortlists first actions and averages budget-feasible
sampled rollouts under a cheap, observation-dependent continuation policy.
Replan after each real outcome. Joint sampling avoids separately enumerating every
uncertainty and recursively optimizing all branches. A scalar value predictor, if
used, approximates this continuation value; it is not a second inheritance model.

This retains value of information through the choices made after observing an
outcome. For a fixed portfolio and a score-only belief update,
$EE [U(A | S_(t+1)) | S_t,a] = U(A | S_t)$: learning alone does not increase its
expected hypervolume on average. Evaluation becomes valuable when it changes
portfolio selection or subsequent refinement, generation, and evaluation decisions.
Refinement and generation both create opportunities and affect future information.
Thus all action types use the same continuation objective; an additional novelty
or information bonus is unnecessary.

#to-define[Stopping and lookahead][
  $cal(F)(S)$: portfolio eligibility, including unevaluated children. The displayed
  $H_M$ selects its bounded archive after scores are realized; selecting a fixed
  bounded deployment archive beforehand is a different terminal objective and
  remains a choice to settle. $cal(L)(S)$: candidate actions. Lookahead depth,
  rollout horizon and sample count, continuation policy or value approximation,
  and a finite-horizon condition or positive lower bound on generation cost remain
  to be specified.
  Planning computation is outside the current action-cost budget.
]

#figure(
  image("bayesian-action-flow.svg", width: 100%),
  caption: [Shared evidence informs action predictions and budgeted lookahead.
    One executed action supplies the next outcome and updates persistent state.],
)
