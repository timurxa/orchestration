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

At the meta-level, admissibility means correct execution on the evaluated
portfolio: $g_M (o) = 1$ iff $o$ runs correctly on every
$p in cal(R)_t$, and $g_M (o) = 0$ otherwise. Thus only orchestration
programs that execute correctly across the portfolio can enter the
meta-level nondominated set and hypervolume archive.

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


