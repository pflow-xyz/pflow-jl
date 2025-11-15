# Example: Traffic Light System with Colored Petri Nets
#
# This example demonstrates a traffic light control system using colored Petri nets.
# Three colors represent different directions: North-South (red), East-West (green), Pedestrian (blue)

using PFlow: Pflow, place!, arc!, transition!, to_json, to_svg, to_html

function traffic_light_system()
    m = Pflow()
    
    # Define token colors for different traffic directions
    # Red = North-South traffic, Green = East-West traffic, Blue = Pedestrian
    m.token = ["#dc3545", "#28a745", "#007bff"]
    
    # Places
    # Initial state: NS has green (2 cars), EW has red (0 cars), Pedestrian has red (0)
    place!(m, "ns_green", initial=[2, 0, 0], x=100, y=200, label_text="NS Green")
    place!(m, "ns_red", initial=[0, 0, 0], x=100, y=400, label_text="NS Red")
    
    place!(m, "ew_red", initial=[0, 3, 0], x=400, y=200, label_text="EW Red")
    place!(m, "ew_green", initial=[0, 0, 0], x=400, y=400, label_text="EW Green")
    
    place!(m, "ped_red", initial=[0, 0, 1], x=250, y=100, label_text="Ped Red")
    place!(m, "ped_green", initial=[0, 0, 0], x=250, y=500, label_text="Ped Green")
    
    # Control token - indicates which phase is active
    place!(m, "timer", initial=1, x=250, y=300, label_text="Timer")
    
    # Transitions
    transition!(m, "ns_to_ew", x=250, y=200, label_text="NS→EW")
    transition!(m, "ew_to_ped", x=400, y=300, label_text="EW→Ped")
    transition!(m, "ped_to_ns", x=100, y=300, label_text="Ped→NS")
    
    # Phase 1: NS green -> EW green
    # When timer fires, move NS traffic to red, EW traffic to green
    arc!(m, source="timer", target="ns_to_ew", weight=1)
    arc!(m, source="ns_green", target="ns_to_ew", weight=[1, 0, 0])  # Take NS cars
    arc!(m, source="ew_red", target="ns_to_ew", weight=[0, 1, 0])    # Take EW cars
    
    arc!(m, source="ns_to_ew", target="timer", weight=1)
    arc!(m, source="ns_to_ew", target="ns_red", weight=[1, 0, 0])    # NS to red
    arc!(m, source="ns_to_ew", target="ew_green", weight=[0, 1, 0])  # EW to green
    
    # Phase 2: EW green -> Pedestrian green
    arc!(m, source="timer", target="ew_to_ped", weight=1)
    arc!(m, source="ew_green", target="ew_to_ped", weight=[0, 1, 0])
    arc!(m, source="ped_red", target="ew_to_ped", weight=[0, 0, 1])
    
    arc!(m, source="ew_to_ped", target="timer", weight=1)
    arc!(m, source="ew_to_ped", target="ew_red", weight=[0, 1, 0])
    arc!(m, source="ew_to_ped", target="ped_green", weight=[0, 0, 1])
    
    # Phase 3: Pedestrian green -> NS green
    arc!(m, source="timer", target="ped_to_ns", weight=1)
    arc!(m, source="ped_green", target="ped_to_ns", weight=[0, 0, 1])
    arc!(m, source="ns_red", target="ped_to_ns", weight=[1, 0, 0])
    
    arc!(m, source="ped_to_ns", target="timer", weight=1)
    arc!(m, source="ped_to_ns", target="ped_red", weight=[0, 0, 1])
    arc!(m, source="ped_to_ns", target="ns_green", weight=[1, 0, 0])
    
    return m
end

# Create the model
m = traffic_light_system()

# Export to JSON (can be imported into pflow.xyz/editor)
json_output = to_json(m)
println("=== JSON-LD Output ===")
println(json_output)

# Export to SVG
svg_output = to_svg(m)
println("\n=== SVG Output (first 800 chars) ===")
println(svg_output[1:min(800, length(svg_output))])
println("...")

# Model statistics
println("\n=== Model Statistics ===")
println("Places: $(length(m.places))")
println("Transitions: $(length(m.transitions))")
println("Arcs: $(length(m.arcs))")
println("Token colors: $(length(m.token))")

# Show colored token counts
println("\n=== Initial Token Distribution ===")
for (name, place) in m.places
    if !isempty(place.initial) && sum(place.initial) > 0
        tokens = place.initial
        println("$name: $tokens (total: $(sum(tokens)))")
    end
end
