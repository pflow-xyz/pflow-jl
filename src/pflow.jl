module pflow

using JSON
using LabelledArrays
using Petri
using Base64
using SHA

# Export main types
export Pflow, StateMachine, Place, Transition, Arrow

# Export builder functions  
export place!, transition!, arc!, guard!

# Export conversion functions
export to_json, to_svg, to_html, to_model, to_state, set_state, set_rates, set_state!, set_rates!

# Export state machine functions
export transform!

struct Place
    label::String
    offset::Int
    initial::Vector{Int}  # Changed to array for colored Petri nets
    capacity::Vector{Float64}  # Changed to array for colored Petri nets
    x::Int
    y::Int
    label_text::Union{Nothing,String}  # Optional label for display
end

struct Transition
    label::String
    offset::Int
    role::String
    x::Int
    y::Int
    label_text::Union{Nothing,String}  # Optional label for display
end

struct Arrow
    source::String
    target::String
    weight::Vector{Int}  # Changed to array for colored Petri nets
    consume::Union{Nothing,Bool}
    produce::Union{Nothing,Bool}
    inhibit::Union{Nothing,Bool}
    read::Union{Nothing,Bool}
    inhibit_transition::Bool  # Renamed for JSON-LD compatibility
end

mutable struct Pflow
    model_type::String
    version::String
    places::Dict{String,Place}
    transitions::Dict{String,Transition}
    arcs::Vector{Arrow}
    token::Vector{String}  # Array of token color URLs or hex colors for colored Petri nets
end

mutable struct StateMachine
    model::Pflow
    state
    rates
end

function StateMachine(m::Pflow)
    StateMachine(m, set_state(m), set_rates(m))
end

function to_model(sm::StateMachine)::Petri.Model
    to_model(sm.model)
end

function set_rates!(sm::StateMachine, rates)
    sm.rates = set_rates(sm.model, rates)
end

function set_state!(sm::StateMachine, state)
    sm.state = set_state(sm.model, state)
end

function transform!(sm::StateMachine, action::Symbol, multiple=1)
    new_state = copy(sm.state)
    for arc in sm.model.arcs
        t = Symbol(arc.target)
        s = Symbol(arc.source)
        # Sum array weights for state transformation
        weight_sum = isempty(arc.weight) ? 1 : sum(arc.weight)
        if t == action
            #println("$s -> $t")
            new_state[s] -= weight_sum * multiple
            if new_state[s] < 0
                return false
            end
        elseif s == action
            #println("$s -> $t")
            new_state[t] += weight_sum * multiple
        end
    end
    sm.state = new_state
    return true
end

function Pflow()
    Pflow("petriNet", "v0", Dict(), Dict(), [], String[])
end

function place!(net::Pflow, label::String; offset::Union{Nothing,Int}=nothing, initial::Union{Nothing,Int,Vector{Int}}=nothing, capacity::Union{Nothing,Int,Float64,Vector{Float64}}=nothing, x::Int=0, y::Int=0, label_text::Union{Nothing,String}=nothing)
    offset = isnothing(offset) ? length(net.transitions) : offset
    
    # Convert scalar to array for colored Petri net compatibility
    initial_arr = if isnothing(initial)
        Int[]
    elseif isa(initial, Vector)
        initial
    else
        [initial]
    end
    
    capacity_arr = if isnothing(capacity)
        Float64[]
    elseif isa(capacity, Vector)
        capacity
    else
        [Float64(capacity)]
    end
    
    net.places[label] = Place(label, offset, initial_arr, capacity_arr, x, y, label_text)
end

function transition!(net::Pflow, label::String; offset::Union{Nothing,Int}=nothing, role::String="default", x::Int=0, y::Int=0, label_text::Union{Nothing,String}=nothing)
    offset = isnothing(offset) ? length(net.transitions) : offset
    net.transitions[label] = Transition(label, offset, role, x, y, label_text)
end

function arc!(net::Pflow; source::String="", target::String="", weight::Union{Nothing,Int,Vector{Int}}=1)
    # Convert scalar to array for colored Petri net compatibility
    weight_arr = if isnothing(weight)
        [1]
    elseif isa(weight, Vector)
        weight
    else
        [weight]
    end
    
    # set consume if source is a place and target is a transition
    consume = haskey(net.places, source) && haskey(net.transitions, target)
    # set produce if source is a transition and target is a place
    produce = haskey(net.transitions, source) && haskey(net.places, target)
    inhibit = false
    read = false
    inhibit_transition = false
    push!(net.arcs, Arrow(source, target, weight_arr, consume, produce, inhibit, read, inhibit_transition))
