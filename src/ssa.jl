# Portable discrete-stochastic SSA (Gillespie direct method).
#
# Byte-exact across go-pflow, pflow-rs, pflow-xyz and this package: the same
# seed yields bit-identical sample paths, ensemble means, standard deviations
# and final values in every language. Three sources of platform variance are
# removed by construction and every function below exists to remove one:
#
#   1. the random stream  — SplitMix64-seeded xoshiro256** (`splitmix64`,
#                           `Xoshiro256`, `next!`, `uniform!`), never `Random`;
#   2. the logarithm      — `plog`, an explicit port of the fdlibm e_log.c
#                           algorithm in the form Go's pure `math.log` uses,
#                           never `Base.log` (the two differ on ~7 % of inputs,
#                           e.g. log(3.0));
#   3. arithmetic order   — every sum, product and comparison is an explicit
#                           `for` loop in the order the spec fixes. No
#                           `@fastmath`, `@simd`, `muladd`, `fma`, `sum`,
#                           `prod`, `mapreduce`, `cumsum`, `mean` or `std`
#                           anywhere on this path (`sum` is pairwise, `std`
#                           divides by n-1).
#
# `to_jump_problem` (JumpProcesses) is a different, non-exact engine and is
# deliberately not held to these goldens. Goldens: test/testdata/ssa/*.json.

export SsaPlace, SsaTransition, SsaArc, SsaModel, SsaResult
export ssa_model, simulate_ssa, splitmix64, Xoshiro256, next!, uniform!, plog, combinations

# ---------------------------------------------------------------------------
# §1 PRNG
# ---------------------------------------------------------------------------

"""
    splitmix64(seed::UInt64) -> NTuple{4,UInt64}

Four SplitMix64 outputs from `seed`, in order; the xoshiro256** initial state.
All arithmetic wraps modulo 2^64 (native `UInt64` behaviour).
"""
function splitmix64(seed::UInt64)
    x = seed
    out = UInt64[]
    for _ in 1:4
        x = x + 0x9e3779b97f4a7c15
        z = x
        z = (z ⊻ (z >> 30)) * 0xbf58476d1ce4e5b9
        z = (z ⊻ (z >> 27)) * 0x94d049bb133111eb
        z = z ⊻ (z >> 31)
        push!(out, z)
    end
    return (out[1], out[2], out[3], out[4])
end

"""
    Xoshiro256(seed::UInt64)

xoshiro256** generator seeded through `splitmix64`. Not `Random.Xoshiro`:
this one has a fixed seeding procedure and a fixed `uniform!` mapping so that
every language draws the same stream.
"""
mutable struct Xoshiro256
    s0::UInt64
    s1::UInt64
    s2::UInt64
    s3::UInt64
end

function Xoshiro256(seed::UInt64)
    s = splitmix64(seed)
    return Xoshiro256(s[1], s[2], s[3], s[4])
end

"""
    next!(g::Xoshiro256) -> UInt64

One xoshiro256** output. `result` is formed from the *old* `s1` before the
state update.
"""
function next!(g::Xoshiro256)
    result = bitrotate(g.s1 * 0x0000000000000005, 7) * 0x0000000000000009
    t = g.s1 << 17
    g.s2 = g.s2 ⊻ g.s0
    g.s3 = g.s3 ⊻ g.s1
    g.s1 = g.s1 ⊻ g.s2
    g.s0 = g.s0 ⊻ g.s3
    g.s2 = g.s2 ⊻ t
    g.s3 = bitrotate(g.s3, 45)
    return result
end

"""
    uniform!(g::Xoshiro256) -> Float64

Uniform double in `[0, 1)` with granularity 2^-53: the top 53 bits of
`next!` scaled by 2^-53 (both steps exact).
"""
uniform!(g::Xoshiro256) = Float64(next!(g) >> 11) * 0x1p-53

# ---------------------------------------------------------------------------
# §2 Portable natural logarithm
# ---------------------------------------------------------------------------

