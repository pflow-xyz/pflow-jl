# Closure check for the Settle class (PROOF-ROADMAP P3).
# Run alone:  julia --project=. -e 'using pflow, AlgebraicPetri; include("test/test_closure.jl")'
using Test
using Random
using pflow
using AlgebraicPetri
using Catlab.CategoricalAlgebra: compose, apex, set_subpart!

# --- random wirings -------------------------------------------------------

# n parties named p1..pn; m channels between random distinct pairs (repeats
# allowed, disambiguated by tag); glued along the party names.  Returns the
# LabelledPetriNet apex and the number of channels actually wired.
function random_settle_wiring(rng::AbstractRNG; max_parties = 6, max_channels = 7)
    n = rand(rng, 2:max_parties)
    m = rand(rng, 1:max_channels)
    parties = ["p$i" for i in 1:n]
    parts = Pair{Symbol, Pflow}[]
    ports = Dict{Symbol, Vector{String}}()
    for k in 1:m
        x, y = parties[randperm(rng, n)[1:2]]
        k == 1 && ((x, y) = ("p1", parties[rand(rng, 2:n)]))   # p1 always participates (a glue handle for ⊗-then-glue)
        name = Symbol("ch$k")
        push!(parts, name => settle_channel(x, y; tag = "c$k"))
        ports[name] = [x, y]
    end
    glue(parts, ports), m
end

# ⊗ in Pflow is `+` (disjoint union with label renaming); take it back to a
# LabelledPetriNet.
tensor(a::LabelledPetriNet, b::LabelledPetriNet) =
    to_labelled_petri_net(from_labelled_petri_net(a) + from_labelled_petri_net(b))

# --- negative controls ----------------------------------------------------

# Two channels a->b and b->a plus a netting transition that consumes both
# pendings and produces one token in a (ρ = 2): the P2 experiment's net.
function netting_net()
    parts = [:ab => settle_channel("a", "b"), :ba => settle_channel("b", "a")]
    cyc = from_labelled_petri_net(glue(parts, Dict(:ab => ["a", "b"], :ba => ["b", "a"])))
    transition!(cyc, "net_ab")
    arc!(cyc; source = "pending_ab", target = "net_ab")
    arc!(cyc; source = "pending_ba", target = "net_ab")
    arc!(cyc; source = "net_ab", target = "a")
    to_labelled_petri_net(cyc)
end

