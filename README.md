# PFlow.jl

PFlow.jl provides a wrapper to build out Petri-net models for [Petri.jl](https://github.com/username/Petri.jl).

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
Pkg.add("PFlow")
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
    place!(m, "item0", 0, 1, nothing, 351, 140)
    place!(m, "item1", 1, 1, nothing, 353, 265)
    place!(m, "item2", 2, 1, nothing, 351, 417)
    place!(m, "item3", 3, 1, nothing, 350, 543)
    place!(m, "weight", 4, 0, nothing, 880, 320)
    place!(m, "value", 5, 0, nothing, 765, 145)
    place!(m, "capacity", 6, 15, nothing, 730, 541)

    # Add transitions
    transition!(m, "txn0", 1, "", 465, 139)
    transition!(m, "txn1", 2, "", 466, 264)
    transition!(m, "txn2", 3, "", 462, 418)
    transition!(m, "txn3", 4, "", 464, 542)

    # Add arcs
    arc!(m, "txn0", "weight", 2)
    arc!(m, "txn0", "value", 10)
    arc!(m, "txn1", "weight", 4)
    arc!(m, "item0", "txn0", 1)
    arc!(m, "txn1", "value", 10)
    arc!(m, "item1", "txn1", 1)
    arc!(m, "item2", "txn2", 1)
    arc!(m, "item3", "txn3", 1)
    arc!(m, "txn2", "weight", 6)
    arc!(m, "txn2", "value", 12)
    arc!(m, "txn3", "value", 18)
    arc!(m, "txn3", "weight", 9)
    arc!(m, "capacity", "txn0", 2)
    arc!(m, "capacity", "txn1", 4)
    arc!(m, "capacity", "txn2", 6)
    arc!(m, "capacity", "txn3", 9)
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
petri = to_model(m)

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
