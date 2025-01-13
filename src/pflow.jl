module pflow

using JSON
using LabelledArrays
using Petri
using Base64

struct Place
    label::String
    offset::Int
    initial::Union{Nothing,Int}
    capacity::Union{Nothing,Int}
    x::Int
    y::Int
end

struct Transition
    label::String
    offset::Int
    role::String
    x::Int
    y::Int
end

struct Arrow
    source::String
    target::String
    weight::Union{Nothing,Int}
    consume::Union{Nothing,Bool}
    produce::Union{Nothing,Bool}
    inhibit::Union{Nothing,Bool}
    read::Union{Nothing,Bool}
end

mutable struct Pflow
    model_type::String
    version::String
    places::Dict{String,Place}
    transitions::Dict{String,Transition}
    arcs::Vector{Arrow}
end

function Pflow()
    Pflow("petriNet", "v0", Dict(), Dict(), [])
end

function place!(net::Pflow, label::String; offset::Union{Nothing,Int}=nothing, initial::Union{Nothing,Int}=nothing, capacity::Union{Nothing,Int}=nothing, x::Int=0, y::Int=0)
    offset = isnothing(offset) ? length(net.transitions) : offset
    net.places[label] = Place(label, offset, initial, capacity, x, y)
end

function transition!(net::Pflow, label::String; offset::Union{Nothing,Int}=nothing, role::String="default", x::Int=0, y::Int=0)
    offset = isnothing(offset) ? length(net.transitions) : offset
    net.transitions[label] = Transition(label, offset, role, x, y)
end

function arc!(net::Pflow; source::String="", target::String="", weight::Union{Nothing,Int}=1)
    # set consume if source is a place and target is a transition
    consume = haskey(net.places, source) && haskey(net.transitions, target)
    # set produce if source is a transition and target is a place
    produce = haskey(net.transitions, source) && haskey(net.places, target)
    inhibit = false
    read = false
    push!(net.arcs, Arrow(source, target, weight, consume, produce, inhibit, read))
end

function guard!(net::Pflow, source::String, target::String, weight::Union{Nothing,Int})
    # set consume if source is a place and target is a transition
    consume = haskey(net.places, source) && haskey(net.transitions, target)
    # set produce if source is a transition and target is a place
    produce = haskey(net.transitions, source) && haskey(net.places, target)
    inhibit = true
    read = haskey(net.transitions, source) && haskey(net.places, target)

    push!(net.arcs, Arrow(source, target, weight, consume, produce, inhibit, read))
end

function set_state(pflow::Pflow)
    fields = Dict{Symbol, Number}()
    for (label, place) in pflow.places
        fields[Symbol(label)] = isnothing(place.initial) ? 0 : place.initial
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
                if ! arc.consume
                    error("Transition $label should consume from place $arc.source")
                end
                input_places[Symbol(arc.source)] = isnothing(arc.weight) ? 1 : arc.weight
            end
            if arc.source == label
                if ! arc.produce
                    error("Transition $label should produce to place $arc.target")
                end
                output_places[Symbol(arc.target)] = isnothing(arc.weight) ? 1 : arc.weight
            end
        end

        transitions[Symbol(label)] = (input_places, output_places)
    end

    return Petri.Model(states, transitions)
end

function to_json(net::Pflow)::String
    JSON.json(Dict(
        "modelType" => net.model_type,
        "version" => net.version,
        "places" => Dict(k => Dict(
            "offset" => v.offset,
            "initial" => v.initial,
            "capacity" => v.capacity,
            "x" => v.x,
            "y" => v.y
        ) for (k, v) in net.places),
        "transitions" => Dict(k => Dict(
            "role" => v.role,
            "offset" => v.offset,
            "x" => v.x,
            "y" => v.y
        ) for (k, v) in net.transitions),
        "arcs" => [Dict(
            "source" => arc.source,
            "target" => arc.target,
            "weight" => arc.weight,
            "consume" => arc.consume,
            "produce" => arc.produce,
            "inhibit" => arc.inhibit,
            "read" => arc.read
        ) for arc in net.arcs]
    ))
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
    write(d.buffer, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100%\" height=\"100%\" viewBox=\"0 0 $w $h\">")
    rect(d, 0, 0, w, h, "fill=\"#ffffff\"") # add white background
    write_defs(d)