const _LN2HI = reinterpret(Float64, 0x3fe62e42fee00000)
const _LN2LO = reinterpret(Float64, 0x3dea39ef35793c76)
const _L1 = reinterpret(Float64, 0x3fe5555555555593)
const _L2 = reinterpret(Float64, 0x3fd999999997fa04)
const _L3 = reinterpret(Float64, 0x3fd2492494229359)
const _L4 = reinterpret(Float64, 0x3fcc71c51d8e78af)
const _L5 = reinterpret(Float64, 0x3fc7466496cb03de)
const _L6 = reinterpret(Float64, 0x3fc39a09d078c69f)
const _L7 = reinterpret(Float64, 0x3fc2f112df3e5244)
const _SQRT2_OVER_2 = reinterpret(Float64, 0x3fe6a09e667f3bcd)

# frexp on the bit pattern: x = frac * 2^exp with frac in [0.5, 1).
# Defined for positive finite non-zero x (the only inputs plog passes it).
function _frexp(x::Float64)
    b = reinterpret(UInt64, x)
    e = Int((b >> 52) & 0x00000000000007ff)
    if e == 0                          # subnormal: normalise first (exact)
        x = x * 0x1p52
        b = reinterpret(UInt64, x)
        e = Int((b >> 52) & 0x00000000000007ff) - 52
    end
    ex = e - 1022
    frac = reinterpret(Float64, (b & ~(0x00000000000007ff << 52)) | (0x00000000000003fe << 52))
    return frac, ex
end

"""
    plog(x::Float64) -> Float64

Natural logarithm, fdlibm e_log.c in the form of Go's pure `math.log`. Every
operator is one binary64 operation in the written order; no FMA. Use this,
never `Base.log`, on the portable SSA path.
"""
function plog(x::Float64)
    if isnan(x) || x == Inf
        return x
    end
    if x < 0
        return NaN
    end
    if x == 0
        return -Inf
    end

    f1, ki = _frexp(x)
    if f1 < _SQRT2_OVER_2
        f1 = f1 * 2.0                  # exact
        ki = ki - 1
    end
    f = f1 - 1.0
    k = Float64(ki)

    s = f / (2.0 + f)
    s2 = s * s
    s4 = s2 * s2
    t1 = s2 * (_L1 + (s4 * (_L3 + (s4 * (_L5 + (s4 * _L7))))))
    t2 = s4 * (_L2 + (s4 * (_L4 + (s4 * _L6))))
    R = t1 + t2
    hfsq = (0.5 * f) * f
    return (k * _LN2HI) - (((hfsq - ((s * (hfsq + R)) + (k * _LN2LO))) - f))
end

# ---------------------------------------------------------------------------
# §3.1 Model
# ---------------------------------------------------------------------------

struct SsaPlace
    id::String
    initial::Int
    capacity::Int          # 0 = unbounded
end

struct SsaTransition
    id::String
    rate::Float64
end

struct SsaArc
    from::String
    to::String
    weight::Int
    kind::Symbol           # :flow | :inhibitor | :read
    kinetic::Bool
end

"""
    SsaModel(places, transitions, arcs)

Three **ordered** vectors. Place order and transition order are the vector
orders; arcs are scanned in vector order. Never build one from a `Dict`
iteration.
"""
struct SsaModel
    places::Vector{SsaPlace}
    transitions::Vector{SsaTransition}
    arcs::Vector{SsaArc}
end

_num(x, default) = x === nothing ? default : x

