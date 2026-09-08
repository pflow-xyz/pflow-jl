# Chemical Langevin SDE: the third leg of Petri.jl's
# ODEProblem/JumpProblem/SDEProblem trio (go-pflow ROADMAP.md G6), a port of
# go-pflow's `stochastic/sde.go`. Continuous state, but with the net's own
# intrinsic firing noise rather than SSA's discrete events or `to_ode_problem`
# / `to_jump_problem`'s none at all — Euler-Maruyama over the same
# propensities and stoichiometry `_compile` (ssa.jl) already extracts for SSA.
#
# Refuses a gated model (any read arc, inhibitor or reachable capacity)
# exactly as go-pflow's `Forecast`/`SimulateSDE` do: a firing instant is what
# those need, and continuous diffusion has none.
#
# Not yet part of the byte-exact cross-language contract SSA has — no
# test/testdata/sde/ goldens exist — but the Gaussian sampler is checked
# bit-for-bit against go-pflow's own `stochastic/portable_test.go`
# `TestPortableNormalVectors` (Go is the reference implementation for
# normal(): no external SDE spec, the same role it plays for wait()/uniform()
# in ssa-spec.md).

export SdeResult, simulate_sde, combinations_real, GaussianSampler, normal!
export CHEMICAL_LANGEVIN_ASSUMPTION

# ---------------------------------------------------------------------------
# §1 Gaussian sampler
# ---------------------------------------------------------------------------

"""
    GaussianSampler(seed::UInt64)

Wraps [`Xoshiro256`](@ref) with the Marsaglia polar method's spare-value
cache — exactly go-pflow's `portableSampler` (its `x` field plus
`hasSpare`/`spare`). Needs only `sqrt` (IEEE-754-exact and identical across
every conformant runtime, unlike `log`, so it needs no port) and [`plog`],
both already part of ssa.jl's contract — deliberately not Box-Muller, which
would need a second ported transcendental (sin/cos) this package has no
reference implementation for.

The cache is load-bearing, not an optimization: two consecutive `normal!`
calls on one accepted `(u1, u2)` pair return `u1*mul` then `u2*mul` from that
SAME pair. A version that redraws every call diverges from go-pflow's stream
from the second value on.
"""
mutable struct GaussianSampler
    rng::Xoshiro256
    has_spare::Bool
    spare::Float64
end

GaussianSampler(seed::UInt64) = GaussianSampler(Xoshiro256(seed), false, 0.0)

"""
    normal!(s::GaussianSampler) -> Float64

One standard normal draw, exactly go-pflow's `portableSampler.normal()`.
"""
function normal!(s::GaussianSampler)
    if s.has_spare
        s.has_spare = false
        return s.spare
    end
    while true
        u1 = 2.0 * uniform!(s.rng) - 1.0
        u2 = 2.0 * uniform!(s.rng) - 1.0
        sq = u1 * u1 + u2 * u2
        if sq > 0.0 && sq < 1.0
            mul = sqrt((-2.0 * plog(sq)) / sq)
            s.spare = u2 * mul
            s.has_spare = true
            return u1 * mul
        end
    end
end

# ---------------------------------------------------------------------------
# §2 Continuous propensity
# ---------------------------------------------------------------------------

"""
    combinations_real(x::Float64, w::Integer) -> Float64

[`combinations`](@ref) (spec-pinned, integer `m`) generalized to continuous
state: the same falling-factorial product evaluated at a real `x`, which
agrees with `combinations(m, w)` at every non-negative integer `m` — the
property that makes this the continuum limit rather than an arbitrary
generalization.

Below `x = w - 1` the product can go negative (e.g. x=0.5, w=2:
0.5×-0.5/2 = -0.125) — not a bug, the same "wrong near zero" behaviour
go-pflow's copy documents; callers clamp the resulting propensity at zero
rather than let a negative term flip a sign.
"""
function combinations_real(x::Float64, w::Integer)
    if w <= 0
        return 1.0
    end
    result = 1.0
    for i in 0:(w - 1)
        result = result * (x - Float64(i))
        result = result / Float64(i + 1)
    end
    return result
end

struct _SdeTransition
    rate::Float64
    terms::Vector{Tuple{Int,Int}}   # (place index, weight); kinetic inputs only
    delta::Vector{Float64}
end

function _compile_sde(model::SsaModel)
    trs = _compile(model)
    nP = length(model.places)
    out = _SdeTransition[]
    for t in trs
        delta = zeros(Float64, nP)
        terms = Tuple{Int,Int}[]
        for (p, w, kinetic) in t.inputs
            delta[p] -= Float64(w)
            if kinetic
                push!(terms, (p, w))
            end
        end
        for (p, w) in t.outputs
            delta[p] += Float64(w)
        end
        push!(out, _SdeTransition(t.rate, terms, delta))
    end
    return out
end

function _propensity(t::_SdeTransition, x::Vector{Float64})
    a = t.rate
    for (p, w) in t.terms
        a = a * combinations_real(x[p], w)
        if a <= 0.0
            return 0.0
        end
    end
    return a
end

