# PFlow-jl

Pflow provides a wrapper to build out Petri-net models for Petri.jl with support for colored Petri nets and JSON-LD output format.

This wrapper makes it easier to compose Petri-nets with code, which allows faster iteration and more complex design.

See [Petri.jl](https://github.com/AlgebraicJulia/Petri.jl) for more details about model analysis.

## Status 

Beta - works but visualization needs polish

## Features
- Simplifies the composition of Petri-net models
- **NEW: Parse JSON-LD format to construct Pflow models with `from_json()`**
- **NEW: Merge multiple models together with `merge()` or `+` operator**
- **NEW: Support for colored Petri nets with array-based token representations**
- **NEW: JSON-LD compatible output format matching pflow-xyz ecosystem**
- **NEW: Enhanced SVG output with CSS styling matching pflow-xyz**
- Enhances SVG output for visualization in IJulia / IPython Notebooks
- Pflow models convert to html, svg, json
- Export to Petri.jl Model for analysis (colored nets automatically sum to token counts)
- Compatible with [pflow.xyz/editor](https://pflow.xyz/editor)

## What's New

### JSON-LD Parsing
Parse JSON-LD format from pflow.xyz directly into Pflow models:
```julia
json_str = """{ "@type": "PetriNet", "places": {...}, "transitions": {...} }"""
model = from_json(json_str)
```
Supports all pflow.xyz JSON-LD fields including places, transitions, arcs, token colors, and inhibitor arcs.

### Model Merging
Combine multiple Pflow models into one:
```julia
# Using merge function
combined = merge(model1, model2)

# Or using + operator
combined = model1 + model2
```
Automatically handles name conflicts and preserves all model properties including token colors and inhibitor arcs.

### Colored Petri Nets
Places, transitions, and arcs now support array-based data for colored tokens:
- `Place.initial`: `Vector{Int}` for multi-color token counts
- `Place.capacity`: `Vector{Float64}` for color-specific capacity limits
- `Arc.weight`: `Vector{Int}` for color-specific arc weights
- `Pflow.token`: `Vector{String}` for token color definitions (URLs or hex colors)

### JSON-LD Format
JSON output now includes `@type` fields for semantic web compatibility and matches the pflow-xyz data format.

See [COLORED_PETRI_NETS.md](COLORED_PETRI_NETS.md) for detailed documentation on colored nets and [USAGE_GUIDE.md](USAGE_GUIDE.md) for JSON-LD parsing and model merging examples.

## Installation
To install PFlow.jl, use the following command in Julia:
```julia
using Pkg
Pkg.add(PackageSpec(url="https://github.com/pflow-xyz/pflow-jl.git"))
```

### Known Issue with Julia 1.12
There is a compatibility issue with the Petri.jl dependency and Julia 1.12. After installation, you may need to apply a workaround. See [WORKAROUND.md](WORKAROUND.md) for details.

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

## Parsing JSON-LD and Model Merging

### Parse JSON-LD from pflow.xyz

```julia
using PFlow: from_json

# JSON-LD string from pflow.xyz
json_str = """{
  "@context": "https://pflow.xyz/schema",
  "@type": "PetriNet",
  "@version": "1.1",
  "places": {
    "p1": {
      "@type": "Place",
      "capacity": [10],
      "initial": [5],
      "x": 100,
      "y": 100
    }
  },
  "transitions": {
    "t1": {
      "@type": "Transition",
      "x": 200,
      "y": 100
    }
  },
  "arcs": [
    {
      "@type": "Arrow",
      "source": "p1",
      "target": "t1",
      "weight": [1],
      "inhibitTransition": false
    }
  ],
  "token": ["https://pflow.xyz/tokens/black"]
}"""

# Parse into a Pflow model
model = from_json(json_str)
```

### Merge Multiple Models

```julia
using PFlow: Pflow, place!, transition!, arc!, merge

# Create producer model
producer = Pflow()
place!(producer, "source", initial=10, x=50, y=100)
transition!(producer, "produce", x=100, y=100)
arc!(producer, source="source", target="produce", weight=1)

# Create consumer model
consumer = Pflow()
place!(consumer, "sink", initial=0, x=200, y=100)
transition!(consumer, "consume", x=150, y=100)
arc!(consumer, source="sink", target="consume", weight=1)

# Merge models
pipeline = merge(producer, consumer)
# Or use + operator: pipeline = producer + consumer

# The merged model contains all places, transitions, and arcs
# Name conflicts are automatically resolved with suffixes
```

See [examples/json_and_merge_example.jl](examples/json_and_merge_example.jl) for more examples.
```