"""
    ssa_model(dict::AbstractDict) -> SsaModel

Load the go-pflow metamodel subset from a parsed fixture `"model"` object.
Iterates the JSON *arrays* (`places`, `transitions`, `arcs`), so order is the
file's order. Rejects `guard`, non-token `kind`, unknown arc `type`, and
read/inhibitor arcs written transition→place.
"""
function ssa_model(dict::AbstractDict)
    places = SsaPlace[]
    for p in dict["places"]
        kind = get(p, "kind", "token")
        kind == "token" || error("ssa_model: place $(p["id"]) has kind $(repr(kind)); only token places are supported")
        cap = Int(_num(get(p, "capacity", nothing), 0))
        push!(places, SsaPlace(String(p["id"]), Int(_num(get(p, "initial", nothing), 0)), cap))
    end
    place_ids = Set(p.id for p in places)
    transitions = SsaTransition[]
    for t in dict["transitions"]
        haskey(t, "guard") && error("ssa_model: transition $(t["id"]) carries a guard; guards are out of scope for the portable path")
        rate = Float64(_num(get(t, "rate", nothing), 0))
        if rate == 0
            rate = 1.0
        end
        push!(transitions, SsaTransition(String(t["id"]), rate))
    end
    transition_ids = Set(t.id for t in transitions)
    arcs = SsaArc[]
    for a in dict["arcs"]
        w = Int(_num(get(a, "weight", nothing), 0))
        if w == 0
            w = 1
        end
        typ = _num(get(a, "type", nothing), "")
        kind = typ == "" ? :flow :
               typ == "inhibitor" ? :inhibitor :
               typ == "read" ? :read :
               error("ssa_model: unknown arc type $(repr(typ))")
        kinetic = Bool(_num(get(a, "kinetic", nothing), true))
        from = String(a["from"]); to = String(a["to"])
        if kind != :flow && !(from in place_ids && to in transition_ids)
            error("ssa_model: $(kind) arc $(from)→$(to) must be written place→transition")
        end
        push!(arcs, SsaArc(from, to, w, kind, kinetic))
    end
    return SsaModel(places, transitions, arcs)
end

"""
    ssa_model(net::Pflow; rates, place_order, transition_order) -> SsaModel

Build an `SsaModel` from a `Pflow` net. `net.places` and `net.transitions`
are `Dict`s, so the caller must pass the place and transition order
explicitly; `rates` maps transition label → rate (missing → 1.0). Colored
nets use the first color only. Contextual arcs follow the pflow.xyz `guard!`
convention: transition→place is a read arc, place→transition an inhibitor;
both become place→transition `SsaArc`s. Every input is kinetic (`Arrow` has no
kinetic flag).
"""
function ssa_model(net::Pflow; rates = Dict{String,Float64}(),
                   place_order::Vector{String}, transition_order::Vector{String})
    places = SsaPlace[]
    for id in place_order
        p = net.places[id]
        init = isempty(p.initial) ? 0 : p.initial[1]
        cap = isempty(p.capacity) || !isfinite(p.capacity[1]) ? 0 : Int(p.capacity[1])
        push!(places, SsaPlace(id, init, cap))
    end
    transitions = SsaTransition[]
    for id in transition_order
        haskey(net.transitions, id) || error("ssa_model: unknown transition $(id)")
        r = Float64(get(rates, id, get(rates, Symbol(id), 1.0)))
        push!(transitions, SsaTransition(id, r == 0 ? 1.0 : r))
    end
    arcs = SsaArc[]
    for a in net.arcs
        w = isempty(a.weight) ? 1 : a.weight[1]
        w = w == 0 ? 1 : w
        # `guard!` sets `inhibit = true` on BOTH contextual kinds; the pflow.xyz
        # convention (see algebraic.jl) tells them apart by direction: drawn
        # transition→place it is a read arc, drawn place→transition an inhibitor.
        # The SSA model writes every contextual arc place→transition (§3.1), so a
        # read arc is flipped here — left as drawn, `_compile` would never see it.
        if is_read_arc(a)
            push!(arcs, SsaArc(a.target, a.source, w, :read, true))
        elseif is_inhibitor_arc(a)
            push!(arcs, SsaArc(a.source, a.target, w, :inhibitor, true))
        else
            push!(arcs, SsaArc(a.source, a.target, w, :flow, true))
        end
    end
    return SsaModel(places, transitions, arcs)
end

# Compiled transition: indices into the marking vector.
struct _CompiledTransition
    rate::Float64
    inputs::Vector{Tuple{Int,Int,Bool}}    # (place index, weight, kinetic)
    outputs::Vector{Tuple{Int,Int}}        # (place index, weight)
    reads::Vector{Tuple{Int,Int}}
    inhibits::Vector{Tuple{Int,Int}}
    caps::Vector{Tuple{Int,Int,Int}}       # (place index, delta, limit)
end

