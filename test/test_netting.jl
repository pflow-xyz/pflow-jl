# Netting experiment (book Appendix E, "Where the Free Structure Stops").
#
# A multi-fan-in observer transition `net_abc` (ρ = 3) is glued onto the
# three-channel Settle cycle from test_algebraic.jl along the *pending*
# places.  Questions, each answered by a named testset below:
#
#   "netting part"          — the ρ > 1 transition itself
#   "composite shape"       — ns/nt after gluing along shared place names
#   "P-invariants"          — which invariants of the parts lift (rational
#                             left nullspace of C, no extra deps)
#   "event graph breaks"    — is_event_graph == false and which places
#   "transition gluing"     — AlgebraicPetri's Open is species-only; Catlab
#                             can glue along T; interface-place workaround
#   "liveness does not survive gluing" — bounded BFS counterexample
#   "safety survives gluing"           — the other direction, for contrast
#
# Run directly:
#   julia --project=. -e 'using pflow, AlgebraicPetri; include("test/test_netting.jl")'

using Test
using pflow
using AlgebraicPetri
using Catlab
using Catlab.CategoricalAlgebra: OpenACSetTypes, FinFunction, apex
using Catlab.WiringDiagrams: oapply
using Catlab.Programs.RelationalPrograms: parse_relation_diagram

# ---------------------------------------------------------------- parts ----

# Same channel as test_algebraic.jl (duplicated so this file runs standalone).
function netting_channel(x::String, y::String)
    net = Pflow()
    place!(net, x; initial = 100)
    place!(net, y; initial = 100)
    place!(net, "pending_$(x)$(y)"; initial = 0)
    transition!(net, "send_$(x)$(y)")
    transition!(net, "settle_$(x)$(y)")
    arc!(net; source = x, target = "send_$(x)$(y)")
    arc!(net; source = "send_$(x)$(y)", target = "pending_$(x)$(y)")
    arc!(net; source = "pending_$(x)$(y)", target = "settle_$(x)$(y)")
    arc!(net; source = "settle_$(x)$(y)", target = y)
    net
end

# The observer: one transition consuming the three pending obligations of a
# full a->b->c->a cycle and producing ONE token into `cleared`.
#
# Why `cleared` and not credits to a/b/c: a cycle of equal obligations nets
# to zero — nobody is owed anything — so the honest post-set is a single
# "this cycle was cleared" receipt.  Crediting the balances would just be
# three more settle_* transitions (ρ = 1 each) and would not leave the event
# graph; a ρ = 3 verdict transition is the point of the experiment.
function netting_part()
    net = Pflow()
    for p in ("pending_ab", "pending_bc", "pending_ca"); place!(net, p; initial = 0); end
    place!(net, "cleared"; initial = 0)
    transition!(net, "net_abc")
    for p in ("pending_ab", "pending_bc", "pending_ca"); arc!(net; source = p, target = "net_abc"); end
    arc!(net; source = "net_abc", target = "cleared")
    net
end

const CHANNEL_PARTS = [:ch_ab => netting_channel("a", "b"),
                       :ch_bc => netting_channel("b", "c"),
                       :ch_ca => netting_channel("c", "a")]
const CHANNEL_PORTS = Dict(:ch_ab => ["a", "b", "pending_ab"],
                           :ch_bc => ["b", "c", "pending_bc"],
                           :ch_ca => ["c", "a", "pending_ca"])
const NETTING_PORTS = Dict(:netting => ["pending_ab", "pending_bc", "pending_ca"])

cycle_net()   = glue(CHANNEL_PARTS, CHANNEL_PORTS)
netting_net() = glue(vcat(CHANNEL_PARTS, [:netting => netting_part()]),
                     merge(CHANNEL_PORTS, NETTING_PORTS))

# -------------------------------------------------------------- helpers ----

sidx(lpn, s::Symbol) = findfirst(==(s), snames(lpn))
tidx(lpn, t::Symbol) = findfirst(==(t), tnames(lpn))
rho(lpn, t::Symbol)  = length(inputs(lpn, tidx(lpn, t))) // length(outputs(lpn, tidx(lpn, t)))

"Places violating the event-graph property, as (place, producers, consumers)."
function event_graph_violations(lpn)
    prod = zeros(Int, ns(lpn)); cons = zeros(Int, ns(lpn))
    for t in 1:nt(lpn)
        for s in inputs(lpn, t);  cons[s] += 1; end
        for s in outputs(lpn, t); prod[s] += 1; end
    end
    [(sname(lpn, s), prod[s], cons[s]) for s in 1:ns(lpn) if prod[s] != 1 || cons[s] != 1]
end