end

function guard!(net::Pflow, source::String, target::String, weight::Union{Nothing,Int,Vector{Int}})
    # Convert scalar to array for colored Petri net compatibility
    weight_arr = if isnothing(weight)
        [1]
    elseif isa(weight, Vector)
        weight
    else
        [weight]
    end
    
    # set consume if source is a place and target is a transition
    consume = haskey(net.places, source) && haskey(net.transitions, target)
    # set produce if source is a transition and target is a place
    produce = haskey(net.transitions, source) && haskey(net.places, target)
    inhibit = true
    read = haskey(net.transitions, source) && haskey(net.places, target)
    inhibit_transition = true

    push!(net.arcs, Arrow(source, target, weight_arr, consume, produce, inhibit, read, inhibit_transition))
end

function set_state(pflow::Pflow)
    fields = Dict{Symbol, Number}()
    for (label, place) in pflow.places
        # Sum array values for ODE conversion (colored nets collapse to counts)
        fields[Symbol(label)] = isempty(place.initial) ? 0 : sum(place.initial)
    end
    return LVector(; fields...)
end

function set_state(pflow::Pflow, state)
    fields = Dict{Symbol, Number}()
    for (label, _) in pflow.places
        if ! haskey(state, label)
            error("Place $label not found in the state")
        end
        fields[Symbol(label)] = state[label]
    end
    return LVector(; fields...)
end

function set_rates(pflow::Pflow)
    fields = Dict{Symbol, Number}()
    for (label, _) in pflow.transitions
        fields[Symbol(label)] = 1
    end
    return LVector(; fields...)
end

function set_rates(pflow::Pflow, rates)
    fields = Dict{Symbol, Number}()
    for (label, _) in pflow.transitions
        fields[Symbol(label)] = 1
    end
    for (label, rate) in rates
        if ! haskey(pflow.transitions, string(label))
            error("Transition $label not found in the model")
        end
        fields[Symbol(label)] = rate
    end
    return LVector(; fields...)
end

function to_model(pflow::Pflow)::Petri.Model
    states = Symbol[]
    transitions = Dict{Symbol, Tuple{Dict{Symbol, Number}, Dict{Symbol, Number}}}()

    # Collect states from places
    for (label, _) in pflow.places
        push!(states, Symbol(label))
    end

    # Collect transitions
    for (label, _) in pflow.transitions
        input_places = Dict{Symbol, Number}()
        output_places = Dict{Symbol, Number}()

        # Find input places (arcs where the transition is the target)
        for arc in pflow.arcs
            if arc.target == label
                # Sum array weights for ODE conversion (colored nets collapse to counts)
                weight_sum = isempty(arc.weight) ? 1 : sum(arc.weight)
                input_places[Symbol(arc.source)] = weight_sum
            end
            if arc.source == label
                # Sum array weights for ODE conversion (colored nets collapse to counts)
                weight_sum = isempty(arc.weight) ? 1 : sum(arc.weight)
                output_places[Symbol(arc.target)] = weight_sum
            end
        end

        transitions[Symbol(label)] = (input_places, output_places)
    end

    return Petri.Model(states, transitions)
end

function to_json(net::Pflow)::String
    places_dict = Dict{String, Any}()
    for (k, v) in net.places
        place_obj = Dict{String, Any}(
            "@type" => "Place",
            "offset" => v.offset,
            "initial" => v.initial,
            "capacity" => v.capacity,
            "x" => v.x,
            "y" => v.y
        )
        if !isnothing(v.label_text)
            place_obj["label"] = v.label_text
        end
        places_dict[k] = place_obj
    end
    
    transitions_dict = Dict{String, Any}()
    for (k, v) in net.transitions
        trans_obj = Dict{String, Any}(
            "@type" => "Transition",
            "role" => v.role,
            "offset" => v.offset,
            "x" => v.x,
            "y" => v.y
        )
        if !isnothing(v.label_text)
            trans_obj["label"] = v.label_text
        end
        transitions_dict[k] = trans_obj
    end
    
    arcs_arr = []
    for arc in net.arcs
        arc_obj = Dict{String, Any}(
            "@type" => "Arrow",
            "source" => arc.source,
            "target" => arc.target,
            "weight" => arc.weight,
            "inhibitTransition" => arc.inhibit_transition
        )
        push!(arcs_arr, arc_obj)
    end
    
    # Create the data structure first without @id to compute hash
    data = Dict{String, Any}(
        "places" => places_dict,
        "transitions" => transitions_dict,
        "arcs" => arcs_arr,
        "token" => net.token
    )
    
    # Generate a content identifier (CID) from the JSON data
    data_json = JSON.json(data)
    hash_bytes = sha256(data_json)
    cid = "z" * bytes2hex(hash_bytes[1:20])  # Use first 20 bytes for shorter ID
    
    # Add JSON-LD fields
    result = Dict{String, Any}(
        "@context" => "https://pflow.xyz/schema",
        "@id" => cid,
        "@type" => "PetriNet",
        "@version" => "1.1",
        "places" => places_dict,
        "transitions" => transitions_dict,
        "arcs" => arcs_arr,
        "token" => net.token
    )
    
    JSON.json(result)