end

function write_defs(d::Display)
    write(
        d.buffer,
        """<defs>
               <marker id="markerArrow1" markerWidth="23" markerHeight="13" refX="31" refY="6" orient="auto">
                   <rect width="28" height="3" fill="white" stroke="white" x="3" y="5"/>
                   <path d="M2,2 L2,11 L10,6 L2,2"/>
               </marker>
               <marker id="markerInhibit1" markerWidth="23" markerHeight="13" refX="31" refY="6" orient="auto">
                   <rect width="28" height="3" fill="white" stroke="white" x="3" y="5"/>
                   <circle cx="5" cy="6.5" r="4"/>
               </marker>
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
    circle(d, place.x, place.y, 16, "stroke-width=\"1.5\" fill=\"#ffffff\" stroke=\"#000000\"")
    text(d, place.x - 18, place.y - 20, label, "font-size=\"small\"")
    
    x = place.x
    y = place.y
    tokens = isnothing(place.initial) ? 0 : place.initial
    
    if tokens > 0
        if tokens == 1
            circle(d, x, y, 2, "fill=\"#000000\" stroke=\"#000000\"")
        elseif tokens < 10
            text(d, x - 4, y + 5, string(tokens), "font-size=\"large\"")
        else
            text(d, x - 7, y + 5, string(tokens), "font-size=\"small\"")
        end
    end
    
    gend(d)
end

function arc_element(d::Display, arc::Arrow)
    group(d)
    marker = arc.inhibit ? "url(#markerInhibit1)" : "url(#markerArrow1)"
    extra = "stroke=\"#000000\" fill=\"#000000\" marker-end=\"$marker\""

    if arc.inhibit
        if haskey(d.model.places, arc.source)
            p = d.model.places[arc.source]
            t = d.model.transitions[arc.target]
        else
            p = d.model.places[arc.target]
            t = d.model.transitions[arc.source]
        end
    else
        if haskey(d.model.places, arc.source)
            p = d.model.places[arc.source]
            t = d.model.transitions[arc.target]
        else
            p = d.model.places[arc.target]
            t = d.model.transitions[arc.source]
        end
    end

    # REVIEW: use the new bool functions
    if haskey(d.model.places, arc.source)
        p = d.model.places[arc.source]
        t = d.model.transitions[arc.target]
        line(d, p.x, p.y, t.x, t.y, extra)
        mid_x = (p.x + t.x) / 2
        mid_y = (p.y + t.y) / 2 - 8
    else
        p = d.model.places[arc.target]
        t = d.model.transitions[arc.source]
        line(d, t.x, t.y, p.x, p.y, extra)
        mid_x = (t.x + p.x) / 2
        mid_y = (t.y + p.y) / 2 - 8
    end

    weight = isnothing(arc.weight) ? 1 : arc.weight
    text(d, Int(round(mid_x - 4)), Int(round(mid_y + 4)), "$weight", "font-size=\"small\"")
    gend(d)
end

function transition_element(d::Display, label::String, transition::Transition)
    group(d)
    x, y = transition.x - 17, transition.y - 17
    rect(d, x, y, 30, 30, "stroke=\"#000000\" fill=\"#ffffff\" rx=\"4\"")
    text(d, x, y - 8, label, "font-size=\"small\"")
    gend(d)
end

function end_svg(d::Display)
    write(d.buffer, "</svg>")
end

function to_html(d::Display)::String
    return """
    <!DOCTYPE html>
    <html>
        <body>
            $(String(take!(d.buffer)))
        </body>
    </html>
    """
end

function to_html(net::Pflow)::String
    d = Display(net)
    max_x = max(
        maximum([p.x for (_, p) in net.places]),
        maximum([t.x for (_, t) in net.transitions])
    ) + 100
    max_y = max(
        maximum([p.y for (_, p) in net.places]),
        maximum([t.y for (_, t) in net.transitions])
    ) + 100
    new_svg_image(d, max_x, max_y)
    render(d)
    return to_html(d)
end

function to_svg(net::Pflow)::String
    d = Display(net)
    new_svg_image(d)
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
