using Test
using JSON
using pflow: SsaModel, SsaPlace, SsaTransition, SsaArc, ssa_model, simulate_ssa,
             simulate_sde, combinations, combinations_real, GaussianSampler, normal!,
             CHEMICAL_LANGEVIN_ASSUMPTION

# Chemical Langevin SDE (go-pflow ROADMAP.md G6, stochastic/sde.go). Unlike
# SSA there is no byte-exact cross-language SDE contract yet — no
# test/testdata/sde/ goldens — so most of this file checks consistency
# against this package's own simulate_ssa, mirroring go-pflow's
# stochastic/sde_test.go. The one bit-exact check is normal!() against
# go-pflow's own TestPortableNormalVectors: Go is the reference
# implementation for this sampler, the same role it plays for wait()/uniform()
# in ssa-spec.md.

bits(x::Float64) = reinterpret(UInt64, x)
const SDE_FIXTURES = joinpath(@__DIR__, "testdata", "ssa")   # reuse the SSA models

@testset "Chemical Langevin SDE" begin

    @testset "normal!() matches go-pflow's TestPortableNormalVectors at seed 42" begin
        want = [0xbfe73d2feb0fb377, 0xbfcb088028693f9c, 0x3fcc5e21f7812a4c,
                0x3fe0ba8bb0c5fa51, 0x3fddb514bfac5b4e]
        s = GaussianSampler(UInt64(42))
        for e in want
            @test bits(normal!(s)) == e
        end
    end

    @testset "combinations_real" begin
        for m in 0:10, w in 0:4
            @test abs(combinations_real(Float64(m), w) - combinations(m, w)) < 1e-9
        end
        # documented "wrong near zero" case, matched to go-pflow's own comment
        @test abs(combinations_real(0.5, 2) - (-0.125)) < 1e-12
        for x in (0.0, 0.3, 1.0, 5.7, 100.0)
            @test combinations_real(x, 1) === x
        end
    end

    @testset "refuses a gated model" begin
        m = SsaModel(
            [SsaPlace("a", 10, 10), SsaPlace("licence", 1, 0), SsaPlace("b", 0, 0)],
            [SsaTransition("t", 1.0)],
            [SsaArc("a", "t", 1, :flow, true),
             SsaArc("licence", "t", 1, :read, true),
             SsaArc("t", "b", 1, :flow, true)],
        )
        res = simulate_sde(m; horizon = 1.0, samples = 2, realizations = 1, seed = UInt64(1))
        @test res.diverged
        @test !isempty(res.caveats)
    end

    @testset "dispatch names the chemical Langevin assumption" begin
        doc = JSON.parsefile(joinpath(SDE_FIXTURES, "chain.json"))
        model = ssa_model(doc["model"])
        res = simulate_sde(model; horizon = 1.0, samples = 5, realizations = 1, seed = UInt64(1))
        @test !res.diverged
        @test !isempty(CHEMICAL_LANGEVIN_ASSUMPTION)
    end

    @testset "SDE mean tracks SSA mean on a mean-field-exact linear chain" begin
        doc = JSON.parsefile(joinpath(SDE_FIXTURES, "chain.json"))
        model = ssa_model(doc["model"])
        opts = (horizon = 6.0, samples = 61, realizations = 400, seed = UInt64(20260902))
        ssa = simulate_ssa(model; opts...)
        sde = simulate_sde(model; opts...)
        @test !sde.diverged
        for (p, id) in enumerate(sde.places)
            max_diff = 0.0
            for i in 1:length(sde.times)
                max_diff = max(max_diff, abs(sde.values[p][i] - ssa.values[p][i]))
            end
            @test max_diff <= 2.0
        end
        @test abs(sum(sde.final) - 100.0) <= 2.0
    end

    @testset "SDE variance tracks SSA variance on the SIR fixture at scale" begin
        doc = JSON.parsefile(joinpath(SDE_FIXTURES, "sir.json"))
        base = doc["model"]
        # Scale x10 (N = 10,000) the way go-pflow's consistency_test.go's
        # sirModel(scale) does: population up, infect rate proportionally
        # down so R0 (and the trajectory shape) matches.
        scale = 10
        scaled = Dict(
            "places" => [merge(p, Dict("initial" => p["initial"] * scale)) for p in base["places"]],
            "transitions" => [t["id"] == "infect" ? merge(t, Dict("rate" => t["rate"] / scale)) : t for t in base["transitions"]],
            "arcs" => base["arcs"],
        )
        model = ssa_model(scaled)
        opts = (horizon = 40.0, samples = 81, realizations = 100, seed = UInt64(20260902))
        ssa = simulate_ssa(model; opts...)
        sde = simulate_sde(model; opts...)
        @test !sde.diverged
        for (p, id) in enumerate(sde.places)
            ssa_sd = ssa.stddev[p]
            sde_sd = sde.stddev[p]
            peak = 1
            for i in 2:length(ssa_sd)
                if ssa_sd[i] > ssa_sd[peak]
                    peak = i
                end
            end
            ssa_sd[peak] < 1e-9 && continue
            rel = abs(sde_sd[peak] - ssa_sd[peak]) / ssa_sd[peak]
            @test rel <= 0.35
        end
    end

    @testset "SDE tracks SSA (not the ODE's different rate law) on weight-2 dimerisation" begin
        doc = JSON.parsefile(joinpath(SDE_FIXTURES, "dimer.json"))
        model = ssa_model(doc["model"])
        opts = (horizon = 5.0, samples = 51, realizations = 300, seed = UInt64(20260902))
        ssa = simulate_ssa(model; opts...)
        sde = simulate_sde(model; opts...)
        @test !sde.diverged
        for (p, id) in enumerate(sde.places)
            max_diff = 0.0
            for i in 1:length(sde.times)
                max_diff = max(max_diff, abs(sde.values[p][i] - ssa.values[p][i]))
            end
            @test max_diff <= 3.0
        end
    end
end