end

function urlencode(str::String)::String
    # URL encode a string by converting each character
    result = IOBuffer()
    for c in str
        if c in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
            write(result, c)
        else
            # Convert to hex
            write(result, '%')
            write(result, uppercase(string(Int(c), base=16, pad=2)))
        end
    end
    return String(take!(result))
end

function to_pflow_url(net::Pflow)::String
    json_str = to_json(net)
    
    # URL encode the JSON data
    encoded_data = urlencode(json_str)
    
    return "https://pflow.xyz/?data=$(encoded_data)"
end

mutable struct Display
    buffer::IOBuffer
    model::Pflow
end

function Display(model::Pflow)
    Display(IOBuffer(), model)
end

function new_svg_image(d::Display, width::Union{Int,Nothing}=nothing, height::Union{Int,Nothing}=nothing)
    w = isnothing(width) ? 400 : width
    h = isnothing(height) ? 400 : height
    write(d.buffer, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 $w $h\" width=\"$w\" height=\"$h\">")
    write_defs(d)
end

function write_defs(d::Display)
    write(
        d.buffer,
        """<defs>
<style>
.place { fill: #fff; stroke: #333; stroke-width: 2; }
.place-cap-full { fill: #ffebee; }
.transition { fill: #ffffff; stroke: #000; stroke-width: 1; }
.transition-active { fill: #62fa75; stroke: #000; }
.arc { stroke: #cfcfcf; stroke-width: 1; fill: none; }
.arc-active { stroke: #2a6fb8; }
.arrowhead { fill: #cfcfcf; }
.arrowhead-active { fill: #2a6fb8; }
.inhibitor { fill: #fff; stroke: #cfcfcf; stroke-width: 1.3; }
.inhibitor-active { stroke: #2a6fb8; }
.token-dot { fill: #333; }
.token-text { font-family: system-ui, Arial; font-size: 12px; fill: #333; text-anchor: middle; dominant-baseline: middle; }
.weight-badge { font-family: system-ui, Arial; font-size: 10px; fill: #666; text-anchor: middle; dominant-baseline: middle; }
.weight-bg { fill: #fafafa; stroke: #ddd; stroke-width: 1; }
.weight-bg-active { fill: #e8f0fb; stroke: #2a6fb8; }
.label-text { font-family: system-ui, Arial; font-size: 11px; fill: #333; text-anchor: middle; dominant-baseline: hanging; }
</style>
</defs>
"""
    )
end

function gend(d::Display)
    write_element(d, "</g>")
end

function write_element(d::Display, element::String)
    write(d.buffer, element)
end

# Helper function to check if a transition is enabled
function is_transition_enabled(model::Pflow, transition_label::String)::Bool
    # A transition is enabled if all input places have sufficient tokens
    for arc in model.arcs
        # Check if this arc goes from a place to this transition (consume arc)
        if arc.target == transition_label && haskey(model.places, arc.source)
            place = model.places[arc.source]
            # Sum tokens in the place
            tokens = isempty(place.initial) ? 0 : sum(place.initial)
            # Sum weight required by the arc
            weight = isempty(arc.weight) ? 1 : sum(arc.weight)
            
            # If not enough tokens, transition is not enabled
            if tokens < weight
                return false
            end
        end
    end
    return true
end

function render(d::Display)
    for arc in d.model.arcs
        arc_element(d, arc)
    end
    for (label, place) in d.model.places
        place_element(d, label, place)
    end
    for (label, transition) in d.model.transitions
        transition_element(d, label, transition)
    end
    end_svg(d)
end

