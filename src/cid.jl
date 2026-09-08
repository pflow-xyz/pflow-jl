# Content identifier (CID) for a Pflow net — CIDv1(dag-json, sha2-256,
# base58btc) over the @id-stripped URDNA2015-canonicalized N-Quads of the
# net's JSON-LD document, matching go-pflow (internal/seal/seal.go) and
# pflow-xyz (public/seal-cid.mjs) byte-for-byte. See ROADMAP.md item 5b.
#
# The RDF canonicalization itself lives in urdna2015.jl and is generic; this
# file is the pflow-specific half — a hand-written JSON-LD expander for
# exactly the one context this schema uses (see PFLOW_SCHEMA_CONTEXT below),
# not a general JSON-LD processor. Verified against go-pflow's actual
# canonical N-Quads output on every fixture in
# pflow-xyz/parity/fixtures/*.jsonld (test/testdata/cid/), not from a
# from-memory reading of the JSON-LD spec.
#
# What the expander has to get right, because it is NOT generic JSON-LD
# expansion:
#   - every object value becomes its own blank node; each of ITS keys
#     becomes a predicate via @vocab expansion (`https://pflow.xyz/schema#`
#     + key) pointing at the nested blank node, or a literal for a scalar
#   - a term declared `@container: @list` in the context (arcs, token,
#     weight, capacity, initial, parents) becomes an RDF Collection: a
#     chain of blank nodes each carrying rdf:first/rdf:rest, terminated by
#     rdf:nil; `null` entries are DROPPED before building the list (JSON-LD
#     value expansion drops null), so `"capacity": [null]` becomes an empty
#     list — rdf:nil directly, no list cell at all
#   - "@type" becomes an rdf:type triple whose object is the @vocab-expanded
#     IRI of the type name, never a literal
#   - every other scalar becomes a literal: Julia Bool -> xsd:boolean,
#     Integer -> xsd:integer, AbstractFloat -> xsd:double (untested against
#     go-pflow — no fixture has ever had a fractional coordinate — kept
#     for correctness rather than silently mishandling one if it appears),
#     String -> plain literal (xsd:string, no ^^ suffix in N-Quads)
#   - "@id"/"@context"/"@version" are JSON-LD keywords, not properties, and
#     produce no triple; "@id" is additionally stripped from the input
#     before expansion even starts (a net's own CID would otherwise be part
#     of its own preimage)

const PFLOW_VOCAB = "https://pflow.xyz/schema#"
const PFLOW_LIST_CONTAINERS = Set(["arcs", "token", "weight", "capacity", "initial", "parents"])

vocab_iri(key::AbstractString) = IRI(PFLOW_VOCAB * key)

mutable struct ExpandCounter
    n::Int
end
fresh_bnode!(c::ExpandCounter) = (c.n += 1; BNode("j" * string(c.n)))

function literal_for(v)::Term
    if v isa Bool
        return Literal(v ? "true" : "false", "http://www.w3.org/2001/XMLSchema#boolean")
    elseif v isa Integer
        return Literal(string(v), "http://www.w3.org/2001/XMLSchema#integer")
    elseif v isa AbstractFloat
        # xsd:double canonical form per the JSON-LD spec's number-to-literal
        # rule: mantissa always carries a decimal point, exponent always
        # present, uppercase E. Untested against go-pflow (see module doc).
        s = uppercase(string(v))
        if !occursin("E", s)
            s *= "E0"
        end
        return Literal(s, "http://www.w3.org/2001/XMLSchema#double")
    elseif v isa AbstractString
        return Literal(String(v), "")
    else
        error("cid: don't know how to expand a literal of type $(typeof(v)): $(repr(v))")
    end
end

