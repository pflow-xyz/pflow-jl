# Manual Verification Guide

This guide demonstrates the new JSON-LD parsing and model merging functionality.

## Feature 1: Parsing JSON-LD Format

### Usage Example

```julia
using pflow

# JSON-LD string in pflow.xyz format
json_str = """{
  "@context": "https://pflow.xyz/schema",
  "@type": "PetriNet",
  "@version": "1.1",
  "places": {
    "place0": {
      "@type": "Place",
      "capacity": [3],
      "initial": [1],
      "offset": 0,
      "x": 130,
      "y": 207
    }
  },
  "transitions": {
    "txn0": {
      "@type": "Transition",
      "x": 46,
      "y": 116
    }
  },
  "arcs": [
    {
      "@type": "Arrow",
      "inhibitTransition": false,
      "source": "txn0",
      "target": "place0",
      "weight": [1]
    }
  ],
  "token": ["https://pflow.xyz/tokens/black"]
}"""

# Parse the JSON-LD into a Pflow model
m = from_json(json_str)

# Access the parsed model
println("Model type: ", m.model_type)  # "PetriNet"
println("Version: ", m.version)        # "1.1"
println("Places: ", length(m.places))  # 1
println("Transitions: ", length(m.transitions))  # 1
println("Arcs: ", length(m.arcs))      # 1
```

### Roundtrip Conversion

```julia
# Create a model
m1 = Pflow()
place!(m1, "p1", initial=1, x=100, y=100)
transition!(m1, "t1", x=150, y=100)
arc!(m1, source="p1", target="t1", weight=1)

# Export to JSON-LD
json_str = to_json(m1)

# Parse it back
m2 = from_json(json_str)

# m2 now has the same structure as m1
```

## Feature 2: Model Merging

### Using merge() Function

```julia
using pflow

# Create first model
m1 = Pflow()
place!(m1, "input", initial=3, x=50, y=100)
transition!(m1, "process", x=100, y=100)
arc!(m1, source="input", target="process", weight=1)

# Create second model
m2 = Pflow()
place!(m2, "output", initial=0, x=200, y=100)
transition!(m2, "finalize", x=150, y=100)
arc!(m2, source="output", target="finalize", weight=1)

# Merge models
m3 = merge(m1, m2)

# m3 contains all elements from both models
println("Places: ", keys(m3.places))      # "input", "output"
println("Transitions: ", keys(m3.transitions))  # "process", "finalize"
println("Arcs: ", length(m3.arcs))        # 2
```

### Using + Operator

```julia
# Same as merge(), but with operator syntax
m3 = m1 + m2
```

### Handling Name Conflicts

```julia
# Create two models with conflicting names
m1 = Pflow()
place!(m1, "p1", initial=1, x=100, y=100)

m2 = Pflow()
place!(m2, "p1", initial=2, x=200, y=100)  # Same name!

# Merge - conflicts are resolved automatically
m3 = merge(m1, m2)

# m3 has both places with unique names
println(keys(m3.places))  # "p1", "p1_1"
```

### Merging Token Colors

```julia
m1 = Pflow()
m1.token = ["#ff0000", "#00ff00"]

m2 = Pflow()
m2.token = ["#0000ff", "#00ff00"]  # One duplicate

m3 = merge(m1, m2)

# Tokens are unioned
println(m3.token)  # ["#ff0000", "#00ff00", "#0000ff"]
```

## Supported JSON-LD Fields

The `from_json` function supports all fields from the pflow.xyz JSON-LD schema:

### Top Level
- `@context` - JSON-LD context URL (informational)
- `@id` - Content identifier (informational)
- `@type` - Model type (e.g., "PetriNet")
- `@version` - Schema version (e.g., "1.1")
- `token` - Array of token color URLs or hex colors

### Places
- `@type` - Always "Place"
- `offset` - Numeric offset
- `initial` - Array of initial token counts
- `capacity` - Array of capacity values
- `x`, `y` - Position coordinates
- `label` - Optional display label

### Transitions
- `@type` - Always "Transition"
- `offset` - Numeric offset
- `role` - Role string (default: "default")
- `x`, `y` - Position coordinates
- `label` - Optional display label

### Arcs
- `@type` - Always "Arrow"
- `source` - Source place or transition label
- `target` - Target place or transition label
- `weight` - Array of weight values
- `inhibitTransition` - Boolean flag for inhibitor arcs

## Inhibitor Arcs

Both parsing and merging correctly handle inhibitor arcs (guard arcs):

```julia
# Create model with inhibitor arc
m = Pflow()
place!(m, "p1", initial=5, x=100, y=100)
transition!(m, "t1", x=150, y=100)
guard!(m, "p1", "t1", 3)  # Inhibitor arc

# Export to JSON-LD
json_str = to_json(m)
# Contains: "inhibitTransition": true

# Parse back
m2 = from_json(json_str)
# Inhibitor property is preserved

# Merge with another model
m3 = merge(m, other_model)
# Inhibitor arcs are preserved in merged model
```

## Testing

Run the comprehensive test suite:

```julia
using Pkg
Pkg.test()
```

The test suite includes:
- Parsing the example JSON-LD from the problem statement
- Roundtrip conversion tests
- Basic model merging
- Name conflict resolution
- Token color merging
- Inhibitor arc preservation
- Complex model merging scenarios

## Error Handling

The implementation handles various edge cases:

1. **Missing fields**: Uses sensible defaults (e.g., empty arrays, default role)
2. **Name conflicts**: Automatically renames with `_1`, `_2` suffixes
3. **Arc references**: Updates references when places/transitions are renamed during merge
4. **Empty models**: Can merge empty models without errors

## Integration with pflow.xyz

The JSON-LD format is fully compatible with https://pflow.xyz/editor:

1. Create a model in Julia
2. Export with `to_json(model)`
3. Copy the JSON output to pflow.xyz/editor
4. Edit visually in the web editor
5. Copy JSON back
6. Parse with `from_json(json_str)`

This enables a seamless workflow between Julia code and visual editing.