"""
    _gating_reasons(model::SsaModel) -> Vector{String}

Mirrors go-pflow's `Model.Gating()` at the level `_compile`'s output can see
it: a read arc, an inhibitor, or a reachable capacity, none of which has a
continuous analogue.
"""
function _gating_reasons(model::SsaModel)
    trs = _compile(model)
    reasons = String[]
    if any(!isempty(t.reads) for t in trs)
        push!(reasons, "a read arc has no continuous analogue")
    end
    if any(!isempty(t.inhibits) for t in trs)
        push!(reasons, "an inhibitor arc has no continuous analogue")
    end
    if any(!isempty(t.caps) for t in trs)
        push!(reasons, "a reachable capacity is a post-firing bound, which has no continuous analogue")
    end
    return reasons
end

# ---------------------------------------------------------------------------
# §3 Euler-Maruyama path
# ---------------------------------------------------------------------------

# How many substeps run between each reported sample point. Matches
# go-pflow's `sdeInternalSubsteps` exactly — chosen empirically against the
# consistency tests, not derived, and deliberately not a public option for
# the same reason it isn't one there.
const _SDE_INTERNAL_SUBSTEPS = 20

function _sde_path(trs::Vector{_SdeTransition}, x0::Vector{Float64}, times::Vector{Float64}, rng::GaussianSampler)
    n = length(x0)
    S = length(times)
    out = Vector{Vector{Float64}}(undef, S)
    x = copy(x0)
    out[1] = copy(x)

    dt_outer = S > 1 ? (times[S] - times[1]) / Float64(S - 1) : 0.0
    dt = dt_outer / Float64(_SDE_INTERNAL_SUBSTEPS)
    sqrt_dt = sqrt(dt)

    drift = zeros(Float64, n)
    for gi in 2:S
        if dt > 0.0
            for _sub in 1:_SDE_INTERNAL_SUBSTEPS
                fill!(drift, 0.0)
                for t in trs
                    a = _propensity(t, x)
                    if a == 0.0
                        continue
                    end
                    noise = sqrt(a) * sqrt_dt * normal!(rng)
                    for p in 1:n
                        d = t.delta[p]
                        if d == 0.0
                            continue
                        end
                        drift[p] += d * a * dt
                        x[p] += d * noise
                    end
                end
                for p in 1:n
                    x[p] += drift[p]
                    if x[p] < 0.0
                        x[p] = 0.0
                    end
                    drift[p] = 0.0
                end
            end
        end
        out[gi] = copy(x)
    end
    return out
end

# ---------------------------------------------------------------------------
# §4 Ensemble
# ---------------------------------------------------------------------------

"go-pflow's `ChemicalLangevinAssumption`, word for word."
const CHEMICAL_LANGEVIN_ASSUMPTION = "this engine approximates the discrete firing process as continuous diffusion (the chemical Langevin equation), which is accurate when populations are large enough that the gap between SSA and this engine's mean is small (see the model's own consistency margin) and breaks down near zero, where a place's state is clamped rather than allowed to go negative."

"""
    SdeResult

Mirrors [`SsaResult`](@ref) (same `places`/`times`/`values`/`stddev`/`final`
shape and `series` property) plus `diverged`/`reason`/`caveats`, which
`SsaResult` never carries — an SDE run can refuse a model outright.
"""
struct SdeResult
    places::Vector{String}
    times::Vector{Float64}
    values::Vector{Vector{Float64}}
    stddev::Union{Nothing,Vector{Vector{Float64}}}
    final::Vector{Float64}
    diverged::Bool
    reason::String
    caveats::Vector{String}
end

function Base.getproperty(r::SdeResult, name::Symbol)
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
    simulate_sde(model::SsaModel; horizon, samples, realizations, seed::UInt64) -> SdeResult

Ensemble of `realizations` chemical Langevin sample paths on the same grid
[`simulate_ssa`](@ref) uses, seeded the same way. Refuses (via
`diverged`/`reason`/`caveats`) any model with a read arc, inhibitor, or
reachable capacity — none has a continuous analogue.
"""
function simulate_sde(model::SsaModel; horizon::Real, samples::Integer, realizations::Integer, seed::UInt64)
    samples >= 2 || error("simulate_sde: samples must be >= 2")
    realizations >= 1 || error("simulate_sde: realizations must be >= 1")

    S = Int(samples)
    R = Int(realizations)
    stepv = Float64(horizon) / Float64(S - 1)
    times = Vector{Float64}(undef, S)
    for i in 0:(S - 1)
        times[i + 1] = Float64(i) * stepv
    end
    places = [p.id for p in model.places]

    caveats = _gating_reasons(model)
    if !isempty(caveats)
        reason = "this model constrains firing in ways continuous diffusion cannot express, so the SDE would silently model an unconstrained system. Use the discrete engine (simulate_ssa). Specifically: " * join(caveats, "; ")
        return SdeResult(places, times, Vector{Float64}[], nothing, Float64[], true, reason, caveats)
    end

    trs = _compile_sde(model)
    nP = length(model.places)
    x0 = Vector{Float64}(undef, nP)
    for (p, place) in enumerate(model.places)
        x0[p] = Float64(place.initial)
    end

    base = seed == 0 ? UInt64(1) : seed
    sums = zeros(Float64, nP, S)
    sumsq = zeros(Float64, nP, S)

    for r in 0:(R - 1)
        rng = GaussianSampler(base + UInt64(r))   # wraps
        path = _sde_path(trs, x0, times, rng)
        for gi in 1:S
            xv = path[gi]
            for p in 1:nP
                sums[p, gi] += xv[p]
                sumsq[p, gi] += xv[p] * xv[p]
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
    return SdeResult(places, times, values, stddev, final, false, "", String[])
end
