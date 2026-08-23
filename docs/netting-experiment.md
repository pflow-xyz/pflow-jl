# Netting experiment: a ρ > 1 observer glued onto the Settle cycle

Test file: `test/test_netting.jl` (run with
`julia --project=. -e 'using pflow, AlgebraicPetri; include("test/test_netting.jl")'`).
Every claim below names the testset that checks it. The categorical statements
it exercises are in the book's Appendix E ("Net Types as Sub-SMCs", "Where the
Free Structure Stops", "The 2-Categorical View"). Conventions: incidence
matrix `C` is places × transitions, a P-invariant is `yᵀC = 0`,
`ρ(t) = |pre(t)| / |post(t)|`.

## The nets

Baseline is the three-party Settle cycle of `test/test_algebraic.jl`: channels
`a→b`, `b→c`, `c→a`, each `x --send_xy--> pending_xy --settle_xy--> y`, glued
by pushout along the shared balance places. 6 places, 6 transitions, a timed
event graph with the single invariant `ones(6)`.

The observer is one transition, `net_abc`, consuming `pending_ab`,
`pending_bc`, `pending_ca` and producing **one** token into a new place
`cleared` (`netting_part()`). So `ρ(net_abc) = 3` — testset **"netting
part"**.

*Why `cleared` and not credits to the balances:* a full cycle of equal
obligations nets to zero, nobody is owed anything, so the honest post-set is a
single "this cycle was cleared" receipt. Crediting `a`, `b`, `c` instead would
just be three more `settle_*`-shaped transitions, each with `ρ = 1`, and the
composite would stay an event graph — there would be no experiment. A sink
with `ρ = 3` is exactly the verdict-transition cell of Appendix E's table.

## (2) Composition along places — testsets "composite shape", "P-invariants", "event graph breaks"

`glue` composes the four parts along shared **place names**; the netting
part's ports are the three `pending_*` places, which are also added to the
channels' port lists so the pushout identifies them.

| | cycle | cycle + netting |
|---|---|---|
| `ns` | 6 | 7 (`+cleared`) |
| `nt` | 6 | 7 (`+net_abc`) |
| `is_event_graph` | true | **false** |
| left-nullspace dimension of `C` | 1 | 1 |
| invariant | `a+b+c+p_ab+p_bc+p_ca` | `a+b+c+p_ab+p_bc+p_ca + 3·cleared` |

**Which P-invariants lift.** The left nullspace is computed with an exact
Gauss–Jordan over `Rational{BigInt}` (`left_nullspace`, no dependencies beyond
`Base`). Findings, all in **"P-invariants"**:

- *Extension by zero does not lift.* A channel's own invariant
  `a + b + pending_ab` is an invariant of the channel and **not** of the
  composite (`b` is consumed by `send_bc`). Likewise the cycle's `ones(6)` is
  **not** an invariant of the netting composite — `net_abc` turns three tokens
  into one.
- *Restriction does lift, downward.* The composite's single invariant
  `(1,1,1,1,1,1,3)` restricted to the places of every part — each channel, the
  netting part, and the whole cycle — is an invariant of that part. This is
  the precise content of Appendix E's "P-invariants of a component are still
  derivable from the composite's incidence matrix": a part's transitions only
  touch the part's places, so any composite invariant restricts to a part
  invariant; the converse (part → composite) is false.

**Which places break the event graph** (**"event graph breaks"**): exactly
`pending_ab`, `pending_bc`, `pending_ca` (each now has **two consumers**,
`settle_*` and `net_abc`) and `cleared` (one producer, **zero consumers** — a
sink). The balances `a`, `b`, `c` are untouched. This is the ρ boundary in
the concrete: the fan-in transition alone is what removes the "one producer,
one consumer per place" property, and the ODE will treat `cleared` as a sink.

## (3) Gluing along a transition — testset "transition gluing"