# Build an RDF list (spec: "@list" expansion -> rdf:first/rdf:rest chain).
# `items` has already had `nothing` entries dropped. Returns the term that
# should be used where the list is referenced (rdf:nil for an empty list,
# otherwise the first cell's blank node) and appends the list's own quads
# to `quads`.
function expand_list!(quads::Vector{Quad}, counter::ExpandCounter, items::Vector)::Term
    isempty(items) && return IRI(RDF_NIL)
    cells = [fresh_bnode!(counter) for _ in items]
    for (i, item) in enumerate(items)
        obj = expand_value!(quads, counter, item)
        push!(quads, (cells[i], IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#first"), obj))
        rest = i == length(items) ? IRI(RDF_NIL) : cells[i + 1]
        push!(quads, (cells[i], IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#rest"), rest))
    end
    return cells[1]
end

# Expand one JSON value (already known not to be a @list-container value)
# into the term that should stand in for it — a literal for a scalar, a
# fresh blank node (with its own quads appended) for an object.
function expand_value!(quads::Vector{Quad}, counter::ExpandCounter, v)::Term
    if v isa AbstractDict
        node = fresh_bnode!(counter)
        expand_object!(quads, counter, node, v)
        return node
    end
    return literal_for(v)
end

# Expand every key of a JSON object as a property of `subject`, appending
# quads to `quads`. "@type" becomes rdf:type with a vocab-expanded IRI
# object; "@id"/"@context"/"@version" are keywords and produce nothing;
# every other key vocab-expands to a predicate IRI, and a key declared in
# PFLOW_LIST_CONTAINERS is expanded as an RDF list (dropping null items)
# rather than as a single value or a plain nested object.
function expand_object!(quads::Vector{Quad}, counter::ExpandCounter, subject::Term, obj::AbstractDict)
    for (k, v) in obj
        if k == "@id" || k == "@context" || k == "@version"
            continue
        elseif k == "@type"
            push!(
                quads,
                (subject, IRI("http://www.w3.org/1999/02/22-rdf-syntax-ns#type"), vocab_iri(String(v))),
            )
        elseif k in PFLOW_LIST_CONTAINERS
            items = v isa AbstractVector ? v : [v]
            # A JSON `null` list entry is dropped: JSON-LD value expansion
            # drops null, so "capacity": [null] becomes an empty list.
            filtered = Any[x for x in items if x !== nothing]
            list_term = expand_list!(quads, counter, filtered)
            push!(quads, (subject, vocab_iri(k), list_term))
        else
            obj_term = expand_value!(quads, counter, v)
            push!(quads, (subject, vocab_iri(k), obj_term))
        end
    end
end

"""
    to_quads(data::AbstractDict) -> Vector{Quad}

Expand a pflow net's JSON-LD document (as parsed by `JSON.parse`, `@id`
already removed by the caller — `compute_cid` does this) into RDF quads,
per this file's module doc. The root document itself becomes one blank
node.
"""
function to_quads(data::AbstractDict)::Vector{Quad}
    quads = Quad[]
    counter = ExpandCounter(0)
    root = fresh_bnode!(counter)
    expand_object!(quads, counter, root, data)
    return quads
end

# --- Multiformats: multihash, CIDv1(dag-json), multibase(base58btc) -------

const BASE58BTC_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

function base58btc_encode(bytes::Vector{UInt8})::String
    # Standard big-integer-radix-conversion base58 encoding, with one
    # leading '1' per leading 0x00 byte (multibase's usual convention,
    # shared with Bitcoin's base58check and IPFS CIDs).
    n = big(0)
    for b in bytes
        n = n * 256 + b
    end
    digits = Char[]
    if n == 0
        push!(digits, BASE58BTC_ALPHABET[1])
    end
    while n > 0
        n, r = divrem(n, 58)
        push!(digits, BASE58BTC_ALPHABET[Int(r) + 1])
    end
    leading_zeros = 0
    for b in bytes
        b == 0x00 || break
        leading_zeros += 1
    end
    return BASE58BTC_ALPHABET[1]^leading_zeros * String(reverse(digits))
end

# Unsigned LEB128 varint, as multiformats (multihash/CID) use throughout.
function uvarint(n::Integer)::Vector{UInt8}
    out = UInt8[]
    while true
        b = UInt8(n & 0x7f)
        n >>= 7
        if n != 0
            push!(out, b | 0x80)
        else
            push!(out, b)
            break
        end
    end
    return out
end

const MULTIHASH_SHA2_256 = 0x12
const CID_VERSION_1 = 0x01
const CODEC_DAG_JSON = 0x0129

"CIDv1(dag-json, sha2-256), base58btc-encoded with the multibase 'z' prefix."
function cidv1_dagjson_sha256(preimage::Vector{UInt8})::String
    digest = SHA.sha256(preimage)
    multihash = vcat(uvarint(MULTIHASH_SHA2_256), uvarint(length(digest)), digest)
    cid_bytes = vcat(uvarint(CID_VERSION_1), uvarint(CODEC_DAG_JSON), multihash)
    return "z" * base58btc_encode(cid_bytes)
end

"""
    compute_cid(data::AbstractDict) -> (cid::String, canonical_nquads::String)

The Julia-side equivalent of go-pflow's `seal.SealJSONLD` / pflow-xyz's
`sealJsonLD`: strip `@id` (self-referential, excluded from its own
preimage), canonicalize, hash, and encode. `data` is a JSON object already
parsed into nested `Dict`/`Vector`/scalar Julia values (e.g. via
`JSON.parse`) — not yet stripped of `@id`.
"""
function compute_cid(data::AbstractDict)::Tuple{String,String}
    stripped = Dict{String,Any}(k => v for (k, v) in data if k != "@id")
    quads = to_quads(stripped)
    nquads = canonical_nquads(quads)
    cid = cidv1_dagjson_sha256(Vector{UInt8}(nquads))
    return cid, nquads
end
