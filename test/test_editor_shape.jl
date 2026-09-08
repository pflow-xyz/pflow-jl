# Editor-shape parse parity: pflow-jl's from_json must read the pflow.xyz
# editor shape exactly as go-pflow's parser does. The goldens under
# testdata/editor-shape are byte copies of go-pflow's
# parser/testdata/editor-shape (cmd/shape-goldens); each carries the input
# document and go-pflow's parsed colored net. Readers may stay plural; their
# answers may not.
using Test
using JSON
using pflow

@testset "editor-shape parse parity (go-pflow goldens)" begin
    dir = joinpath(@__DIR__, "testdata", "editor-shape")
    files = filter(f -> endswith(f, ".json"), readdir(dir))
    @test !isempty(files)
    for f in files
        g = JSON.parsefile(joinpath(dir, f))
        want = g["parsed"]
        net = from_json(g["input"])
        @testset "$f" begin
            @test net.token == String[String(t) for t in want["token"]]
            @test sort(collect(keys(net.places))) == sort(collect(keys(want["places"])))
            for (id, wp) in want["places"]
                p = net.places[id]
                @test Float64.(p.initial) == Float64.(wp["initial"])
                @test Float64.(p.capacity) == Float64.(wp["capacity"])
                @test Float64(p.x) == Float64(wp["x"])
                @test Float64(p.y) == Float64(wp["y"])
                @test something(p.label_text, "") == get(wp, "label", "")
            end
            @test sort(collect(keys(net.transitions))) == sort(collect(keys(want["transitions"])))
            for (id, wt) in want["transitions"]
                t = net.transitions[id]
                @test t.role == get(wt, "role", "default")
                @test Float64(t.x) == Float64(wt["x"])
                @test Float64(t.y) == Float64(wt["y"])
                @test something(t.label_text, "") == get(wt, "label", "")
            end
            @test length(net.arcs) == length(want["arcs"])
            for (a, wa) in zip(net.arcs, want["arcs"])
                @test a.source == wa["source"]
                @test a.target == wa["target"]
                @test Float64.(a.weight) == Float64.(wa["weight"])
                @test a.inhibit_transition == wa["inhibit"]
            end
        end
    end
end
