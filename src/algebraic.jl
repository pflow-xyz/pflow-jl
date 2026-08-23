# AlgebraicPetri bridge.
#
# Pflow is a builder/serializer; AlgebraicPetri is where the category theory
# lives (open Petri nets as structured cospans, composition by pushout,
# mass-action vector fields).  This file converts between the two and exposes
# the one operation Pflow's own `merge`/`+` does not provide: gluing nets
# along shared boundary places.
#
#   merge(a, b) / a + b   — coproduct: disjoint union, colliding labels renamed
#   glue(...)             — pushout: boundary places with the same port name
#                           become ONE place; that is what removes behaviour
#                           and is what "composing channels" means.

using AlgebraicPetri
using Catlab
using Catlab.CategoricalAlgebra: apex, legs
using Catlab.WiringDiagrams: oapply
using Catlab.Programs.RelationalPrograms: parse_relation_diagram

export to_labelled_petri_net, from_labelled_petri_net, open_net, glue,
       incidence_matrix, is_p_invariant, is_event_graph, to_ode_problem,
       ContextualArcError

"""
Raised when a net with read or inhibitor arcs is converted to a formalism
that has no such arcs.  A read arc is a *contextual* arc: it has no entry in
the incidence matrix and nets that carry one do not generate the free
symmetric monoidal category that AlgebraicPetri's composition assumes
(Montanari & Rossi, 1995).  Pass `contextual=:selfloop` to encode a read arc
as consume-then-restore — exact under interleaving semantics, *not* under
partial-order semantics — or `contextual=:drop` to ignore them.  Inhibitor
arcs have no encoding at all and are always an error unless dropped.
"""
struct ContextualArcError <: Exception
    msg::String
end
Base.showerror(io::IO, e::ContextualArcError) = print(io, "ContextualArcError: ", e.msg)

weight_sum(a::Arrow) = isempty(a.weight) ? 1 : sum(a.weight)

# pflow.xyz convention (see guard!): an inhibit arc drawn transition->place is
# a *read* arc (fires only if the place holds >= weight tokens, consumes
# nothing); drawn place->transition it is an *inhibitor* (fires only if empty).
is_read_arc(a::Arrow)      = a.inhibit_transition && a.read === true
is_inhibitor_arc(a::Arrow) = a.inhibit_transition && !(a.read === true)
is_contextual(a::Arrow)    = a.inhibit_transition

_ordered(d::Dict) = sort(collect(values(d)); by = v -> (v.offset, v.label))

"""
    to_labelled_petri_net(net::Pflow; contextual=:error) -> LabelledPetriNet

Ordinary arcs map to AlgebraicPetri inputs/outputs; an arc of weight `w`
becomes `w` repeated entries (AlgebraicPetri's stoichiometry).  Note that
AlgebraicPetri's `vectorfield` is then chemical mass action — a weight-`w`
input contributes `M^w` — which is *not* go-pflow's rate law
(`flux = k·∏M`, first power, weight scales consumption only).  For the
nets this bridge is meant for (unit weights, event graphs) the two agree.

Colored nets collapse to token counts, as in `to_json` → ODE elsewhere.
"""
function to_labelled_petri_net(net::Pflow; contextual::Symbol = :error)::LabelledPetriNet
    contextual in (:error, :selfloop, :drop) ||
        throw(ArgumentError("contextual must be :error, :selfloop or :drop"))
    places = [Symbol(p.label) for p in _ordered(net.places)]
    # Vectors, not Tuples: AlgebraicPetri's vectorify wraps a 1-tuple as a key
    specs = Pair{Symbol, Pair{Vector{Symbol}, Vector{Symbol}}}[]
    for t in _ordered(net.transitions)
        ins = Symbol[]; outs = Symbol[]
        for a in net.arcs
            if is_contextual(a)
                touches = a.source == t.label || a.target == t.label
                touches || continue
                if contextual == :error
                    kind = is_read_arc(a) ? "read" : "inhibitor"
                    throw(ContextualArcError("transition $(t.label) has a $kind arc ($(a.source) -> $(a.target)); " *
                        "AlgebraicPetri has no contextual arcs. Use contextual=:selfloop (read arcs only) or :drop."))
                elseif contextual == :drop
                    continue
                elseif is_read_arc(a)          # transition -> place, read
                    w = weight_sum(a); p = Symbol(a.target)
                    append!(ins, fill(p, w)); append!(outs, fill(p, w))
                else
                    throw(ContextualArcError("transition $(t.label) has an inhibitor arc from $(a.source); " *
                        "inhibitor arcs cannot be encoded as self-loops. Use contextual=:drop to ignore."))
                end
            elseif a.target == t.label && haskey(net.places, a.source)
                append!(ins, fill(Symbol(a.source), weight_sum(a)))
            elseif a.source == t.label && haskey(net.places, a.target)
                append!(outs, fill(Symbol(a.target), weight_sum(a)))
            end
        end
        push!(specs, Symbol(t.label) => (ins => outs))
    end
    LabelledPetriNet(places, specs...)
end