"Basis of {y : yᵀC = 0} over the rationals (Gauss–Jordan on Cᵀ, exact)."
function left_nullspace(C::AbstractMatrix{<:Integer})
    A = Rational{BigInt}.(transpose(C))          # nt × ns, solve A·y = 0
    m, n = size(A); pivots = Int[]; r = 1
    for c in 1:n
        r > m && break
        p = findfirst(i -> A[i, c] != 0, r:m)
        p === nothing && continue
        p += r - 1
        A[r, :], A[p, :] = A[p, :], A[r, :]
        A[r, :] ./= A[r, c]
        for i in 1:m
            (i != r && A[i, c] != 0) && (A[i, :] .-= A[i, c] .* A[r, :])
        end
        push!(pivots, c); r += 1
    end
    basis = Vector{Rational{BigInt}}[]
    for f in setdiff(1:n, pivots)
        y = zeros(Rational{BigInt}, n); y[f] = 1
        for (i, c) in enumerate(pivots); y[c] = -A[i, f]; end
        push!(basis, y)
    end
    basis
end

"Vector over `lpn`'s places from a name => value dict (zero elsewhere)."
vec_on(lpn, d::AbstractDict) = [get(d, s, 0) for s in snames(lpn)]
"Restrict a composite vector to the places of `part`, by name."
restrict(y, composite, part) = [y[sidx(composite, s)] for s in snames(part)]
"Embed a part vector into the composite, zero on the places the part lacks."
extend(y, part, composite) = vec_on(composite, Dict(s => y[i] for (i, s) in enumerate(snames(part))))

# Tiny interleaving-semantics reachability.  All nets here are bounded by a
# positive P-invariant, `cap` is a safety net so a mistake cannot loop forever.
function fire(lpn, m::Vector{Int}, t::Int)
    m2 = copy(m)
    for s in inputs(lpn, t); m2[s] -= 1; end
    any(<(0), m2) && return nothing
    for s in outputs(lpn, t); m2[s] += 1; end
    m2
end
enabled(lpn, m, t) = fire(lpn, m, t) !== nothing
function reachable(lpn, m0::Vector{Int}; cap::Int = 32)
    seen = Set{Vector{Int}}([m0]); queue = [m0]
    while !isempty(queue)
        m = popfirst!(queue)
        for t in 1:nt(lpn)
            m2 = fire(lpn, m, t); m2 === nothing && continue
            maximum(m2) > cap && error("reachability bound $cap exceeded")
            m2 in seen && continue
            push!(seen, m2); push!(queue, m2)
        end
    end
    seen
end
is_dead(lpn, m)         = !any(t -> enabled(lpn, m, t), 1:nt(lpn))
"Liveness (L4): from every reachable marking, t can eventually fire."
is_live(lpn, m0, t::Int) = all(m -> any(m2 -> enabled(lpn, m2, t), reachable(lpn, m)), reachable(lpn, m0))
is_live(lpn, m0, t::Symbol) = is_live(lpn, m0, tidx(lpn, t))

# ---------------------------------------------------------------- tests ----