function place_element(d::Display, label::String, place::Place)
    group(d)
    
    # Sum array values for display (colored nets collapse to counts)
    tokens = isempty(place.initial) ? 0 : sum(place.initial)
    
    # Check if place is at capacity
    capacity = isempty(place.capacity) ? Inf : place.capacity[1]
    is_full = capacity != Inf && tokens >= capacity
    
    place_class = is_full ? "place place-cap-full" : "place"
    circle(d, place.x, place.y, 16, "class=\"$place_class\"")
    
    # Display label (use label_text if available, otherwise use label)
    # Position label below the place circle
    display_label = isnothing(place.label_text) ? label : place.label_text
    text(d, place.x, place.y + 28, display_label, "class=\"label-text\"")
    
    x = place.x
    y = place.y
    
    if tokens > 0
        if tokens == 1
            circle(d, x, y, 2, "class=\"token-dot\"")
        else
            text(d, x, y, string(tokens), "class=\"token-text\"")
        end
    end
    
    gend(d)
end

function arc_element(d::Display, arc::Arrow)
    group(d)
    
    # Determine source and target positions
    if haskey(d.model.places, arc.source)
        p = d.model.places[arc.source]
        t = d.model.transitions[arc.target]
        src_x, src_y = p.x, p.y
        trg_x, trg_y = t.x, t.y
        src_is_place = true
    else
        p = d.model.places[arc.target]
        t = d.model.transitions[arc.source]
        src_x, src_y = t.x, t.y
        trg_x, trg_y = p.x, p.y
        src_is_place = false
    end
    
    # Calculate arc endpoints with padding
    pad_src = src_is_place ? 18 : 17
    pad_trg = src_is_place ? 17 : 18
    
    dx = trg_x - src_x
    dy = trg_y - src_y
    dist = sqrt(dx*dx + dy*dy)
    if dist == 0
        dist = 1
    end
    ux = dx / dist
    uy = dy / dist
    
    tip_offset = arc.inhibit_transition ? 8 : 7.2
    ex = src_x + ux * pad_src
    ey = src_y + uy * pad_src
    fx = trg_x - ux * (pad_trg + tip_offset)
    fy = trg_y - uy * (pad_trg + tip_offset)
    
    # Draw arc line
    line(d, Int(round(ex)), Int(round(ey)), Int(round(fx)), Int(round(fy)), "class=\"arc\"")
    
    # Draw arrowhead or inhibitor
    if arc.inhibit_transition
        circle(d, Int(round(fx)), Int(round(fy)), 6, "class=\"inhibitor\"")
    else
        # Draw arrowhead
        ahx = fx + (-ux * 8 - uy * 3.6)
        ahy = fy + (-uy * 8 + ux * 3.6)
        bhx = fx + (-ux * 8 + uy * 3.6)
        bhy = fy + (-uy * 8 - ux * 3.6)
        write_element(d, "<path d=\"M $(Int(round(fx))) $(Int(round(fy))) L $(Int(round(ahx))) $(Int(round(ahy))) L $(Int(round(bhx))) $(Int(round(bhy))) Z\" class=\"arrowhead\"/>")
    end
    
    # Draw weight badge
    mid_x = (ex + fx) / 2
    mid_y = (ey + fy) / 2
    
    # Sum array weights for display
    weight = isempty(arc.weight) ? 1 : sum(arc.weight)
    
    circle(d, Int(round(mid_x)), Int(round(mid_y)), 10, "class=\"weight-bg\"")
    text(d, Int(round(mid_x)), Int(round(mid_y)), string(weight), "class=\"weight-badge\"")
    
    gend(d)
end

function transition_element(d::Display, label::String, transition::Transition)
    group(d)
    x, y = transition.x - 15, transition.y - 15
    
    # Check if transition is enabled
    is_enabled = is_transition_enabled(d.model, label)
    transition_class = is_enabled ? "transition transition-active" : "transition"
    
    rect(d, x, y, 30, 30, "class=\"$transition_class\" rx=\"4\"")
    
    # Display label (use label_text if available, otherwise use label)
    # Position label below the transition rectangle
    display_label = isnothing(transition.label_text) ? label : transition.label_text
    text(d, transition.x, transition.y + 28, display_label, "class=\"label-text\"")
    gend(d)
end

function end_svg(d::Display)
    write(d.buffer, "</svg>")
end

