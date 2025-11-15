# Colored Petri Nets Support

This document describes the colored Petri nets support added to pflow-jl to match the pflow-xyz data structures.

## Overview

The package now supports colored Petri nets through array-based data structures for places, transitions, and arcs. This allows for:
- Multiple token colors per place
- Color-specific arc weights
- JSON-LD compatible output format
- Full compatibility with pflow-xyz ecosystem

## Data Structure Changes

### Place
- `initial`: Changed from `Union{Nothing,Int}` to `Vector{Int}` - supports multiple colored tokens
- `capacity`: Changed from `Union{Nothing,Int}` to `Vector{Float64}` - supports color-specific capacity limits
- `label_text`: New optional field for custom display labels

### Transition
- `label_text`: New optional field for custom display labels

### Arc
- `weight`: Changed from `Union{Nothing,Int}` to `Vector{Int}` - supports color-specific weights
- `inhibit_transition`: New field for JSON-LD compatibility

### Pflow Model
- `token`: New `Vector{String}` field for token color definitions (URLs or hex colors)

## Usage Examples

### Basic Petri Net (Backward Compatible)

```julia
using PFlow: Pflow, place!, arc!, transition!, to_json, to_svg

m = Pflow()
place!(m, "p1", initial=2, x=100, y=100)  # Automatically converted to [2]
place!(m, "p2", initial=0, x=200, y=100)  # Automatically converted to [0]
transition!(m, "t1", x=150, y=100)
arc!(m, source="p1", target="t1", weight=1)  # Automatically converted to [1]
arc!(m, source="t1", target="p2", weight=1)
```

### Colored Petri Net

```julia
using PFlow: Pflow, place!, arc!, transition!, to_json, to_svg

m = Pflow()

# Define token colors
m.token = ["#ff0000", "#00ff00", "#0000ff"]  # Red, Green, Blue

# Places with colored tokens: [red_count, green_count, blue_count]
place!(m, "input", initial=[2, 1, 0], x=100, y=100)
place!(m, "output", initial=[0, 0, 0], x=200, y=100)

# Transition
transition!(m, "process", x=150, y=100)

# Arc with color-specific weights
arc!(m, source="input", target="process", weight=[1, 1, 0])  # Consume 1 red, 1 green
arc!(m, source="process", target="output", weight=[0, 0, 2])  # Produce 2 blue
```

### With Custom Labels

```julia
m = Pflow()
place!(m, "p1", initial=5, x=100, y=100, label_text="Input Queue")
transition!(m, "t1", x=150, y=100, label_text="Process")
place!(m, "p2", initial=0, x=200, y=100, label_text="Output Queue")
```

## JSON-LD Output Format

The `to_json()` function now outputs JSON-LD compatible format:

```json
{
  "modelType": "petriNet",
  "version": "v0",
  "places": {
    "p1": {
      "@type": "Place",
      "offset": 0,
      "initial": [2],
      "capacity": [],
      "x": 100,
      "y": 100
    }
  },
  "transitions": {
    "t1": {
      "@type": "Transition",
      "role": "default",
      "offset": 0,
      "x": 150,
      "y": 100
    }
  },
  "arcs": [
    {
      "@type": "Arc",
      "source": "p1",
      "target": "t1",
      "weight": [1]
    }
  ],
  "token": []
}
```

## SVG Rendering

The SVG output has been updated to match pflow-xyz styles:
- CSS classes for styling (`.place`, `.transition`, `.arc`, etc.)
- Proper viewBox calculation with padding
- Token count display (sum of array values for colored nets)
- Weight badges on arcs
- Support for custom labels

## ODE Conversion

For ODE analysis (Petri.jl integration), colored token arrays are automatically summed:
- `place.initial = [2, 1, 3]` becomes `6` tokens in the ODE model
- `arc.weight = [1, 0, 2]` becomes weight `3` in the ODE model

This allows colored Petri nets to be analyzed using standard ODE solvers while maintaining the rich colored net representation in JSON and SVG.

```julia
using Petri, OrdinaryDiffEq

m = Pflow()
# ... build colored net ...

# Convert to ODE (arrays are summed automatically)
petri_model = to_model(m)
initial_state = set_state(m)  # Sums colored tokens
rates = set_rates(m)

# Solve as usual
prob = ODEProblem(petri_model, initial_state, (0.0, 10.0), rates)
sol = solve(prob, Tsit5())
```

## Compatibility

### Backward Compatibility
All existing code continues to work. Scalar values for `initial`, `capacity`, and `weight` are automatically converted to single-element arrays.

### pflow-xyz Compatibility
The JSON-LD output format matches the pflow-xyz Go implementation and can be:
- Imported into pflow-xyz/editor
- Processed by pflow-xyz/pflow-xyz tools
- Stored in IPFS with compatible schemas