@testset "Netting experiment" begin

    @testset "netting part" begin
        obs = to_labelled_petri_net(netting_part())
        @test ns(obs) == 4 && nt(obs) == 1
        @test rho(obs, :net_abc) == 3 // 1                 # ρ > 1: observer
        @test !is_event_graph(obs)
        # alone it still has an invariant: p_ab + p_bc + p_ca + 3·cleared
        @test is_p_invariant(obs, vec_on(obs, Dict(:pending_ab => 1, :pending_bc => 1, :pending_ca => 1, :cleared => 3)))
    end

    @testset "composite shape" begin
        cyc = cycle_net(); comp = netting_net()
        @test ns(cyc) == 6 && nt(cyc) == 6                  # baseline (test_algebraic.jl)
        @test ns(comp) == 7 && nt(comp) == 7                # +cleared, +net_abc
        @test Set(snames(comp)) == Set([:a, :b, :c, :pending_ab, :pending_bc, :pending_ca, :cleared])
        @test :net_abc in tnames(comp)
        # the pending places were identified, not duplicated
        @test count(==(:pending_ab), snames(comp)) == 1
        # net_abc reads the channels' pending places, not private copies
        t = tidx(comp, :net_abc)
        @test Set(sname.(Ref(comp), inputs(comp, t))) == Set([:pending_ab, :pending_bc, :pending_ca])
        @test sname.(Ref(comp), outputs(comp, t)) == [:cleared]
        @test rho(comp, :net_abc) == 3 // 1
        @test all(rho(comp, tn) == 1 // 1 for tn in tnames(comp) if tn != :net_abc)
    end

    @testset "P-invariants" begin
        cyc = cycle_net(); comp = netting_net()
        C = incidence_matrix(comp)
        @test size(C) == (7, 7)
        basis = left_nullspace(C)
        # exactly one invariant survives, and it weights `cleared` by 3
        @test length(basis) == 1
        y = basis[1]; y = y ./ minimum(filter(!iszero, y))
        expected = vec_on(comp, Dict(:a => 1, :b => 1, :c => 1, :pending_ab => 1, :pending_bc => 1, :pending_ca => 1, :cleared => 3))
        @test y == expected
        @test is_p_invariant(comp, expected)
        # sanity: the same routine on the bare cycle recovers ones(6) (test_algebraic.jl)
        bc = left_nullspace(incidence_matrix(cyc))
        @test length(bc) == 1 && all(==(bc[1][1]), bc[1])
        # (a) Extension by zero does NOT lift: a channel's a+b+pending_ab is an
        #     invariant of the channel but not of the composite (b is shared).
        ch = to_labelled_petri_net(CHANNEL_PARTS[1][2])
        @test is_p_invariant(ch, ones(Int, 3))
        @test !is_p_invariant(comp, extend(ones(Int, 3), ch, comp))
        # (b) The cycle's total-token invariant ones(6) does not lift either:
        #     net_abc turns three tokens into one.
        @test is_p_invariant(cyc, ones(Int, 6))
        @test !is_p_invariant(comp, extend(ones(Int, 6), cyc, comp))
        # (c) What DOES hold, and is what Appendix E actually claims: every
        #     composite invariant RESTRICTS to an invariant of each part.
        for (_, part) in CHANNEL_PARTS
            @test is_p_invariant(to_labelled_petri_net(part), restrict(expected, comp, to_labelled_petri_net(part)))
        end
        obs = to_labelled_petri_net(netting_part())
        @test is_p_invariant(obs, restrict(expected, comp, obs))
        @test is_p_invariant(cyc, restrict(expected, comp, cyc))
    end

    @testset "event graph breaks" begin
        cyc = cycle_net(); comp = netting_net()
        @test is_event_graph(cyc)
        @test !is_event_graph(comp)
        v = event_graph_violations(comp)
        @test Set(first.(v)) == Set([:pending_ab, :pending_bc, :pending_ca, :cleared])
        # each pending place now has TWO consumers (settle_* and net_abc) ...
        for p in (:pending_ab, :pending_bc, :pending_ca)
            @test (p, 1, 2) in v
        end
        # ... and cleared is a sink: one producer, no consumer
        @test (:cleared, 1, 0) in v
        # the balances a, b, c are untouched by the observer
        @test isempty(intersect(first.(v), [:a, :b, :c]))
    end

    @testset "transition gluing" begin
        # Two one-step nets sharing a transition NAME `t`.
        A = LabelledPetriNet([:x, :p], :t => ([:x] => [:p]))
        B = LabelledPetriNet([:q, :y], :t => ([:q] => [:y]))
        # (i) AlgebraicPetri's Open exposes species only: a transition name
        #     is looked up among snames and is simply not there.
        @test_throws KeyError Open(A, [:t])
        @test Open(A, [:x]) isa OpenLabelledPetriNet
        # (ii) Catlab itself CAN build cospans with transition feet, because
        #     the schema inclusion {T} ↪ {T, S, I, O} has no outgoing arrows
        #     from T (I and O point INTO T).  The pushout then fuses the two
        #     transitions into one with the union of their pre/post sets —
        #     a synchronisation, Appendix E's EventLink.
        _, OpenT = OpenACSetTypes(AlgebraicPetri.LabelledPetriNetUntyped, :T)
        oA = OpenT{Symbol}(A, FinFunction([1], nt(A)))
        oB = OpenT{Symbol}(B, FinFunction([1], nt(B)))
        uwd = parse_relation_diagram(:(()), :(begin A(t); B(t) end))
        fused = apex(oapply(uwd, Dict(:A => oA, :B => oB)))
        @test ns(fused) == 4 && nt(fused) == 1
        @test Set(sname.(Ref(fused), inputs(fused, 1)))  == Set([:x, :q])
        @test Set(sname.(Ref(fused), outputs(fused, 1))) == Set([:p, :y])
        @test rho(fused, :t) == 1 // 1                      # still core
        @test is_p_invariant(fused, vec_on(fused, Dict(:x => 1, :p => 1)))
        @test is_p_invariant(fused, vec_on(fused, Dict(:q => 1, :y => 1)))
        # (iii) The place-only workaround: split t into t_A -> iface -> t_B
        #       and glue along the interface PLACE with the existing `glue`.
        pa = Pflow(); place!(pa, "x"; initial = 1); place!(pa, "p"); place!(pa, "iface")
        transition!(pa, "t_A")
        arc!(pa; source = "x", target = "t_A"); arc!(pa; source = "t_A", target = "p"); arc!(pa; source = "t_A", target = "iface")
        pb = Pflow(); place!(pb, "q"; initial = 1); place!(pb, "y"); place!(pb, "iface")
        transition!(pb, "t_B")
        arc!(pb; source = "iface", target = "t_B"); arc!(pb; source = "q", target = "t_B"); arc!(pb; source = "t_B", target = "y")
        split = glue([:A => pa, :B => pb], Dict(:A => ["iface"], :B => ["iface"]))
        @test ns(split) == 5 && nt(split) == 2              # +1 place, +1 transition
        # What it changes:
        #  - the sync point becomes two transitions, one of which now has ρ>1
        @test rho(split, :t_A) == 1 // 2
        @test rho(split, :t_B) == 2 // 1
        #  - interleaving: a marking with p produced but y not yet is reachable
        m_fused = vec_on(fused, Dict(:x => 1, :q => 1))
        m_split = vec_on(split, Dict(:x => 1, :q => 1))
        Rf = reachable(fused, m_fused); Rs = reachable(split, m_split)
        @test length(Rf) == 2 && length(Rs) == 3
        half_done = vec_on(split, Dict(:p => 1, :iface => 1, :q => 1))
        @test half_done in Rs
        @test !any(m -> m[sidx(fused, :p)] == 1 && m[sidx(fused, :y)] == 0, Rf)
        #  - the two LOCAL invariants survive, but the cross-net invariant
        #    x + y of the fused net does not: it must be rewritten through
        #    the interface place as x + iface + y.
        @test is_p_invariant(fused, vec_on(fused, Dict(:x => 1, :y => 1)))
        @test is_p_invariant(split, vec_on(split, Dict(:x => 1, :p => 1)))
        @test is_p_invariant(split, vec_on(split, Dict(:q => 1, :y => 1)))
        @test !is_p_invariant(split, vec_on(split, Dict(:x => 1, :y => 1)))
        @test is_p_invariant(split, vec_on(split, Dict(:x => 1, :iface => 1, :y => 1)))
    end

    @testset "liveness does not survive gluing" begin
        cyc = cycle_net(); comp = netting_net()
        m_cyc  = vec_on(cyc,  Dict(:a => 1, :b => 1, :c => 1))
        m_comp = vec_on(comp, Dict(:a => 1, :b => 1, :c => 1))
        # In the cycle every transition is live: the token ring never stops.
        # (every distribution of 3 tokens over 6 places is reachable: C(8,3))
        @test length(reachable(cyc, m_cyc)) == binomial(8, 3)
        @test !any(m -> is_dead(cyc, m), reachable(cyc, m_cyc))
        @test all(t -> is_live(cyc, m_cyc, t), 1:nt(cyc))
        # Glue on net_abc: the SAME initial marking on the SAME channels now
        # reaches a dead marking — three sends, one netting, everything in cleared.
        dead = vec_on(comp, Dict(:cleared => 1))
        Rc = reachable(comp, m_comp)
        @test dead in Rc
        @test is_dead(comp, dead)
        @test all(t -> !is_live(comp, m_comp, t), 1:nt(comp))   # none survive
        # The witness run, step by step:
        m = m_comp
        for t in (:send_ab, :send_bc, :send_ca, :net_abc)
            m = fire(comp, m, tidx(comp, t)); @test m !== nothing
        end
        @test m == dead
        # Restricting the dead composite marking to the cycle's places gives
        # the zero marking — something the cycle ALONE can never reach.
        @test !(restrict(dead, comp, cyc) in reachable(cyc, m_cyc))
    end

    @testset "safety survives gluing" begin
        cyc = cycle_net(); comp = netting_net()
        m_cyc  = vec_on(cyc,  Dict(:a => 1, :b => 1, :c => 1))
        m_comp = vec_on(comp, Dict(:a => 1, :b => 1, :c => 1))
        # "never more than three tokens in flight" holds in the part (it is
        # the ones(6) invariant; note the ring is NOT 1-safe: one place can hold all 3) ...
        inflight(lpn, m) = sum(m[sidx(lpn, s)] for s in (:a, :b, :c, :pending_ab, :pending_bc, :pending_ca))
        @test all(m -> inflight(cyc, m) == 3, reachable(cyc, m_cyc))
        @test any(m -> maximum(m) == 2, reachable(cyc, m_cyc))
        # ... and still in the composite; and every composite marking,
        # restricted to the cycle's places, is one the cycle could produce
        # by itself or the zero marking net_abc leaves behind.
        Rc = reachable(comp, m_comp); Rcyc = reachable(cyc, m_cyc)
        @test all(m -> inflight(comp, m) <= 3, Rc)
        @test any(m -> inflight(comp, m) < 3, Rc)              # net_abc only removes
        @test all(m -> restrict(m, comp, cyc) in Rcyc || all(iszero, restrict(m, comp, cyc)), Rc)
    end
end
