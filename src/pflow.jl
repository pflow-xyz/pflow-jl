module pflow

using JSON
using LabelledArrays
using Base64
using SHA

# Export main types
export Pflow, StateMachine, Place, Transition, Arrow

# Export builder functions  
export place!, transition!, arc!, guard!

# Export conversion functions
export to_json, from_json, to_svg, to_html, to_model, to_state, set_state, set_rates, set_state!, set_rates!

# Export CID computation (cid.jl)
export compute_cid

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

"""
    to_model(x) -> LabelledPetriNet

AlgebraicPetri model of the net (was `Petri.Model` before v0.2; Petri.jl
pins Catlab ≤ 0.14 and cannot coexist with AlgebraicPetri).  Errors on
contextual (read/inhibitor) arcs instead of silently consuming them — see
`to_labelled_petri_net` for the encoding options.
"""
to_model(sm::StateMachine; kw...) = to_labelled_petri_net(sm.model; kw...)

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

to_model(pflow::Pflow; kw...) = to_labelled_petri_net(pflow; kw...)

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
    
    # The full document, sans @id: CIDv1(dag-json, sha2-256, base58btc) over
    # its @id-stripped URDNA2015-canonicalized N-Quads (compute_cid, cid.jl)
    # — the same algorithm go-pflow (internal/seal/seal.go) and pflow-xyz
    # (public/seal-cid.mjs) use, verified byte-for-byte against go-pflow's
    # canonical N-Quads output (test/test_cid.jl). @id is self-referential —
    # it equals the CID being computed — so it is excluded from its own
    # preimage; compute_cid does this stripping itself.
    result = Dict{String, Any}(
        "@context" => "https://pflow.xyz/schema",
        "@type" => "PetriNet",
        "@version" => "1.1",
        "places" => places_dict,
        "transitions" => transitions_dict,
        "arcs" => arcs_arr,
        "token" => net.token
    )
    cid, _ = compute_cid(result)
    result["@id"] = cid

    JSON.json(result)
end

# JSON parses arrays as Vector{Any}; the builders want concrete element types.
# A `null` entry is the editor's "unbounded" (it serialises Infinity that
# way); it becomes 0, which every engine already reads as unbounded, so a
# mixed vector like [5, null] keeps its color alignment. go-pflow's parser
# does the same — parity gate: test/test_editor_shape.jl.
_ints(v::AbstractVector) = Int[isnothing(x) ? 0 : Int(x) for x in v]
_ints(v) = v
_floats(v::AbstractVector) = Float64[isnothing(x) ? 0.0 : Float64(x) for x in v]
_floats(v) = v

function from_json(json_str::String)::Pflow
    data = JSON.parse(json_str)
    return from_json(data)
end

