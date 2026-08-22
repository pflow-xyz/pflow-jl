using Test
using pflow
using AlgebraicPetri
using OrdinaryDiffEq

# One settlement channel x -> y: send_xy debits x into pending_xy, settle_xy
# credits y.  Boundary places are x and y; pending_xy is internal.
function channel(x::String, y::String)
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

@testset "AlgebraicPetri bridge" begin

    @testset "round trip" begin
        ch = channel("a", "b")
        lpn = to_labelled_petri_net(ch)
        @test ns(lpn) == 3 && nt(lpn) == 2
        @test snames(lpn) == [:a, :b, :pending_ab]
        back = from_labelled_petri_net(lpn)
        @test Set(keys(back.places)) == Set(keys(ch.places))
        @test length(back.arcs) == length(ch.arcs)
        @test to_labelled_petri_net(back) == lpn
    end

    @testset "weights become multiplicity" begin
        net = Pflow()
        place!(net, "milk"; initial = 5000); place!(net, "used"; initial = 0)
        transition!(net, "latte")
        arc!(net; source = "milk", target = "latte", weight = 3)
        arc!(net; source = "latte", target = "used", weight = 3)
        lpn = to_labelled_petri_net(net)
        @test length(inputs(lpn, 1)) == 3
        @test incidence_matrix(lpn) == reshape([-3, 3], 2, 1)
        @test from_labelled_petri_net(lpn).arcs[1].weight == [3]
    end

    @testset "contextual arcs are not silently consumed" begin
        net = channel("a", "b")
        place!(net, "limit"; initial = 1)
        guard!(net, "send_ab", "limit", 1)          # read arc (transition -> place)
        @test_throws ContextualArcError to_model(net)
        @test_throws ContextualArcError to_labelled_petri_net(net)
        loop = to_labelled_petri_net(net; contextual = :selfloop)
        t = findfirst(==(:send_ab), tnames(loop))
        @test :limit in sname.(Ref(loop), inputs(loop, t))
        @test :limit in sname.(Ref(loop), outputs(loop, t))
        @test incidence_matrix(loop)[findfirst(==(:limit), snames(loop)), t] == 0
        dropped = to_labelled_petri_net(net; contextual = :drop)
        @test !(:limit in sname.(Ref(dropped), inputs(dropped, t)))
        guard!(net, "limit", "settle_ab", 1)         # inhibitor (place -> transition)
        @test_throws ContextualArcError to_labelled_petri_net(net; contextual = :selfloop)
    end

    @testset "Settle: coproduct vs pushout" begin
        parts = [:ch_ab => channel("a", "b"), :ch_bc => channel("b", "c"), :ch_ca => channel("c", "a")]
        # merge/+ is the coproduct: nine places, shared balances duplicated
        cop = parts[1][2] + parts[2][2] + parts[3][2]
        @test length(cop.places) == 9
        @test haskey(cop.places, "b_1")
        # glue is the pushout: six places, each balance is one place
        cycle = glue(parts, Dict(:ch_ab => ["a", "b"], :ch_bc => ["b", "c"], :ch_ca => ["c", "a"]))
        @test ns(cycle) == 6
        @test nt(cycle) == 6
        @test Set(snames(cycle)) == Set([:a, :b, :c, :pending_ab, :pending_bc, :pending_ca])
        # the core is a timed event graph ...
        @test is_event_graph(cycle)
        # ... with the accounting identity as a P-invariant: a+b+c+p_ab+p_bc+p_ca = const
        @test is_p_invariant(cycle, ones(Int, 6))
        # and no component has a cycle at all — throughput is created at the glue
        @test !is_event_graph(to_labelled_petri_net(parts[1][2]))
        # exposing a boundary: the glued cycle as an open net on {a}
        opened = glue(parts, Dict(:ch_ab => ["a", "b"], :ch_bc => ["b", "c"], :ch_ca => ["c", "a"]); outer = ["a"])
        @test ns(opened) == 6
        # back to Pflow for the editor
        back = from_labelled_petri_net(cycle)
        @test length(back.places) == 6 && length(back.transitions) == 6 && length(back.arcs) == 12
    end

    @testset "ODE via vectorfield" begin
        ch = channel("a", "b")
        u0 = set_state(ch, Dict("a" => 100, "b" => 0, "pending_ab" => 0))
        rates = set_rates(ch, (:send_ab => 1.0, :settle_ab => 1.0))
        prob = to_ode_problem(ch, (0.0, 20.0); u0 = u0, rates = rates)
        sol = solve(prob, Tsit5())
        final = sol.u[end]
        @test sum(final) ≈ 100 atol = 1e-6          # conservation
        @test final[2] > 99                          # everything settled into b
    end
end
