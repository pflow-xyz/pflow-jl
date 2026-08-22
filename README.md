# PFlow-jl

Pflow provides a builder for Petri-net models with colored tokens and JSON-LD output, and a bridge to [AlgebraicPetri.jl](https://github.com/AlgebraicJulia/AlgebraicPetri.jl) for categorical composition (open nets, pushouts) and mass-action ODEs.

This wrapper makes it easier to compose Petri-nets with code, which allows faster iteration and more complex design.

`to_model` returns an AlgebraicPetri `LabelledPetriNet` (it returned a `Petri.Model` before v0.2; Petri.jl pins Catlab ≤ 0.14 and cannot coexist with AlgebraicPetri).

## Status 

Beta - works but visualization needs polish

## Features
- Simplifies the composition of Petri-net models
- **NEW: Parse JSON-LD format to construct Pflow models with `from_json()`**
- Disjoint union of models with `merge()` / `+` (the **coproduct** — colliding labels are renamed, nothing is shared)
- **NEW: Compose models by gluing along shared boundary places with `glue()` (the **pushout**, via AlgebraicPetri's `oapply`)**
- **NEW: `open_net`, `incidence_matrix`, `is_p_invariant`, `is_event_graph`, `to_ode_problem`; contextual (read/inhibitor) arcs raise `ContextualArcError` instead of being silently consumed**
- **NEW: Support for colored Petri nets with array-based token representations**
- **NEW: JSON-LD compatible output format matching pflow-xyz ecosystem**
- **NEW: Enhanced SVG output with CSS styling matching pflow-xyz**
- Enhances SVG output for visualization in IJulia / IPython Notebooks
- Pflow models convert to html, svg, json
- Export to AlgebraicPetri `LabelledPetriNet` for analysis (colored nets automatically sum to token counts)
- Compatible with [pflow.xyz/editor](https://pflow.xyz/editor)

## What's New

### JSON-LD Parsing
Parse JSON-LD format from pflow.xyz directly into Pflow models:
```julia
json_str = """{ "@type": "PetriNet", "places": {...}, "transitions": {...} }"""
model = from_json(json_str)
```
Supports all pflow.xyz JSON-LD fields including places, transitions, arcs, token colors, and inhibitor arcs.

### Composition: coproduct vs pushout
`merge`/`+` is the **coproduct**: a disjoint union in which colliding labels are
renamed (`b` → `b_1`). Nothing is shared, so nothing is constrained — two
payment channels that both mention Bob's balance end up with two Bobs.

`glue` is the **pushout**: boundary places with the same port name become one
place. That is what composing channels *means*, and it is the operation that
can remove behaviour (a pushout identifies; a coproduct never does):

```julia
using pflow, AlgebraicPetri

ch(x, y) = begin                       # one settlement channel x -> y
    net = Pflow()
    place!(net, x; initial=100); place!(net, y; initial=100)
    place!(net, "pending_$x$y"; initial=0)
    transition!(net, "send_$x$y"); transition!(net, "settle_$x$y")
    arc!(net; source=x, target="send_$x$y"); arc!(net; source="send_$x$y", target="pending_$x$y")
    arc!(net; source="pending_$x$y", target="settle_$x$y"); arc!(net; source="settle_$x$y", target=y)
    net
end

parts = [:ch_ab => ch("a","b"), :ch_bc => ch("b","c"), :ch_ca => ch("c","a")]
ports = Dict(:ch_ab => ["a","b"], :ch_bc => ["b","c"], :ch_ca => ["c","a"])

cycle = glue(parts, ports)             # LabelledPetriNet: 6 places, 6 transitions
is_event_graph(cycle)                  # true  — one producer and one consumer per place
is_p_invariant(cycle, ones(Int, 6))    # true  — a + b + c + p_ab + p_bc + p_ca = const
from_labelled_petri_net(cycle)         # back to a Pflow for JSON-LD / the editor

parts[1][2] + parts[2][2] + parts[3][2] # coproduct: 9 places, with b_1 and c_1
```

`to_ode_problem(net, tspan; u0, rates)` wraps AlgebraicPetri's `vectorfield`.
Note that AlgebraicPetri uses chemical mass action (a weight-`w` input
contributes `M^w`), which differs from go-pflow's `flux = k·∏M` with weight
scaling consumption only; for unit-weight nets they agree.

### Model Merging (coproduct)
Combine multiple Pflow models into one disjoint union:
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

### Option 1: Using Docker (Recommended for Quick Start)

Run PFlow-jl with Jupyter notebook in a Docker container:

```bash
docker-compose up
```

Then open your browser to the URL displayed in the terminal. See [DOCKER.md](DOCKER.md) for detailed instructions.

### Option 2: Local Installation

To install PFlow.jl locally, use the following command in Julia:
```julia
using Pkg
Pkg.add(PackageSpec(url="https://github.com/pflow-xyz/pflow-jl.git"))
```

#### Version pins
AlgebraicPetri 0.10 / Catlab 0.17 fail to precompile on Julia 1.12 (an ambiguous
`collect` export). The project therefore pins AlgebraicPetri 0.9.2 with Catlab
0.16, which loads cleanly on Julia 1.11 and 1.12. Petri.jl is no longer a
dependency.

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
using AlgebraicPetri
using OrdinaryDiffEq
using Plots

# Convert the model to an AlgebraicPetri LabelledPetriNet
petri_net = to_model(m)

time_max = 5.0
tspan = (0.0, time_max)

rates = set_rates(m)
initial_state = set_state(m)
prob = to_ode_problem(m, tspan; u0=initial_state, rates=rates)   # wraps vectorfield(petri_net)
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
