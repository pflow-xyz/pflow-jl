using Test
using Petri
using pflow: Pflow, place!, arc!, guard!, transition!, initial_state, to_json, to_svg, to_html, to_model, default_rates, set_rates

# Define a simple Petri net model to solve a knapsack problem
# Try the interactive version:
# https://pflow.dev/?cid=zb2rhZVDEDCs4V88q8SG93tLd1jqRhwQbgazwmSe8py49S5tZ
function knapsack!(m::Pflow)
    # Add places
    #        label,  id, initial, capacity, x,   y
    place!(m, "item0",    0, 1,  nothing, 351, 140)
    place!(m, "item1",    1, 1,  nothing, 353, 265)
    place!(m, "item2",    2, 1,  nothing, 351, 417)
    place!(m, "item3",    3, 1,  nothing, 350, 543)
    place!(m, "weight",   4, 0,  nothing, 880, 320)
    place!(m, "value",    5, 0,  nothing, 765, 145)
    place!(m, "capacity", 6, 15, nothing, 730, 541)

    # Add transitions
    #              label,  id,  role,   x,   y
    transition!(m, "txn0", 0, "role", 465, 139)
    transition!(m, "txn1", 1, "role", 466, 264)
    transition!(m, "txn2", 2, "role", 462, 418)
    transition!(m, "txn3", 3, "role", 464, 542)

    # Add arcs
    #         source, target, weight
    arc!(m, "txn0",     "weight", 2)
    arc!(m, "txn0",     "value", 10)
    arc!(m, "txn1",     "weight", 4)
    arc!(m, "item0",    "txn0",   1)
    arc!(m, "txn1",     "value", 10)
    arc!(m, "item1",    "txn1",   1)
    arc!(m, "item2",    "txn2",   1)
    arc!(m, "item3",    "txn3",   1)
    arc!(m, "txn2",     "weight", 6)
    arc!(m, "txn2",     "value", 12)
    arc!(m, "txn3",     "value", 18)
    arc!(m, "txn3",     "weight", 9)
    arc!(m, "capacity", "txn0",   2)
    arc!(m, "capacity", "txn1",   4)
    arc!(m, "capacity", "txn2",   6)
    arc!(m, "capacity", "txn3",   9)
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

        state = initial_state(m)
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
