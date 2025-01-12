using Test
using Petri
using pflow: Pflow, place!, arc!, guard!, transition!, initial_state, to_json, to_svg, to_html, to_model, set_state, set_rates

# Define a simple Petri net model to solve a knapsack problem
# Try the interactive version:
# https://pflow.dev/?cid=zb2rhZVDEDCs4V88q8SG93tLd1jqRhwQbgazwmSe8py49S5tZ
function knapsack!(m::Pflow)
    # Add places
    place!(m, "item0", initial=1, x=351, y=140)
    place!(m, "item1", initial=1, x=353, y=265)
    place!(m, "item2", initial=1, x=351, y=417)
    place!(m, "item3", initial=1, x=350, y=543)
    place!(m, "weight", initial=0, x=880, y=320)
    place!(m, "value", initial=0, x=765, y=145)
    place!(m, "capacity", initial=15, x=730, y=541)

    # Add transitions
    transition!(m, "txn0", x=465, y=139)
    transition!(m, "txn1", x=466, y=264)
    transition!(m, "txn2", x=462, y=418)
    transition!(m, "txn3", x=464, y=542)

    # Add arcs
    arc!(m, source="txn0", target="weight", weight=2)
    arc!(m, source="txn0", target="value", weight=10)
    arc!(m, source="txn1", target="weight", weight=4)
    arc!(m, source="item0", target="txn0", weight=1)
    arc!(m, source="txn1", target="value", weight=10)
    arc!(m, source="item1", target="txn1", weight=1)
    arc!(m, source="item2", target="txn2", weight=1)
    arc!(m, source="item3", target="txn3", weight=1)
    arc!(m, source="txn2", target="weight", weight=6)
    arc!(m, source="txn2", target="value", weight=12)
    arc!(m, source="txn3", target="value", weight=18)
    arc!(m, source="txn3", target="weight", weight=9)
    arc!(m, source="capacity", target="txn0", weight=2)
    arc!(m, source="capacity", target="txn1", weight=4)
    arc!(m, source="capacity", target="txn2", weight=6)
    arc!(m, source="capacity", target="txn3", weight=9)
end

@testset "Pflow Model Tests" begin
    
    @testset "Petri Net Model" begin
        m = Pflow()
        knapsack!(m)

        time_max = 5.0
        tspan = (0.0, time_max)

        #rates = default_rates(m)
        rates = set_rates(m, (
            :txn0 => 1.0,
            :txn1 => 1.0,
            :txn2 => 0.0, # disable txn2
            :txn3 => 1.0
        ))

        @test rates[:txn0] == 1
        @test rates[:txn1] == 1
        @test rates[:txn2] == 0 # txn2 is disabled
        @test rates[:txn3] == 1

        state = set_state(m)
        @test state[:item0] == 1
        @test state[:item1] == 1
        @test state[:item2] == 1
        @test state[:item3] == 1
        @test state[:weight] == 0
        @test state[:value] == 0
        @test state[:capacity] == 15

        petri = to_model(m)
        @test isa(petri, Petri.Model)

        # REVIEW: copy and paste json to pflow.xyz/editor to simulate network
        json_data = to_json(m)
        # test it starts with {"modelType":"petriNet
        @test startswith(json_data, "{\"modelType\":\"petriNet")

        svg_data = to_svg(m)
        # test it starts with <svg
        @test startswith(svg_data, "<svg")

        html_data = to_html(m)
        # test it starts with <!DOCTYPE html>
        @test startswith(html_data, "<!DOCTYPE html>")
        # REVIEW: see example.ipynb in this repo to see how to use Petri.Model
        # with OrdinaryDiffEq and Plots to simulate and analyze this model
    end

end