function to_html(d::Display)::String
    # Generate pflow.xyz URL
    pflow_url = to_pflow_url(d.model)
    
    return """
    <!DOCTYPE html>
    <html>
        <head>
            <style>
                body {
                    margin: 0;
                    padding: 0;
                }
                .pflow-container {
                    position: relative;
                    display: inline-block;
                }
                .pflow-button {
                    position: absolute;
                    top: 10px;
                    left: 10px;
                    z-index: 1000;
                    background: white;
                    border: 2px solid #333;
                    border-radius: 8px;
                    padding: 8px 12px;
                    cursor: pointer;
                    box-shadow: 0 2px 8px rgba(0,0,0,0.15);
                    transition: all 0.2s;
                    text-decoration: none;
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }
                .pflow-button:hover {
                    box-shadow: 0 4px 12px rgba(0,0,0,0.25);
                    transform: translateY(-1px);
                }
                .pflow-button img {
                    height: 24px;
                    display: block;
                }
            </style>
        </head>
        <body>
            <div class="pflow-container">
                <a href="$(pflow_url)" target="_blank" class="pflow-button" title="Open in pflow.xyz">
                    <img src="https://cdn.jsdelivr.net/gh/pflow-xyz/pflow-xyz@latest/public/title.svg" alt="pflow">
                </a>
                $(String(take!(d.buffer)))
            </div>
        </body>
    </html>
    """
end

function to_html(net::Pflow)::String
    d = Display(net)
    
    # Calculate bounds matching pflow-xyz style
    if isempty(net.places) && isempty(net.transitions)
        min_x, min_y, max_x, max_y = 0, 0, 100, 100
    else
        min_x = min_y = typemax(Int)
        max_x = max_y = typemin(Int)
        
        for (_, p) in net.places
            min_x = min(min_x, p.x)
            max_x = max(max_x, p.x)
            min_y = min(min_y, p.y)
            max_y = max(max_y, p.y)
        end
        
        for (_, t) in net.transitions
            min_x = min(min_x, t.x)
            max_x = max(max_x, t.x)
            min_y = min(min_y, t.y)
            max_y = max(max_y, t.y)
        end
        
        # Add padding
        padding = 50
        min_x -= padding
        min_y -= padding
        max_x += padding
        max_y += padding
    end
    
    width = max_x - min_x
    height = max_y - min_y
    
    # Minimum size
    width = max(width, 100)
    height = max(height, 100)
    
    write(d.buffer, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"$min_x $min_y $width $height\" width=\"$width\" height=\"$height\">")
    write_defs(d)
    render(d)
    return to_html(d)
end

function to_svg(net::Pflow)::String
    d = Display(net)
    
    # Calculate bounds matching pflow-xyz style
    if isempty(net.places) && isempty(net.transitions)
        min_x, min_y, max_x, max_y = 0, 0, 100, 100
    else
        min_x = min_y = typemax(Int)
        max_x = max_y = typemin(Int)
        
        for (_, p) in net.places
            min_x = min(min_x, p.x)
            max_x = max(max_x, p.x)
            min_y = min(min_y, p.y)
            max_y = max(max_y, p.y)
        end
        
        for (_, t) in net.transitions
            min_x = min(min_x, t.x)
            max_x = max(max_x, t.x)
            min_y = min(min_y, t.y)
            max_y = max(max_y, t.y)
        end
        
        # Add padding
        padding = 50
        min_x -= padding
        min_y -= padding
        max_x += padding
        max_y += padding
    end
    
    width = max_x - min_x
    height = max_y - min_y
    
    # Minimum size
    width = max(width, 100)
    height = max(height, 100)
    
    write(d.buffer, "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"$min_x $min_y $width $height\" width=\"$width\" height=\"$height\">")
    write_defs(d)
    render(d)
    return String(take!(d.buffer))
end

function rect(d::Display, x::Int, y::Int, width::Int, height::Int, extra::String)
    write_element(d, "<rect x=\"$x\" y=\"$y\" width=\"$width\" height=\"$height\" $extra />")
end

function circle(d::Display, x::Int, y::Int, radius::Int, extra::String)
    write_element(d, "<circle cx=\"$x\" cy=\"$y\" r=\"$radius\" $extra />")
end

function text(d::Display, x::Int, y::Int, txt::String, extra::String)
    write_element(d, "<text x=\"$x\" y=\"$y\" $extra>$txt</text>")
end

function line(d::Display, x1::Int, y1::Int, x2::Int, y2::Int, extra::String)
    write_element(d, "<line x1=\"$x1\" y1=\"$y1\" x2=\"$x2\" y2=\"$y2\" $extra />")
end

function group(d::Display)
    write_element(d, "<g>")
end

end # module pflow