@testset "Settle closure" begin

    @testset "generators and channel" begin
        s = send_net("a", "pending_ab"; name = "send_ab"); r = settle_net("pending_ab", "b"; name = "settle_ab")
        # open generators: pending is on the boundary, so they are members ...
        @test is_settle_generated(s)
        @test is_settle_generated(r)
        # ... but their apexes, closed off, are not: the pending is half a channel
        @test startswith(settle_reason(apex(s)), "pending-degree")
        @test startswith(settle_reason(apex(r)), "pending-degree")
        # the channel is the composite of the two generators along `pending`
        composite = apex(compose(s, r))
        @test ns(composite) == 3 && nt(composite) == 2
        @test Set(snames(composite)) == Set([:a, :pending_ab, :b])
        @test is_settle_generated(composite)
        ch = to_labelled_petri_net(settle_channel("a", "b"))
        @test is_settle_generated(ch)
        @test incidence_matrix(ch) == incidence_matrix(composite)[indexin(snames(ch), snames(composite)),
                                                                   indexin(tnames(ch), tnames(composite))]
        # a lone balance (unit-adjacent) and the empty net are in the class
        @test is_settle_generated(LabelledPetriNet([:a]))
        @test is_settle_generated(LabelledPetriNet())
        # the typing the predicate infers is the one the labels intend
        skind, tkind = settle_typing(ch)
        @test skind[findfirst(==(:pending_ab), snames(ch))] == :pending
        @test skind[findfirst(==(:a), snames(ch))] == :balance
        @test tkind[findfirst(==(:send_ab), tnames(ch))] == :send
        @test tkind[findfirst(==(:settle_ab), tnames(ch))] == :settle
    end

    @testset "closed under glue along balances (random wirings)" begin
        rng = MersenneTwister(20260822)
        N = 60
        for i in 1:N
            lpn, m = random_settle_wiring(rng)
            @test nt(lpn) == 2m
            @test is_settle_generated(lpn)
            r = settle_reason(lpn)
            r === nothing || @info "wiring $i rejected" r
        end
        # the three-party cycle from test_algebraic.jl, explicitly
        parts = [:ab => settle_channel("a", "b"), :bc => settle_channel("b", "c"), :ca => settle_channel("c", "a")]
        cycle = glue(parts, Dict(:ab => ["a", "b"], :bc => ["b", "c"], :ca => ["c", "a"]))
        @test is_settle_generated(cycle)
        # a 2-cycle a->b->a is a channel with y = x: both typings valid, still in the class
        two = glue([:ab => settle_channel("a", "b"), :ba => settle_channel("b", "a")],
                   Dict(:ab => ["a", "b"], :ba => ["b", "a"]))
        @test is_settle_generated(two)
    end

    @testset "closed under ⊗ (disjoint union)" begin
        rng = MersenneTwister(7)
        for _ in 1:30
            a, _ = random_settle_wiring(rng); b, _ = random_settle_wiring(rng)
            ab = tensor(a, b)
            @test ns(ab) == ns(a) + ns(b) && nt(ab) == nt(a) + nt(b)
            @test is_settle_generated(ab)
        end
        # ⊗ then glue: glue two tensored composites along a shared party
        rng = MersenneTwister(11)
        for _ in 1:20
            a, _ = random_settle_wiring(rng); b, _ = random_settle_wiring(rng)
            pa = from_labelled_petri_net(a); pb = from_labelled_petri_net(b)
            glued = glue([:A => pa, :B => pb], Dict(:A => ["p1"], :B => ["p1"]))
            @test is_settle_generated(glued)
            @test ns(glued) == ns(a) + ns(b) - 1
        end
    end

    @testset "negative controls" begin
        # netting transition (ρ = 2) glued into a 2-cycle
        nn = netting_net()
        @test !is_settle_generated(nn)
        @test startswith(settle_reason(nn), "fan-in")
        @test occursin("net_ab", settle_reason(nn))
        @test_throws ArgumentError to_settle_net(nn)

        # a two-input transition glued onto a good wiring
        rng = MersenneTwister(3)
        base, _ = random_settle_wiring(rng)
        bad = from_labelled_petri_net(base)
        place!(bad, "fee"); transition!(bad, "pay_fee")
        arc!(bad; source = "p1", target = "pay_fee"); arc!(bad; source = "fee", target = "pay_fee")
        arc!(bad; source = "pay_fee", target = "p2")
        @test startswith(settle_reason(to_labelled_petri_net(bad)), "fan-in")

        # fan-out: one send into two pendings
        fo = from_labelled_petri_net(to_labelled_petri_net(settle_channel("a", "b")))
        place!(fo, "pending_extra"); arc!(fo; source = "send_ab", target = "pending_extra")
        @test startswith(settle_reason(to_labelled_petri_net(fo)), "fan-out")

        # multiplicity 2 on a send arc is fan-in of the same place
        w = settle_channel("a", "b"); w.arcs[1] = pflow.Arrow("a", "send_ab", [2], nothing, nothing, nothing, nothing, false)
        @test startswith(settle_reason(to_labelled_petri_net(w)), "fan-in")

        # a pending with two producers: two sends into one pending (degree)
        pd = settle_channel("a", "b")
        place!(pd, "c"); transition!(pd, "send_cb")
        arc!(pd; source = "c", target = "send_cb"); arc!(pd; source = "send_cb", target = "pending_ab")
        @test startswith(settle_reason(to_labelled_petri_net(pd)), "pending-degree")

        # odd cycle a->b->c->a with single transitions: not bipartite
        odd = LabelledPetriNet([:a, :b, :c], :t1 => ([:a] => [:b]), :t2 => ([:b] => [:c]), :t3 => ([:c] => [:a]))
        @test startswith(settle_reason(odd), "not-bipartite")

        # self-loop, source, sink
        @test startswith(settle_reason(LabelledPetriNet([:a], :t => ([:a] => [:a]))), "self-loop")
        @test startswith(settle_reason(LabelledPetriNet([:a], :t => (Symbol[] => [:a]))), "no-input")
        @test startswith(settle_reason(LabelledPetriNet([:a], :t => ([:a] => Symbol[]))), "no-output")
    end

    @testset "Catlab schema: SettleNet and the forgetful functor" begin
        ch = to_labelled_petri_net(settle_channel("a", "b"))
        sn = to_settle_net(ch)
        @test sn isa SettleNet
        @test is_well_typed_settle(sn)
        @test Set(sn[:, :skind]) == Set([:balance, :pending])
        @test sn[:, :tkind] == [:send, :settle] || sn[:, :tkind] == [:settle, :send]
        back = forget_kinds(sn)
        @test back isa LabelledPetriNet
        @test back == ch
        # round trip over random wirings
        rng = MersenneTwister(99)
        for _ in 1:10
            lpn, _ = random_settle_wiring(rng)
            sn = to_settle_net(lpn)
            @test is_well_typed_settle(sn) && forget_kinds(sn) == lpn
        end
        # a hand-typed net with a wrong kind is caught by the recorded-typing check
        bad = to_settle_net(ch)
        set_subpart!(bad, 1, :skind, :pending)       # a: balance -> pending
        @test !is_well_typed_settle(bad)
    end
end
