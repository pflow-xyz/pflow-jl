using Test
using JSON
using pflow: SsaModel, SsaPlace, SsaTransition, SsaArc, ssa_model, simulate_ssa,
             splitmix64, Xoshiro256, next!, uniform!, plog, combinations, Pflow,
             place!, transition!, arc!, guard!

# Byte-exact portable SSA (ssa-spec.md). Every numeric assertion below is a
# bit-pattern comparison: `===` on Float64 or `reinterpret(UInt64, x) ==`.
# Never loosen one to `≈` — a tolerance is exactly the failure this test
# exists to catch.

bits(x::Float64) = reinterpret(UInt64, x)
const SSA_FIXTURES = joinpath(@__DIR__, "testdata", "ssa")

@testset "Portable SSA" begin

    @testset "SplitMix64 seeding (§1.1)" begin
        @test splitmix64(UInt64(42)) == (0xbdd732262feb6e95, 0x28efe333b266f103,
                                         0x47526757130f9f52, 0x581ce1ff0e4ae394)
        @test splitmix64(UInt64(0)) == (0xe220a8397b1dcdaf, 0x6e789e6aa1b965f4,
                                        0x06c45d188009454f, 0xf88bb8a8724c81ec)
    end

    @testset "xoshiro256** stream (§1.5)" begin
        g = Xoshiro256(UInt64(42))
        expected_next = [0x15780b2e0c2ec716, 0x6104d9866d113a7e, 0xae17533239e499a1,
                         0xecb8ad4703b360a1, 0xfde6dc7fe2ec5e64]
        for e in expected_next
            @test next!(g) == e
        end
        g = Xoshiro256(UInt64(42))
        expected_uniform = [0x3fb5780b2e0c2ec0, 0x3fd84136619b444e, 0x3fe5c2ea66473c93,
                            0x3fed9715a8e0766c, 0x3fefbcdb8ffc5d8b]
        for e in expected_uniform
            @test bits(uniform!(g)) == e
        end
        @test next!(Xoshiro256(UInt64(0))) == 0x99ec5f36cb75f2b4
        @test next!(Xoshiro256(UInt64(1))) == 0xb3f2af6d0fc710c5
        @test next!(Xoshiro256(0xffffffffffffffff)) == 0x8f5520d52a7ead08   # wraps in SplitMix64
        # uniform never leaves [0, 1) and 1 - x1 is never 0
        g = Xoshiro256(UInt64(3))
        for _ in 1:10_000
            x = uniform!(g)
            @test 0.0 <= x < 1.0
            @test 1.0 - x > 0.0
        end
    end

    @testset "portable log (§2.5)" begin
        vectors = [
            (0.5, 0xbfe62e42fefa39ef),
            (2.0, 0x3fe62e42fefa39ef),
            (0.1, 0xc0026bb1bbb55515),
            (1e-300, 0xc085963447f87fb5),
            (0.999999, 0xbeb0c6f82d74d230),
            (3.0, 0x3ff193ea7aad030a),          # glibc gives ...098; proves the port is in use
            (10.0, 0x40026bb1bbb55516),
            (1.0, 0x0000000000000000),
            (0.7071067811865476, 0xbfd62e42fefa39ee),   # = SQRT2/2, no-doubling branch
            (0.7071067811865475, 0xbfd62e42fefa39f1),   # one ulp below, doubling branch
            (1.0000000000000002, 0x3cafffffffffffff),
            (0.9999999999999999, 0xbca0000000000000),
            (1e-9, 0xc034b927f32bffb8),
        ]
        for (x, b) in vectors
            @test bits(plog(x)) == b
        end
        @test plog(0.0) === -Inf
        @test plog(Inf) === Inf
        @test isnan(plog(-1.0))
        @test isnan(plog(NaN))
        # subnormal input exercises the normalisation branch of frexp
        @test isfinite(plog(5e-324))
    end

    @testset "combinations (§3.2)" begin
        @test combinations(50, 2) === 1225.0
        @test combinations(48, 2) === 1128.0
        @test combinations(1, 2) === 0.0
        @test combinations(7, 0) === 1.0
        @test combinations(0, 1) === 0.0
        # C(1000,20) by the spec's multiply-then-divide order: 3.3948281130245768e41
        @test bits(combinations(1000, 20)) == 0x488f2d33d98383ee
    end

    chain = SsaModel(
        [SsaPlace("a", 100, 0), SsaPlace("b", 0, 0), SsaPlace("c", 0, 0)],
        [SsaTransition("ab", 1.0), SsaTransition("bc", 1.0)],
        [SsaArc("a", "ab", 1, :flow, true), SsaArc("ab", "b", 1, :flow, true),
         SsaArc("b", "bc", 1, :flow, true), SsaArc("bc", "c", 1, :flow, true)])

    @testset "reference trace values (§3.8)" begin
        res = simulate_ssa(chain; horizon = 10, samples = 11, realizations = 3, seed = UInt64(42))
        @test res.places == ["a", "b", "c"]
        @test length(res.times) == 11
        @test bits(res.values[1][2]) == 0x4041d55555555555      # a.values[1] = 35.666666666666664
        @test bits(res.stddev[1][2]) == 0x400a660e223f1b70      # a.stddev[1] = 3.2998316455372603
        @test res.final == [0.0, 0.0, 100.0]
        @test res.series["a"].values === res.values[1]

        sir = SsaModel(
            [SsaPlace("S", 990, 0), SsaPlace("I", 10, 0), SsaPlace("R", 0, 0)],
            [SsaTransition("infect", 0.0005), SsaTransition("recover", 0.1)],
            [SsaArc("S", "infect", 1, :flow, true), SsaArc("I", "infect", 1, :flow, true),
             SsaArc("infect", "I", 2, :flow, true), SsaArc("I", "recover", 1, :flow, true),
             SsaArc("recover", "R", 1, :flow, true)])
        res = simulate_ssa(sir; horizon = 40, samples = 81, realizations = 8, seed = UInt64(11))
        @test bits(res.stddev[1][2]) == 0x3ff52a7fa9d2f8ea
        @test res.final == [9.625, 71.5, 918.875]

        dimer = SsaModel(
            [SsaPlace("A", 50, 0), SsaPlace("B", 0, 0)],
            [SsaTransition("dimerise", 0.01), SsaTransition("dissociate", 0.1)],
            [SsaArc("A", "dimerise", 2, :flow, true), SsaArc("dimerise", "B", 1, :flow, true),
             SsaArc("B", "dissociate", 1, :flow, true), SsaArc("dissociate", "A", 2, :flow, true)])
        res = simulate_ssa(dimer; horizon = 5, samples = 21, realizations = 4, seed = UInt64(7))
        @test bits(res.stddev[1][2]) == 0x3ffa887293fd6f34
        @test res.final == [23.5, 13.25]
    end

    @testset "seed rules and determinism (§3.6)" begin
        r0 = simulate_ssa(chain; horizon = 10, samples = 11, realizations = 2, seed = UInt64(0))
        r1 = simulate_ssa(chain; horizon = 10, samples = 11, realizations = 2, seed = UInt64(1))
        @test r0.values == r1.values                       # seed 0 means seed 1
        r2 = simulate_ssa(chain; horizon = 10, samples = 11, realizations = 2, seed = UInt64(2))
        @test r2.values != r1.values
        a = simulate_ssa(chain; horizon = 10, samples = 11, realizations = 1, seed = UInt64(43))
        @test a.stddev === nothing                         # stddev only when R > 1
        # single realization: the mean is the path itself
        one = simulate_ssa(chain; horizon = 10, samples = 11, realizations = 1, seed = UInt64(42))
        @test all(v -> v == round(v), one.values[1])
    end

    @testset "gating semantics (§3.3): read, inhibitor, capacity, non-kinetic" begin
        # p --(read w=1)--> fill (fires only while p >= 1, consumes nothing); q has capacity 2;
        # g --(inhibitor)--> blocked (dead while g >= 1); g --(non-kinetic flow)--> drain
        m = SsaModel(
            [SsaPlace("p", 1, 0), SsaPlace("q", 0, 2), SsaPlace("g", 1, 0), SsaPlace("h", 0, 0)],
            [SsaTransition("fill", 1.0), SsaTransition("blocked", 5.0), SsaTransition("drain", 1.0)],
            [SsaArc("p", "fill", 1, :read, true), SsaArc("fill", "q", 1, :flow, true),
             SsaArc("g", "blocked", 1, :inhibitor, true), SsaArc("blocked", "h", 1, :flow, true),
             SsaArc("g", "drain", 1, :flow, false), SsaArc("drain", "h", 1, :flow, true)])
        res = simulate_ssa(m; horizon = 50, samples = 6, realizations = 3, seed = UInt64(5))
        q = res.series["q"].values
        @test all(v -> v <= 2.0, q)                        # capacity 2 respected
        @test q[end] == 2.0                                # fill ran until the cap, then stalled
        @test res.series["p"].values == fill(1.0, 6)       # read arc consumes nothing
        # `blocked` is inhibited while g = 1; `drain` (non-kinetic) consumes g once and
        # then `blocked` runs freely into h. h ends at 1 (drain) + as many `blocked`
        # firings as fit — but p/q dynamics make the count stochastic; assert the invariant.
        h = res.series["h"].values
        @test h[end] >= 1.0
        @test res.series["g"].values[end] == 0.0
        # combinations(1, 2) == 0 keeps a w=2 input dead at m = 1
        dead = SsaModel([SsaPlace("A", 1, 0), SsaPlace("B", 0, 0)],
                        [SsaTransition("dimerise", 1.0)],
                        [SsaArc("A", "dimerise", 2, :flow, true), SsaArc("dimerise", "B", 1, :flow, true)])
        res = simulate_ssa(dead; horizon = 1, samples = 3, realizations = 2, seed = UInt64(9))
        @test res.values[1] == [1.0, 1.0, 1.0]
    end

    @testset "ssa_model loaders" begin
        d = JSON.parse("""{"places":[{"id":"a","initial":2,"capacity":5}],
                           "transitions":[{"id":"t"},{"id":"u","rate":0.5}],
                           "arcs":[{"from":"a","to":"t"},{"from":"a","to":"u","type":"inhibitor","weight":3,"kinetic":false}]}""")
        m = ssa_model(d)
        @test m.places[1].capacity == 5
        @test m.transitions[1].rate == 1.0 && m.transitions[2].rate == 0.5
        @test m.arcs[2].kind == :inhibitor && m.arcs[2].weight == 3 && m.arcs[2].kinetic == false
        @test_throws ErrorException ssa_model(JSON.parse("""{"places":[{"id":"a","kind":"data"}],"transitions":[],"arcs":[]}"""))
        @test_throws ErrorException ssa_model(JSON.parse("""{"places":[],"transitions":[{"id":"t","guard":"x > 0"}],"arcs":[]}"""))
        @test_throws ErrorException ssa_model(JSON.parse("""{"places":[{"id":"a"}],"transitions":[{"id":"t"}],"arcs":[{"from":"t","to":"a","type":"read"}]}"""))

        net = Pflow()
        place!(net, "a"; initial = 100)
        place!(net, "b"; initial = 0)
        place!(net, "c"; initial = 0)
        transition!(net, "ab")
        transition!(net, "bc")
        arc!(net; source = "a", target = "ab")
        arc!(net; source = "ab", target = "b")
        arc!(net; source = "b", target = "bc")
        arc!(net; source = "bc", target = "c")
        from_net = ssa_model(net; place_order = ["a", "b", "c"], transition_order = ["ab", "bc"])
        want = simulate_ssa(chain; horizon = 10, samples = 11, realizations = 3, seed = UInt64(42))
        got = simulate_ssa(from_net; horizon = 10, samples = 11, realizations = 3, seed = UInt64(42))
        @test got.values == want.values && got.stddev == want.stddev
    end

    @testset "Pflow read arc (guard! transition→place) survives ssa_model" begin
        # `guard!` marks BOTH contextual kinds `inhibit = true`; only the drawing
        # direction says which is which. A classifier keyed on `inhibit` alone
        # turned the read arc into an inhibitor written transition→place, which
        # `_compile` then silently dropped — hence this test.
        d = JSON.parse("""{"places":[{"id":"src","initial":20},{"id":"key","initial":1},
                                     {"id":"buf","initial":0,"capacity":3},{"id":"out","initial":0}],
                           "transitions":[{"id":"produce","rate":2},{"id":"consume","rate":1},{"id":"flip","rate":0.5}],
                           "arcs":[{"from":"src","to":"produce"},
                                   {"from":"key","to":"produce","type":"read"},
                                   {"from":"produce","to":"buf"},
                                   {"from":"buf","to":"consume"},
                                   {"from":"key","to":"consume","type":"inhibitor"},
                                   {"from":"consume","to":"out"},
                                   {"from":"key","to":"flip"}]}""")
        from_json = ssa_model(d)
        net = Pflow()
        place!(net, "src"; initial = 20)
        place!(net, "key"; initial = 1)
        place!(net, "buf"; initial = 0, capacity = 3)
        place!(net, "out"; initial = 0)
        transition!(net, "produce")
        transition!(net, "consume")
        transition!(net, "flip")
        arc!(net; source = "src", target = "produce")
        guard!(net, "produce", "key", 1)          # transition→place: read arc
        arc!(net; source = "produce", target = "buf")
        arc!(net; source = "buf", target = "consume")
        guard!(net, "key", "consume", 1)          # place→transition: inhibitor
        arc!(net; source = "consume", target = "out")
        arc!(net; source = "key", target = "flip")
        from_net = ssa_model(net; rates = Dict("produce" => 2.0, "consume" => 1.0, "flip" => 0.5),
                             place_order = ["src", "key", "buf", "out"],
                             transition_order = ["produce", "consume", "flip"])
        @test [(a.from, a.to, a.weight, a.kind) for a in from_net.arcs] ==
              [(a.from, a.to, a.weight, a.kind) for a in from_json.arcs]
        @test [p.capacity for p in from_net.places] == [0, 0, 3, 0]
        opts = (horizon = 10.0, samples = 21, realizations = 3, seed = UInt64(9))
        want = simulate_ssa(from_json; opts...)
        got = simulate_ssa(from_net; opts...)
        @test got.times == want.times && got.values == want.values &&
              got.stddev == want.stddev && got.final == want.final
        # The read arc is load-bearing: without it `produce` keeps firing after
        # `flip` has consumed the key, so a loader that drops it would diverge.
        without = SsaModel(from_json.places, from_json.transitions,
                           filter(a -> a.kind != :read, from_json.arcs))
        @test simulate_ssa(without; opts...).values != want.values
    end

    @testset "fixture parity (§4, §6.3)" begin
        files = filter(f -> endswith(f, ".json"), readdir(SSA_FIXTURES))
        @test Set(files) == Set(["chain.json", "sir.json", "dimer.json", "coffeeshop.json", "gates.json"])
        for file in sort(files)
            @testset "$file" begin
                doc = JSON.parsefile(joinpath(SSA_FIXTURES, file))
                model = ssa_model(doc["model"])
                o = doc["options"]
                res = simulate_ssa(model; horizon = Float64(o["horizon"]), samples = Int(o["samples"]),
                                   realizations = Int(o["realizations"]), seed = UInt64(o["seed"]))
                ex = doc["expected"]
                S = Int(o["samples"])
                @test length(res.times) == S
                @test length(ex["times"]) == S
                for i in 1:S
                    @test res.times[i] === Float64(ex["times"][i])
                end
                @test Set(keys(ex["series"])) == Set(res.places)
                @test Set(keys(ex["final"])) == Set(res.places)
                for (p, id) in enumerate(res.places)
                    want_v = ex["series"][id]["values"]
                    want_s = ex["series"][id]["stddev"]
                    @test length(want_v) == S && length(want_s) == S
                    mism = 0
                    for i in 1:S
                        res.values[p][i] === Float64(want_v[i]) || (mism += 1)
                        res.stddev[p][i] === Float64(want_s[i]) || (mism += 1)
                    end
                    @test mism == 0
                    @test res.final[p] === Float64(ex["final"][id])
                    @test res.final[p] === res.values[p][S]
                end
            end
        end
    end
end