- **AlgebraicPetri's `Open` is species-only.** `Open(net, [:t])` with a
  transition name raises `KeyError` because legs are looked up in `snames`
  only; every `Open` method in AlgebraicPetri 0.9.2 is built on
  `OpenACSetTypes(…, :S)`.
- **Catlab can do it anyway.** `OpenACSetTypes(LabelledPetriNetUntyped, :T)`
  is legal — Catlab's condition is that the sub-schema has no *outgoing*
  arrows, and `T` has none (`I` and `O` point *into* `T`). Building cospans
  with transition feet and composing with `oapply` yields a pushout that
  **fuses the two transitions into one** with the union of their pre- and
  post-sets: `t : x + q → p + y`. That is a synchronisation — Appendix E's
  EventLink — and it keeps `ρ = 1` and both local invariants. So transition
  gluing is expressible; it is just not wrapped by AlgebraicPetri.
- **The place-only workaround** splits the shared transition into
  `t_A → iface → t_B` and glues along the interface *place* with the
  existing `glue`. What it changes, each checked:
  - `+1` place, `+1` transition;
  - the synchronisation becomes two asynchronous steps: the split net
    reaches 3 markings from `x = q = 1` versus 2 for the fused net, including
    a half-done marking (`p = 1, y = 0`) the fused net can never show;
  - **it crosses the ρ boundary**: `ρ(t_A) = 1/2`, `ρ(t_B) = 2` — the
    interface place manufactures a fan-in transition out of a core one;
  - the local invariants `x + p` and `q + y` survive, but the fused net's
    cross-net invariant `x + y` does not — it has to be rewritten as
    `x + iface + y`.

## (4) Liveness does not survive gluing — testset "liveness does not survive gluing"

Interleaving reachability is a bounded BFS over integer markings (`reachable`,
`fire`, `is_live`; both nets are bounded by a positive invariant, the `cap`
is only a guard). From `a = b = c = 1`:

- In the cycle, all 56 (= C(8,3)) distributions of three tokens over six
  places are reachable, no reachable marking is dead, and **every transition
  is live** (from every reachable marking it can eventually fire).
- In the composite, with the **same** initial marking on the **same**
  channels, the run `send_ab, send_bc, send_ca, net_abc` reaches the marking
  `cleared = 1`, everything else 0, which is **dead**. Consequently **none**
  of the seven transitions is live in the composite — including all six that
  were live in the part. Restricted to the cycle's places the dead marking is
  the zero marking, which the cycle alone can never reach: the quotient took
  behaviour away, exactly as Appendix E says.

## Safety survives — testset "safety survives gluing"

For contrast, the one-directional guarantee: "at most three tokens in flight
across `a, b, c, pending_*`" holds in the cycle (it is the `ones(6)` invariant
as an equality) and holds in the composite as an inequality, where `net_abc`
only removes. Every composite marking, restricted to the cycle's places, is
either a cycle-reachable marking or the zero marking the observer leaves
behind. (The ring is not 1-safe — a single place can hold all 3 tokens — so the naive
"every place ≤ 1" is *not* a safety property of the part; the test checks
that too.)

## Summary

| Claim (Appendix E) | Result | Testset |
|---|---|---|
| ρ > 1 transition composes freely | glue succeeds, ns/nt 7/7 | composite shape |
| … but breaks the event graph | false; `pending_*` gain a 2nd consumer, `cleared` is a sink | event graph breaks |
| P-invariants of parts "derivable from" composite | restriction of composite invariants → part invariants holds; extension by zero fails | P-invariants |
| conservation of the part need not be conservation of the whole | `ones(6)` not an invariant of the composite; `(1,…,1,3)` is | P-invariants |
| gluing along transitions | not in AlgebraicPetri's `Open`; expressible in Catlab via `OpenACSetTypes(_, :T)`; place workaround creates ρ > 1 | transition gluing |
| liveness does not survive gluing | 6 live transitions become dead; explicit 4-step witness | liveness does not survive gluing |
| safety survives gluing | token bound holds in part and composite | safety survives gluing |