"""
    from_labelled_petri_net(lpn) -> Pflow

Inverse of `to_labelled_petri_net` up to layout: repeated inputs/outputs
collapse back into one arc of that weight.  Initial markings are zero.
"""
function from_labelled_petri_net(lpn::AbstractLabelledPetriNet)::Pflow
    net = Pflow()
    for (i, s) in enumerate(snames(lpn))
        place!(net, String(s); initial = 0, x = 100, y = 100 * i)
    end
    for (j, t) in enumerate(tnames(lpn))
        transition!(net, String(t); x = 300, y = 100 * j)
        for (p, w) in _multiplicities(sname(lpn, s) for s in inputs(lpn, j))
            arc!(net; source = String(p), target = String(t), weight = w)
        end
        for (p, w) in _multiplicities(sname(lpn, s) for s in outputs(lpn, j))
            arc!(net; source = String(t), target = String(p), weight = w)
        end
    end
    net
end

function _multiplicities(itr)
    counts = Dict{Symbol, Int}(); order = Symbol[]
    for s in itr
        haskey(counts, s) || push!(order, s)
        counts[s] = get(counts, s, 0) + 1
    end
    [(s, counts[s]) for s in order]
end

"""
    open_net(net::Pflow, legs::AbstractVector{String}...; kw...) -> OpenLabelledPetriNet

Expose boundary places as legs of a structured cospan.  Each leg is a list of
place labels; `open_net(ch, ["a"], ["b"])` is the channel with input
boundary {a} and output boundary {b}.
"""
function open_net(net::Pflow, legs::AbstractVector{<:AbstractString}...; kw...)
    lpn = to_labelled_petri_net(net; kw...)
    isempty(legs) && return Open(lpn)
    Open(lpn, [[Symbol(p) for p in leg] for leg in legs]...)
end

"""
    glue(parts, ports; outer=String[], kw...) -> LabelledPetriNet

Compose open nets by pushout along shared boundary places.

- `parts`  : `[:ch_ab => net1, :ch_bc => net2, ...]` (order fixes transition order)
- `ports`  : `Dict(:ch_ab => ["a","b"], :ch_bc => ["b","c"], ...)` — for each
             part, the labels of its boundary places, *as named inside that
             part*.  Equal port names across parts become one junction, i.e.
             one place in the composite.
- `outer`  : junction names to expose as the composite's own boundary.

Non-boundary place labels should be unique across parts (`pending_ab`, not
`pending`); the pushout keeps them distinct, but AlgebraicPetri labels would
collide.  Returns the apex; use `from_labelled_petri_net` for a `Pflow`.

This is the operation Appendix E of the pflow book calls "CompositeNet is a
pushout, not a coproduct": gluing identifies places and therefore can
*remove* behaviour, which `merge`/`+` never does.
"""
function glue(parts::AbstractVector{<:Pair{Symbol, Pflow}},
              ports::AbstractDict{Symbol, <:AbstractVector{<:AbstractString}};
              outer::AbstractVector{<:AbstractString} = String[], kw...)
    for (name, _) in parts
        haskey(ports, name) || throw(ArgumentError("no ports given for part $name"))
    end
    head = Expr(:tuple, (Symbol(p) for p in outer)...)
    body = Expr(:block, (Expr(:call, name, (Symbol(p) for p in ports[name])...) for (name, _) in parts)...)
    uwd = parse_relation_diagram(head, body)
    models = Dict(name => open_net(net, ([p] for p in ports[name])...; kw...) for (name, net) in parts)
    apex(oapply(uwd, models))
end

"""
    incidence_matrix(lpn) -> Matrix{Int}

`C[p, t] = outputs − inputs`, **places × transitions** (the ecosystem's
convention: `ẋ = C·v`, P-invariant `yᵀC = 0`).
"""
function incidence_matrix(lpn::AbstractPetriNet)
    C = zeros(Int, ns(lpn), nt(lpn))
    for t in 1:nt(lpn)
        for s in inputs(lpn, t);  C[s, t] -= 1; end
        for s in outputs(lpn, t); C[s, t] += 1; end
    end
    C
end

"P-invariant test: `yᵀC = 0`."
is_p_invariant(lpn::AbstractPetriNet, y::AbstractVector) = all(iszero, transpose(y) * incidence_matrix(lpn))

"""
    is_event_graph(lpn) -> Bool

Timed-event-graph property: every place has exactly one input transition
and one output transition.  This is the domain on which the tropical
eigenvalue is defined; it is broken by ρ > 1 transitions (fan-in), which is
the *algebraic* core–observer boundary.
"""
function is_event_graph(lpn::AbstractPetriNet)
    producers = zeros(Int, ns(lpn)); consumers = zeros(Int, ns(lpn))
    for t in 1:nt(lpn)
        for s in inputs(lpn, t);  consumers[s] += 1; end
        for s in outputs(lpn, t); producers[s] += 1; end
    end
    all(==(1), producers) && all(==(1), consumers)
end

"""
    to_ode_problem(net::Pflow, tspan; u0=set_state(net), rates=set_rates(net), kw...)

`ODEProblem` over AlgebraicPetri's `vectorfield`.  `u0` and `rates` are the
`LVector`s `set_state`/`set_rates` produce (keyed by place / transition
label).  Requires `OrdinaryDiffEq` (or `SciMLBase`) to be loaded by the
caller for `ODEProblem`.
"""
function to_ode_problem(net::Pflow, tspan; u0 = set_state(net), rates = set_rates(net), kw...)
    lpn = to_labelled_petri_net(net; kw...)
    # vectorfield on a labelled net indexes u and p by label, so pass LVectors
    u = LVector(; (s => Float64(u0[s]) for s in snames(lpn))...)
    p = LVector(; (t => Float64(rates[t]) for t in tnames(lpn))...)
    Main.ODEProblem(vectorfield(lpn), u, tspan, p)
end
include("settle.jl")