function from_json(data::Dict)::Pflow
    # Create a new Pflow model
    net = Pflow()
    
    # Extract model type and version if present
    if haskey(data, "@type")
        net.model_type = data["@type"]
    end
    if haskey(data, "@version")
        net.version = data["@version"]
    end
    
    # Parse token colors
    if haskey(data, "token")
        net.token = data["token"]
    end
    
    # Parse places
    if haskey(data, "places")
        for (label, place_data) in data["places"]
            offset = get(place_data, "offset", 0)
            initial = _ints(get(place_data, "initial", Int[]))
            capacity = _floats(get(place_data, "capacity", Float64[]))
            x = get(place_data, "x", 0)
            y = get(place_data, "y", 0)
            label_text = get(place_data, "label", nothing)
            
            place!(net, label, offset=offset, initial=initial, capacity=capacity, x=x, y=y, label_text=label_text)
        end
    end
    
    # Parse transitions
    if haskey(data, "transitions")
        for (label, trans_data) in data["transitions"]
            offset = get(trans_data, "offset", 0)
            role = get(trans_data, "role", "default")
            x = get(trans_data, "x", 0)
            y = get(trans_data, "y", 0)
            label_text = get(trans_data, "label", nothing)
            
            transition!(net, label, offset=offset, role=role, x=x, y=y, label_text=label_text)
        end
    end
    
    # Parse arcs
    if haskey(data, "arcs")
        for arc_data in data["arcs"]
            source = arc_data["source"]
            target = arc_data["target"]
            weight = _ints(get(arc_data, "weight", [1]))
            inhibit_transition = get(arc_data, "inhibitTransition", false)
            
            if inhibit_transition
                # This is a guard/inhibitor arc
                guard!(net, source, target, weight)
            else
                # Regular arc
                arc!(net, source=source, target=target, weight=weight)
            end
        end
    end
    
    return net
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
                    display: inline-block;
                }
                .pflow-button {
                    background: white;
                    border: 2px solid #333;
                    border-radius: 8px;
                    padding: 8px 12px;
                    cursor: pointer;
                    box-shadow: 0 2px 8px rgba(0,0,0,0.15);
                    transition: all 0.2s;
                    text-decoration: none;
                    display: inline-flex;
                    align-items: center;
                    gap: 8px;
                    margin-bottom: 10px;
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
                <br>
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

# Merge two Pflow models into a new model
function Base.merge(m1::Pflow, m2::Pflow)::Pflow
    result = Pflow()
    
    # Merge model type and version (use m1's values)
    result.model_type = m1.model_type
    result.version = m1.version
    
    # Merge token colors (union of both, preserving order)
    result.token = union(m1.token, m2.token)
    
    # Helper function to generate unique name
    function make_unique(name::String, existing::Dict)::String
        if !haskey(existing, name)
            return name
        end
        counter = 1
        while haskey(existing, "$(name)_$(counter)")
            counter += 1
        end
        return "$(name)_$(counter)"
    end
    
    # Merge places from m1
    for (label, place) in m1.places
        result.places[label] = Place(
            label, place.offset, place.initial, place.capacity,
            place.x, place.y, place.label_text
        )
    end
    
    # Merge places from m2 (with unique names)
    for (label, place) in m2.places
        new_label = make_unique(label, result.places)
        result.places[new_label] = Place(
            new_label, place.offset, place.initial, place.capacity,
            place.x, place.y, place.label_text
        )
    end
    
    # Merge transitions from m1
    for (label, trans) in m1.transitions
        result.transitions[label] = Transition(
            label, trans.offset, trans.role, trans.x, trans.y, trans.label_text
        )
    end
    
    # Merge transitions from m2 (with unique names)
    for (label, trans) in m2.transitions
        new_label = make_unique(label, result.transitions)
        result.transitions[new_label] = Transition(
            new_label, trans.offset, trans.role, trans.x, trans.y, trans.label_text
        )
    end
    
    # Build mapping for renamed places/transitions from m2
    place_mapping = Dict{String, String}()
    for (old_label, _) in m2.places
        place_mapping[old_label] = make_unique(old_label, m1.places)
    end
    
    trans_mapping = Dict{String, String}()
    for (old_label, _) in m2.transitions
        trans_mapping[old_label] = make_unique(old_label, m1.transitions)
    end
    
    # Merge arcs from m1
    for arc in m1.arcs
        push!(result.arcs, Arrow(
            arc.source, arc.target, arc.weight, arc.consume,
            arc.produce, arc.inhibit, arc.read, arc.inhibit_transition
        ))
    end
    
    # Merge arcs from m2 (updating references to renamed places/transitions)
    for arc in m2.arcs
        new_source = get(place_mapping, arc.source, get(trans_mapping, arc.source, arc.source))
        new_target = get(place_mapping, arc.target, get(trans_mapping, arc.target, arc.target))
        
        push!(result.arcs, Arrow(
            new_source, new_target, arc.weight, arc.consume,
            arc.produce, arc.inhibit, arc.read, arc.inhibit_transition
        ))
    end
    
    return result
end

# Overload + operator for model merging
Base.:+(m1::Pflow, m2::Pflow) = merge(m1, m2)

include("algebraic.jl")
include("ssa.jl")
include("sde.jl")
include("urdna2015.jl")
include("cid.jl")

end # module pflow
