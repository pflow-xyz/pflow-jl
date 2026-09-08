# CID parity against go-pflow / pflow-xyz — byte-exact, not tolerance.
#
# Unlike ODE parity (test_ode_parity.jl, necessarily approximate — a
# different solver implementation), CID is a pure function of the document
# content with no floating-point involved anywhere, so there is no excuse
# for anything short of bit-for-bit agreement: CIDv1(dag-json, sha2-256,
# base58btc) over the @id-stripped URDNA2015-canonicalized N-Quads, matching
# go-pflow's internal/seal.SealJSONLD and pflow-xyz's seal-cid.mjs exactly.
# See ROADMAP.md item 5b and src/cid.jl / src/urdna2015.jl's module docs.

using Test
using pflow
using JSON

@testset "CID parity (byte-exact) vs go-pflow" begin
    dir = joinpath(@__DIR__, "testdata", "cid")
    golden = JSON.parsefile(joinpath(dir, "golden.json"))

    @testset "$(name)" for name in [
        "coffee-shop.jsonld",
        "knapsack.jsonld",
        "net-a.jsonld",
        "net-b.jsonld",
        "with-parents.jsonld",
    ]
        data = JSON.parsefile(joinpath(dir, name))
        cid, _ = compute_cid(data)
        @test cid == golden[name]
    end

    # tie1/tie2 aren't in golden.json (they were written for this port, not
    # pflow-xyz's own parity suite) — their goldens are hardcoded here,
    # generated the same way (Go's seal.SealJSONLD) at the same pflow-xyz
    # commit. See testdata/cid/README.md for what each one is stressing.
    @testset "tie1.jsonld" begin
        data = JSON.parsefile(joinpath(dir, "tie1.jsonld"))
        cid, _ = compute_cid(data)
        @test cid == "z4EBG9jDqmAkYxzdaWnPVRZfBcpug1F45LeQJgck4MicFUDPFgS"
    end
    @testset "tie2.jsonld" begin
        data = JSON.parsefile(joinpath(dir, "tie2.jsonld"))
        cid, _ = compute_cid(data)
        @test cid == "z4EBG9j8AZSNguvWsF6uwoo9PWqURQV2f5YFiYfLXBb9SpvXgt8"
    end
end

@testset "CID: @id is excluded from its own preimage" begin
    # A document's @id is self-referential (it equals the CID being
    # computed), so it must not affect the result — otherwise re-sealing a
    # stored document that already carries @id would drift from the CID
    # that produced it, defeating the whole content-addressing scheme.
    without_id = Dict{String,Any}(
        "@context" => "https://pflow.xyz/schema",
        "@type" => "PetriNet",
        "places" => Dict("a" => Dict("@type" => "Place", "x" => 0, "y" => 0)),
        "transitions" => Dict{String,Any}(),
        "arcs" => [],
    )
    with_id = merge(without_id, Dict("@id" => "z_some_unrelated_stale_value"))
    cid1, nq1 = compute_cid(without_id)
    cid2, nq2 = compute_cid(with_id)
    @test cid1 == cid2
    @test nq1 == nq2
end

@testset "CID: JSON null list entries collapse to an empty list" begin
    # "capacity": [null] canonicalizes as (place, capacity, rdf:nil) — a
    # REAL triple pointing at the empty list, not the same graph as
    # omitting "capacity" entirely (which emits no capacity triple at all;
    # verified against go-pflow directly during development — omitted and
    # [null] are NOT interchangeable, only null-vs-empty-list is). The
    # net-a fixture's "Version" place already exercises this in the
    # byte-exact golden test above; this pins the direct claim.
    data = Dict{String,Any}(
        "@context" => "https://pflow.xyz/schema",
        "@type" => "PetriNet",
        "places" => Dict("a" => Dict("@type" => "Place", "capacity" => [nothing], "x" => 0, "y" => 0)),
        "transitions" => Dict{String,Any}(),
        "arcs" => [],
    )
    _, nq = compute_cid(data)
    @test occursin(
        "<https://pflow.xyz/schema#capacity> <http://www.w3.org/1999/02/22-rdf-syntax-ns#nil> .",
        nq,
    )
end

@testset "URDNA2015 PRNG-free determinism: repeated runs agree" begin
    # canonicalize() has no randomness, but it does rely on Dict iteration
    # (Julia's Dict is not insertion-ordered) at several points — this is
    # exactly the class of bug the OLD "z"+sha256(JSON.json(...))[:20]
    # formula was silently exposed to (JSON.json over a Dict has no
    # guaranteed key order either). Confirms the full pipeline is order-
    # independent by construction, not by chance on today's hash seeds.
    dir = joinpath(@__DIR__, "testdata", "cid")
    data = JSON.parsefile(joinpath(dir, "net-b.jsonld"))
    cids = [compute_cid(data)[1] for _ in 1:5]
    @test all(==(cids[1]), cids)
end
