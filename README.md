# PFlow-jl

Pflow provides a wrapper to build out Petri-net models for Petri.jl.

This wrapper makes it easier to compose Petri-nets with code, which allows faster iteration and more complex design.

See [Petri.jl](https://github.com/AlgebraicJulia/Petri.jl) for more details about model analysis.

## Status 

Beta - works but visualization needs polish

## Features
- Simplifies the composition of Petri-net models
- Enhances SVG output for visualization in IJulia / IPython Notebooks
- Pflow models convert to html, svg, json
- Export to Petri.jl Model for analysis

## Installation
To install PFlow.jl, use the following command in Julia:
```julia
using Pkg
Pkg.add(PackageSpec(url="https://github.com/pflow-xyz/pflow-jl.git"))
```

## Usage
Here is a basic example of how to use PFlow.jl to define a simple Petri net model for solving a knapsack problem:

```julia
#
# *** Build out the Model ***
#
using PFlow: Pflow, place!, arc!, transition!, to_state, to_json, to_model, set_rates

function knapsack!(m::Pflow)
    # Add places
    place!(m, "item0", initial=1, x=351, y=140)
    place!(m, "item1", initial=1, x=353, y=265)
    place!(m, "item2", initial=1, x=351, y=417)
    place!(m, "item3", initial=1, x=350, y=543)
    place!(m, "weight", x=880, y=320)
    place!(m, "value", x=765, y=145)
    place!(m, "capacity", initial=15, x=730, y=541)

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

m = Pflow()
knapsack!(m) # create the model

# Convert the model to JSON format
# NOTE: json format is compatible with pflow.xyz/editor
json_data = to_json(m)

# construct rates for transitions
rates = set_rates(m, (
    :txn0 => 1.0,
    :txn1 => 1.0,
    :txn2 => 0.0, # disable txn2
    :txn3 => 1.0
))

# calculate initial state of the model
initial_state = to_state(m)


# NOTE: Requires IJulia (run in Ipython notebook)see: ./example.ipynb
display(HTML(to_html(m))) # render the model

#
# *** Convert to ODE problem, solve and Graph ***
#
using Plots
using Petri
using LabelledArrays
using Plots
using OrdinaryDiffEq

# Convert the model to Petri.Model
petri_net = to_model(m)

time_max = 5.0
tspan = (0.0, time_max)

# convert to ODE problem
prob = ODEProblem(petri_net, initial_state, tspan, rates)
# create a solution
sol = solve(prob, Tsit5())

#graph 
plot(title="Knapsack Simulation", xlabel="Time", ylabel="Tokens", lw=2)
plot!(sol.t, sol[:value, :], label="Value")

value = round(sol[:value, end], digits=3)
annotate!(4, value, text("Value: $value", 10, :left))
```
