# Example: Using JSON-LD Parsing and Model Merging

using pflow

println("=== Example 1: Parsing JSON-LD from pflow.xyz ===\n")

# This is the JSON-LD format used by pflow.xyz
json_example = """{
  "@context": "https://pflow.xyz/schema",
  "@id": "z2xFpT8KDD7FU8tiWSMcB8n6dxJriy2PtZJrcyCwHkn9fmug732",
  "@type": "PetriNet",
  "@version": "1.1",
  "arcs": [
    {
      "@type": "Arrow",
      "inhibitTransition": false,
      "source": "txn0",
      "target": "place0",
      "weight": [1]
    },
    {
      "@type": "Arrow",
      "inhibitTransition": false,
      "source": "place0",
      "target": "txn1",
      "weight": [3]
    },
    {
      "@type": "Arrow",
      "inhibitTransition": true,
      "source": "txn2",
      "target": "place0",
      "weight": [3]
    },
    {
      "@type": "Arrow",
      "inhibitTransition": true,
      "source": "place0",
      "target": "txn3",
      "weight": [1]
    }
  ],
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
  "token": [
    "https://pflow.xyz/tokens/black"
  ],
  "transitions": {
    "txn0": {
      "@type": "Transition",
      "x": 46,
      "y": 116
    },
    "txn1": {
      "@type": "Transition",
      "x": 227,
      "y": 112
    },
    "txn2": {
      "@type": "Transition",
      "x": 43,
      "y": 307
    },
    "txn3": {
      "@type": "Transition",
      "x": 235,
      "y": 306
    }
  }
}"""

# Parse the JSON-LD
model = from_json(json_example)

println("Parsed model from JSON-LD:")
println("  Type: $(model.model_type)")
println("  Version: $(model.version)")
println("  Places: $(length(model.places))")
println("  Transitions: $(length(model.transitions))")
println("  Arcs: $(length(model.arcs))")
println("  Regular arcs: $(length(filter(a -> !a.inhibit_transition, model.arcs)))")
println("  Inhibitor arcs: $(length(filter(a -> a.inhibit_transition, model.arcs)))")
println()

println("=== Example 2: Creating and Merging Models ===\n")

# Create a producer model
producer = Pflow()
producer.token = ["#ff0000"]
place!(producer, "source", initial=10, x=50, y=100, label_text="Source")
place!(producer, "buffer", initial=0, x=150, y=100, label_text="Buffer")
transition!(producer, "produce", x=100, y=100, label_text="Produce")
arc!(producer, source="source", target="produce", weight=1)
arc!(producer, source="produce", target="buffer", weight=1)

println("Producer model:")
println("  Places: $(collect(keys(producer.places)))")
println("  Transitions: $(collect(keys(producer.transitions)))")
println()

# Create a consumer model
consumer = Pflow()
consumer.token = ["#0000ff"]
place!(consumer, "buffer", initial=0, x=250, y=100, label_text="Buffer")  # Name conflict!
place!(consumer, "sink", initial=0, x=350, y=100, label_text="Sink")
transition!(consumer, "consume", x=300, y=100, label_text="Consume")
arc!(consumer, source="buffer", target="consume", weight=1)
arc!(consumer, source="consume", target="sink", weight=1)

println("Consumer model:")
println("  Places: $(collect(keys(consumer.places)))")
println("  Transitions: $(collect(keys(consumer.transitions)))")
println()

# Merge using the merge() function
pipeline1 = merge(producer, consumer)

println("Merged model (using merge):")
println("  Places: $(collect(keys(pipeline1.places)))")
println("  Transitions: $(collect(keys(pipeline1.transitions)))")
println("  Arcs: $(length(pipeline1.arcs))")
println("  Tokens: $(pipeline1.token)")
println()

# Or use the + operator
pipeline2 = producer + consumer

println("Merged model (using + operator):")
println("  Places: $(collect(keys(pipeline2.places)))")
println("  Transitions: $(collect(keys(pipeline2.transitions)))")
println()

println("=== Example 3: Roundtrip Conversion ===\n")

# Create a model
original = Pflow()
original.token = ["#00ff00", "#ff00ff"]
place!(original, "p1", initial=[2, 3], capacity=[10.0, 15.0], x=100, y=100, label_text="Place 1")
transition!(original, "t1", x=150, y=100, role="worker", label_text="Transition 1")
arc!(original, source="p1", target="t1", weight=[1, 2])
guard!(original, "p1", "t1", [5])  # Add inhibitor arc

# Convert to JSON-LD
json_str = to_json(original)
println("Exported to JSON-LD (first 200 chars):")
println("  $(json_str[1:min(200, length(json_str))])...")
println()

# Parse back
restored = from_json(json_str)

println("Restored from JSON-LD:")
println("  Tokens: $(restored.token)")
println("  Place p1 initial: $(restored.places["p1"].initial)")
println("  Place p1 capacity: $(restored.places["p1"].capacity)")
println("  Transition t1 role: $(restored.transitions["t1"].role)")
println("  Inhibitor arcs: $(length(filter(a -> a.inhibit_transition, restored.arcs)))")
println()

println("=== Example 4: Complex Pipeline ===\n")

# Create input stage
input_stage = Pflow()
place!(input_stage, "raw_data", initial=100, x=50, y=100)
transition!(input_stage, "validate", x=100, y=100)
arc!(input_stage, source="raw_data", target="validate", weight=1)

# Create processing stage
process_stage = Pflow()
place!(process_stage, "valid_data", initial=0, x=150, y=100)
transition!(process_stage, "transform", x=200, y=100)
arc!(process_stage, source="valid_data", target="transform", weight=1)

# Create output stage
output_stage = Pflow()
place!(output_stage, "processed_data", initial=0, x=250, y=100)
transition!(output_stage, "store", x=300, y=100)
arc!(output_stage, source="processed_data", target="store", weight=1)

# Build complete pipeline by merging all stages
complete_pipeline = input_stage + process_stage + output_stage

println("Complete pipeline:")
println("  Total places: $(length(complete_pipeline.places))")
println("  Total transitions: $(length(complete_pipeline.transitions))")
println("  Total arcs: $(length(complete_pipeline.arcs))")
println("  Places: $(collect(keys(complete_pipeline.places)))")
println()

println("✓ All examples completed successfully!")
