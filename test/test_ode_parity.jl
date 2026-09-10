# ODE parity against go-pflow/pflow-xyz/pflow-rs, TOLERANCE not bytes.
#
# Unlike the portable SSA (ssa-spec.md) and the Rust ODE gate
# (pflow-rs/crates/pflow-solver/tests/ode_parity.rs), pflow-jl solves through
# OrdinaryDiffEq's Tsit5 — a mature, independently implemented Runge-Kutta
# suite with its own step-size heuristics — rather than the hand-rolled
# Tsit5 the other three implementations share. Byte-exact agreement is
# neither expected nor meaningful here (CAPABILITIES.md documents this: JS↔Go
# is a live diff plus a byte-identical `expected.json` reference, Rust checks
# against the same fixtures at 1e-12; Julia "agrees to tolerance not bytes").
# What this test protects is that pflow-jl's ODE bridge (to_ode_problem) is
# solving the SAME model — same mass-action rate law, same stoichiometry —
# not a structurally different one; a real divergence would show up as an
# error far larger than solver-to-solver noise.
#
# Colored (multi-color) fixtures are skipped: to_ode_problem does not unfold
# colors the way go-pflow's ExpandColors does, so comparing them would not be
# testing the same computation. Rust's ode_parity.rs skips the same fixtures
# for the same reason (no color unfolding there either).
#
# Fixtures with a non-unit-weight INPUT arc are also skipped, for a reason
# specific to this bridge and already documented at src/algebraic.jl:53-58:
# to_labelled_petri_net repeats a weight-w input arc w times, so
# AlgebraicPetri's vectorfield gives it a combinatorial rate law, while
# go-pflow's ODE uses k*prod(u^w) — first power. The two AGREE only at unit
# weights ("the nets this bridge is meant for"); chain-weighted's weight-3
# arc reproduces exactly that divergence (worst-case final-value error 0.51
# against a tolerance of ~0.12 — real, not solver noise) and is not a bug in
# this test or in to_ode_problem, so it is skipped rather than papered over
# with a looser tolerance.

using Test
using pflow
using OrdinaryDiffEq
using JSON

@testset "ODE parity (tolerance) vs go-pflow" begin
    fixtures_path = joinpath(@__DIR__, "testdata", "ode_parity", "fixtures.json")
    expected_path = joinpath(@__DIR__, "testdata", "ode_parity", "expected.json")
    fixtures = JSON.parsefile(fixtures_path)
    expected = JSON.parsefile(expected_path)
    expected_by_name = Dict(m["name"] => m for m in expected["models"])

    color_count(model) = maximum(
        length(get(p, "initial", [1])) for p in values(model["places"]);
        init = 1,
    )

    function max_input_weight(model)
        transition_ids = Set(keys(model["transitions"]))
        w = 1
        for arc in model["arcs"]
            if arc["target"] in transition_ids
                w = max(w, maximum(get(arc, "weight", [1])))
            end
        end
        return w
    end

    compared = String[]
    skipped = String[]

    for entry in fixtures["models"]
        name = entry["name"]
        model = entry["model"]
        if color_count(model) > 1 || max_input_weight(model) > 1
            push!(skipped, name)
            continue
        end
        want = expected_by_name[name]

        net = from_json(JSON.json(model))
        u0 = set_state(net)
        rates = set_rates(net, entry["rates"])
        tspan = (Float64(entry["tspan"][1]), Float64(entry["tspan"][2]))

        prob = to_ode_problem(net, tspan; u0 = u0, rates = rates)
        sol = solve(prob, Tsit5(); reltol = 1e-6, abstol = 1e-9)

        for place in want["places"]
            got_final = sol(tspan[2])[Symbol(place)]
            want_final = want["final"][place]
            scale = 1e-9 + 1e-2 * max(abs(got_final), abs(want_final))
            @test isapprox(got_final, want_final; atol = scale) ||
                  abs(got_final - want_final) <= scale

            # A handful of interior points too, not just the endpoint — an
            # endpoint-only check would miss a trajectory that visits a very
            # different path but happens to land close at t_f.
            want_t = want["t"]
            want_u = want["u"][place]
            n = length(want_t)
            for i in (max(2, n ÷ 4), n ÷ 2, max(n - 1, 1))
                t = want_t[i]
                t < tspan[1] && continue
                t > tspan[2] && continue
                got = sol(t)[Symbol(place)]
                w = want_u[i]
                s = 1e-9 + 1e-2 * max(abs(got), abs(w))
                @test abs(got - w) <= s
            end
        end
        push!(compared, name)
    end

    @test length(compared) == length(fixtures["models"]) - length(skipped)
    @test !isempty(compared)
    if !isempty(skipped)
        @info "ODE parity: skipped colored and/or non-unit-input-weight fixtures" skipped
    end
end