function _compile(model::SsaModel)
    idx = Dict{String,Int}()
    for (i, p) in enumerate(model.places)
        idx[p.id] = i
    end
    compiled = _CompiledTransition[]
    for t in model.transitions
        inputs = Tuple{Int,Int,Bool}[]
        outputs = Tuple{Int,Int}[]
        reads = Tuple{Int,Int}[]
        inhibits = Tuple{Int,Int}[]
        delta = zeros(Int, length(model.places))
        for a in model.arcs
            if a.to == t.id && haskey(idx, a.from)
                p = idx[a.from]
                if a.kind == :inhibitor
                    push!(inhibits, (p, a.weight))
                elseif a.kind == :read
                    push!(reads, (p, a.weight))
                else
                    push!(inputs, (p, a.weight, a.kinetic))
                    delta[p] -= a.weight
                end
            elseif a.from == t.id && haskey(idx, a.to) && a.kind == :flow
                p = idx[a.to]
                push!(outputs, (p, a.weight))
                delta[p] += a.weight
            end
        end
        caps = Tuple{Int,Int,Int}[]
        for (p, place) in enumerate(model.places)      # place order
            if place.capacity > 0 && delta[p] > 0
                push!(caps, (p, delta[p], place.capacity))
            end
        end
        push!(compiled, _CompiledTransition(t.rate, inputs, outputs, reads, inhibits, caps))
    end
    return compiled
end

# ---------------------------------------------------------------------------
# §3.2 – §3.4 Propensities and one realization
# ---------------------------------------------------------------------------

"""
    combinations(m::Integer, w::Integer) -> Float64

`C(m, w)` as go-pflow computes it: multiply then divide, once per factor, in
that order. Never an integer binomial converted afterwards.
"""
function combinations(m::Integer, w::Integer)
    if w <= 0
        return 1.0
    end
    if m < w
        return 0.0
    end
    result = 1.0
    for i in 0:(w - 1)
        result = result * Float64(m - i)
        result = result / Float64(i + 1)
    end
    return result
end

function _gated(tr::_CompiledTransition, marking::Vector{Int})
    for (p, w) in tr.reads
        if marking[p] < w
            return false
        end
    end
    for (p, w) in tr.inhibits
        if marking[p] >= w
            return false
        end
    end
    for (p, d, limit) in tr.caps
        if marking[p] + d > limit
            return false
        end
    end
    return true
end

# Fills `propensity` in transition order; returns a0 summed strictly left to right.
function _propensities!(propensity::Vector{Float64}, trs::Vector{_CompiledTransition}, marking::Vector{Int})
    a0 = 0.0
    for (j, tr) in enumerate(trs)
        a = tr.rate
        for (p, w, kinetic) in tr.inputs
            m = marking[p]
            if m < w
                a = 0.0
                break
            end
            if kinetic
                a = a * combinations(m, w)
            end
        end
        if a > 0 && !_gated(tr, marking)
            a = 0.0
        end
        propensity[j] = a
        a0 = a0 + a
    end
    return a0
end

const _SSA_MAX_STEPS = 1_000_000

# One realization. traj[p, i] = marking held at grid time times[i].
function _realization!(traj::Matrix{Float64}, trs::Vector{_CompiledTransition},
                       marking::Vector{Int}, times::Vector{Float64}, g::Xoshiro256)
    nP = length(marking)
    nT = length(trs)
    S = length(times)
    propensity = zeros(Float64, nT)
    t = 0.0
    nxt = 1
    # record(): every grid point <= t not yet written gets the current marking
    while nxt <= S && times[nxt] <= t
        for p in 1:nP
            traj[p, nxt] = Float64(marking[p])
        end
        nxt += 1
    end
    tEnd = times[S]                     # not the horizon option; they may differ by an ulp
    step = 0
    while step < _SSA_MAX_STEPS && t < tEnd
        step += 1
        a0 = _propensities!(propensity, trs, marking)
        if a0 <= 0
            break                       # dead marking; no draw consumed
        end
        x1 = uniform!(g)
        u = 1.0 - x1                    # (0, 1], exact
        dt = (-plog(u)) / a0
        t = t + dt
        while nxt <= S && times[nxt] <= t
            for p in 1:nP
                traj[p, nxt] = Float64(marking[p])
            end
            nxt += 1
        end
        if t > tEnd
            break                       # second draw NOT taken
        end
        x2 = uniform!(g)
        r = x2 * a0
        chosen = nT
        acc = 0.0
        for j in 1:nT
            acc = acc + propensity[j]
            if r <= acc
                chosen = j
                break
            end
        end
        tr = trs[chosen]
        for (p, w, _) in tr.inputs
            marking[p] = marking[p] - w
        end
        for (p, w) in tr.outputs
            marking[p] = marking[p] + w
        end
    end
    while nxt <= S                      # hold the final marking through the grid
        for p in 1:nP
            traj[p, nxt] = Float64(marking[p])
        end
        nxt += 1
    end
    return traj
end

# ---------------------------------------------------------------------------
# §3.5 – §3.7 Grid, seeds, ensemble
# ---------------------------------------------------------------------------

"""
    SsaResult

`places` in model order; `times` (length `samples`); `values[p]` and
`stddev[p]` (population, `÷n`) per place in place order; `final[p] ==
values[p][end]`. `series` indexes the same vectors by place id.
"""
struct SsaResult
    places::Vector{String}
    times::Vector{Float64}
    values::Vector{Vector{Float64}}
    stddev::Union{Nothing,Vector{Vector{Float64}}}
    final::Vector{Float64}
end

function Base.getproperty(r::SsaResult, name::Symbol)
    if name === :series
        out = Dict{String,NamedTuple{(:values, :stddev),Tuple{Vector{Float64},Union{Nothing,Vector{Float64}}}}}()
        sd = getfield(r, :stddev)
        for (p, id) in enumerate(getfield(r, :places))
            out[id] = (values = getfield(r, :values)[p], stddev = sd === nothing ? nothing : sd[p])
        end
        return out
    end
    return getfield(r, name)
end

"""
    simulate_ssa(model::SsaModel; horizon, samples, realizations, seed::UInt64) -> SsaResult

Ensemble of `realizations` Gillespie sample paths on the grid
`times[i] = (i-1) * (horizon / (samples-1))`, realization `r` (0-based) seeded
with `splitmix64(base + r)` where `base = seed == 0 ? 1 : seed`. Byte-exact
with go-pflow's portable path and the goldens in `test/testdata/ssa/`.
"""
function simulate_ssa(model::SsaModel; horizon::Real, samples::Integer, realizations::Integer, seed::UInt64)
    samples >= 2 || error("simulate_ssa: samples must be >= 2")
    realizations >= 1 || error("simulate_ssa: realizations must be >= 1")
    trs = _compile(model)
    nP = length(model.places)
    S = Int(samples)
    R = Int(realizations)

    stepv = Float64(horizon) / Float64(S - 1)
    times = Vector{Float64}(undef, S)
    for i in 0:(S - 1)
        times[i + 1] = Float64(i) * stepv
    end

    base = seed == 0 ? UInt64(1) : seed
    sums = zeros(Float64, nP, S)
    sumsq = zeros(Float64, nP, S)
    traj = zeros(Float64, nP, S)
    marking = Vector{Int}(undef, nP)
    for r in 0:(R - 1)
        for (p, place) in enumerate(model.places)
            marking[p] = place.initial
        end
        g = Xoshiro256(base + UInt64(r))       # wraps
        _realization!(traj, trs, marking, times, g)
        for p in 1:nP
            for i in 1:S
                v = traj[p, i]
                sums[p, i] = sums[p, i] + v
                sumsq[p, i] = sumsq[p, i] + (v * v)
            end
        end
    end

    n = Float64(R)
    values = Vector{Vector{Float64}}(undef, nP)
    stddev = R > 1 ? Vector{Vector{Float64}}(undef, nP) : nothing
    final = Vector{Float64}(undef, nP)
    for p in 1:nP
        mean = Vector{Float64}(undef, S)
        sd = R > 1 ? Vector{Float64}(undef, S) : nothing
        for i in 1:S
            mean[i] = sums[p, i] / n
            if R > 1
                variance = (sumsq[p, i] / n) - (mean[i] * mean[i])
                if variance < 0
                    variance = 0.0
                end
                sd[i] = sqrt(variance)
            end
        end
        values[p] = mean
        if R > 1
            stddev[p] = sd
        end
        final[p] = mean[S]
    end
    return SsaResult([p.id for p in model.places], times, values, stddev, final)
end
