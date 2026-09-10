# RDF Dataset Canonicalization (URDNA2015 / RDFC-1.0), ported for CID parity
# with go-pflow (internal/seal/seal.go, piprate/json-gold) and pflow-xyz
# (public/seal-cid.mjs, jsonld.js). This file is the general half: it knows
# nothing about Petri nets, only about RDF quads and blank node labels. The
# pflow-specific half — turning a net's JSON-LD document into a Vector{Quad}
# — is cid.jl.
#
# No Julia package implements JSON-LD/RDF canonicalization (checked
# 2026-09-04), so this is a from-scratch port of the algorithm in
# https://www.w3.org/TR/rdf-canon/ (the spec URDNA2015 was standardized
# into), verified against go-pflow's actual output — never against a
# from-memory reading of the spec alone. See test/test_urdna2015.jl.
#
# A term is one of:
#   IRI(value)              — an absolute IRI
#   BNode(label)             — a blank node, identified by its *input* label
#                              (arbitrary and unstable; canonicalization's
#                              whole job is to replace it with a stable one)
#   Literal(value, datatype) — datatype is "" for a plain (xsd:string)
#                              literal, matching N-Quads' "omit ^^ for
#                              xsd:string" rule
#
# A Quad is (subject, predicate, object) — no named graphs; pflow documents
# never use one, so graph is always the RDF "default graph" and is left out
# of the term tuple entirely rather than modeled as an always-empty field.

struct IRI
    value::String
end
struct BNode
    label::String
end
struct Literal
    value::String
    datatype::String  # "" means xsd:string (the N-Quads default, no ^^ suffix)
end
const Term = Union{IRI,BNode,Literal}
const Quad = Tuple{Term,Term,Term}

const XSD_STRING = "http://www.w3.org/2001/XMLSchema#string"
const RDF_NIL = "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"

# --- N-Quads term/quad serialization (spec section 2.1's "serialization" +
#     RDF 1.1 N-Quads' literal-escaping rules) -----------------------------

function nq_escape(s::AbstractString)
    io = IOBuffer()
    for c in s
        if c == '\\'
            print(io, "\\\\")
        elseif c == '"'
            print(io, "\\\"")
        elseif c == '\n'
            print(io, "\\n")
        elseif c == '\r'
            print(io, "\\r")
        else
            print(io, c)
        end
    end
    return String(take!(io))
end

function nq_term(t::IRI)::String
    return "<" * t.value * ">"
end
function nq_term(t::BNode)::String
    return "_:" * t.label
end
function nq_term(t::Literal)::String
    if t.datatype == "" || t.datatype == XSD_STRING
        return "\"" * nq_escape(t.value) * "\""
    end
    return "\"" * nq_escape(t.value) * "\"^^<" * t.datatype * ">"
end

function nq_line(q::Quad)::String
    return nq_term(q[1]) * " " * nq_term(q[2]) * " " * nq_term(q[3]) * " .\n"
end

"Canonical N-Quads document: every quad's line, lexicographically sorted, concatenated."
function serialize_canonical(quads::Vector{Quad})::String
    lines = [nq_line(q) for q in quads]
    sort!(lines)
    return join(lines)
end

# --- Hashing (spec 4.5 "Hash First Degree Quads" building block) ----------

sha256hex(s::AbstractString) = bytes2hex(SHA.sha256(Vector{UInt8}(s)))

# --- Identifier issuer (spec 4.4) ------------------------------------------

"""
    IdentifierIssuer(prefix)

Issues sequential canonical blank node identifiers (`prefix * "0"`, `prefix *
"1"`, ...) to input blank node labels, first-come-first-served, and
remembers the mapping. `copy(issuer)` is used by Hash N-Degree Quads to try
an issuance path without committing it — cloning must be O(1)-ish and
independent (mutating the clone must not affect the original).
"""
mutable struct IdentifierIssuer
    prefix::String
    counter::Int
    issued_order::Vector{String}          # input labels, in issuance order
    map::Dict{String,String}              # input label -> issued canonical label
end
IdentifierIssuer(prefix::String) = IdentifierIssuer(prefix, 0, String[], Dict{String,String}())

Base.copy(iss::IdentifierIssuer) =
    IdentifierIssuer(iss.prefix, iss.counter, copy(iss.issued_order), copy(iss.map))

has_id(iss::IdentifierIssuer, label::String) = haskey(iss.map, label)

function issue_identifier!(iss::IdentifierIssuer, label::String)::String
    if haskey(iss.map, label)
        return iss.map[label]
    end
    id = iss.prefix * string(iss.counter)
    iss.counter += 1
    iss.map[label] = id
    push!(iss.issued_order, label)
    return id
end

# --- The canonicalization state --------------------------------------------

mutable struct CanonState
    quads::Vector{Quad}
    # blank node label -> quads mentioning it (as subject or object)
    bnode_quads::Dict{String,Vector{Quad}}
    canonical_issuer::IdentifierIssuer
end

function blank_node_labels(quads::Vector{Quad})::Vector{String}
    seen = Dict{String,Bool}()
    out = String[]
    for q in quads, t in q
        if t isa BNode && !haskey(seen, t.label)
            seen[t.label] = true
            push!(out, t.label)
        end
    end
    return out
end

function index_bnode_quads(quads::Vector{Quad})::Dict{String,Vector{Quad}}
    idx = Dict{String,Vector{Quad}}()
    for q in quads
        for t in (q[1], q[3])  # subject, object (predicate is never a bnode here)
            if t isa BNode
                push!(get!(idx, t.label, Quad[]), q)
            end
        end
    end
    return idx
end

# Replace one specific blank node with "a" and every OTHER blank node with
# "z" (spec 4.6.3), so the hash reflects this node's immediate neighborhood
# and nothing about any other node's still-unknown canonical identity.
function relabel_for_hash(t::Term, self_label::String)::Term
    if t isa BNode
        return t.label == self_label ? BNode("a") : BNode("z")
    end
    return t
end

"Hash First Degree Quads (spec 4.6): a hash of this node's immediate quads alone."
function hash_first_degree_quads(state::CanonState, label::String)::String
    qs = get(state.bnode_quads, label, Quad[])
    lines = String[]
    for q in qs
        s = relabel_for_hash(q[1], label)
        p = q[2]
        o = relabel_for_hash(q[3], label)
        push!(lines, nq_line((s, p, o)))
    end
    sort!(lines)
    return sha256hex(join(lines))
end

# Hash Related Blank Node (spec 4.7): the hash of a node related to `label`
# through quad `q`, from `label`'s point of view — used inside Hash N-Degree
# Quads to build the "hash to related bnodes" map for one Nth-degree quad.
function hash_related_blank_node(
    state::CanonState,
    related::String,
    q::Quad,
    issuer::IdentifierIssuer,
    position::Symbol,  # :s or :o — the slot `related` itself occupies in q
)::String
    # go-pflow's identifier issuer (piprate/json-gold's IdentifierIssuer)
    # bakes the N-Quads "_:" sigil directly into every issued id — its
    # prefix is literally "_:c14n" / "_:b", not "c14n" / "b" — and that
    # full string, "_:" included, is what feeds this hash. Getting this
    # byte-for-byte right matters more than it looks: sha256 has no
    # similar-input-similar-output property, so a merely-consistent-with-
    # itself id format (this file's BNode.label never carries "_:";
    # nq_term adds it only at final serialization) still produces a
    # deterministic, internally-valid, but WRONG-relative-to-go-pflow
    # canonicalization the moment two candidates need to be told apart by
    # this hash. Confirmed by instrumenting go-pflow's actual
    # hashNDegreeQuads with debug prints (not from the spec prose, which
    # doesn't mention the sigil at all) and comparing Hash First Degree
    # Quads values node-for-node on test/testdata/cid/tie2.jsonld: three
    # places whose OWN canonical ids matched exactly, while their
    # initial-cells' ids came out permuted, isolating the bug to exactly
    # this "id" computation. The Hash First Degree Quads fallback path
    # needs no such prefix — go-pflow's fallback is the bare hex digest
    # too, already matching.
    id = has_id(state.canonical_issuer, related) ? "_:" * state.canonical_issuer.map[related] :
         has_id(issuer, related) ? "_:" * issuer.map[related] :
         hash_first_degree_quads(state, related)
    # Spec 4.7 steps 2-4, and piprate/json-gold's hashRelatedBlankNode:
    # position ('s'/'o'/'g') + "<predicate IRI>" (the angle brackets are
    # literal hash-input punctuation, not N-Quads syntax here) + id, hashed.
    pred = q[2] isa IRI ? q[2].value : ""
    return sha256hex(String(position) * "<" * pred * ">" * id)
end

# --- Hash N-Degree Quads (spec 4.9) ----------------------------------------
#
# For a blank node whose Hash First Degree Quads value ties with others,
# this explores the graph outward, breadth-first by hash, trying every
# permutation of same-hash related-node groups and keeping the permutation
# that yields the lexicographically smallest issuance path. Recursive: a
# related node with its own first-degree tie is itself resolved by a nested
# call. This is the part of URDNA2015 that a document with no ties never
# reaches — most pflow nets never do, because every node's own quads (an
# arc's source/target strings, a place's x/y) already break ties at the
# first degree. It still has to be implemented correctly, because nothing
# guarantees a future net will be so lucky, and a canonicalizer that is only
# right on asymmetric graphs is not a canonicalizer.
function hash_n_degree_quads(
    state::CanonState,
    label::String,
    issuer::IdentifierIssuer,
)::Tuple{String,IdentifierIssuer}
    issuer = copy(issuer)
    hash_to_related = Dict{String,Vector{String}}()

    for q in get(state.bnode_quads, label, Quad[])
        # pos is the position of `t` (the related node itself, e.g. "s" when
        # it is q's subject) — verified against piprate/json-gold's actual
        # source (createHashToRelated in api_normalize.go: `position =
        # Positions[i]` where i indexes the component that IS `related`).
        for (t, pos) in ((q[1], :s), (q[3], :o))
            if t isa BNode && t.label != label
                h = hash_related_blank_node(state, t.label, q, issuer, pos)
                push!(get!(hash_to_related, h, String[]), t.label)
            end
        end
    end

    data_to_hash = ""
    for h in sort(collect(keys(hash_to_related)))
        data_to_hash *= h
        # Try every ordering of this hash's related nodes and keep whichever
        # produces the lexicographically smallest path string. No early-skip
        # optimization: a partial path being ahead lexicographically does not
        # guarantee the FULL path will be, so cutting a permutation short on
        # a partial comparison risks discarding the true minimum. Ties are
        # rare enough in practice (permutations_lex caps at 8 related nodes)
        # that computing every full path is cheap and unambiguously correct.
        chosen_path = nothing
        chosen_issuer = issuer
        related = sort(unique(hash_to_related[h]))

        for perm in permutations_lex(related)
            issuer_copy = copy(issuer)
            path = ""
            recursion_list = String[]

            for related_label in perm
                # "_:" prepended throughout: see hash_related_blank_node's
                # doc — go-pflow's issuer bakes the sigil into the id
                # itself, and `path` is hash input, not display text.
                if has_id(state.canonical_issuer, related_label)
                    path *= "_:" * state.canonical_issuer.map[related_label]
                elseif has_id(issuer_copy, related_label)
                    path *= "_:" * issuer_copy.map[related_label]
                else
                    issue_identifier!(issuer_copy, related_label)
                    push!(recursion_list, related_label)
                    path *= "_:" * issuer_copy.map[related_label]
                end
            end

            for related_label in recursion_list
                result_hash, result_issuer = hash_n_degree_quads(state, related_label, issuer_copy)
                path *= "_:" * issuer_copy.map[related_label]
                # The recursive hash is wrapped in literal angle brackets
                # before appending — easy to miss (it isn't an N-Quads IRI
                # here, just delimiter punctuation the spec/reference impl
                # both use), and omitting it doesn't look wrong since sha256
                # has no similar-input-similar-output property to visibly
                # betray it: found only by reading piprate/json-gold's
                # hashNDegreeQuads directly (`path += "<" + resultHash +
                # ">"`), not from the spec prose.
                path *= "<" * result_hash * ">"
                issuer_copy = result_issuer
            end

            if chosen_path === nothing || path < chosen_path
                chosen_path = path
                chosen_issuer = issuer_copy
            end
        end

        data_to_hash *= something(chosen_path, "")
        issuer = chosen_issuer
    end

    return sha256hex(data_to_hash), issuer
end

# All permutations of a small Vector{String}, yielded in the exact order
# Hash N-Degree Quads needs to try them (any total order is fine — the
# algorithm compares candidate paths and keeps the smallest, so the order
# permutations are generated in doesn't change the result, only how many are
# generated before a possible early skip; ascending-lex is what the
# reference "NextPermutation" pseudocode produces).
function permutations_lex(v::Vector{String})
    isempty(v) && return [String[]]
    sorted = sort(v)
    n = length(sorted)
    n > 8 && error(
        "hash_n_degree_quads: $(n) same-hash related blank nodes exceeds the " *
        "practical permutation limit (8! = 40320) — no pflow fixture has hit " *
        "this; if one does, this needs Heap's algorithm instead of collecting " *
        "every permutation up front.",
    )
    return collect(Combinatorics_permutations(sorted))
end

# A tiny in-place next_permutation-style generator so we don't add
# Combinatorics.jl as a dependency for this one call site.
function Combinatorics_permutations(v::Vector{String})
    result = Vector{Vector{String}}()
    n = length(v)
    if n == 0
        return [String[]]
    end
    a = copy(v)
    push!(result, copy(a))
    while true
        i = n - 1
        while i >= 1 && a[i] >= a[i + 1]
            i -= 1
        end
        i < 1 && break
        j = n
        while a[j] <= a[i]
            j -= 1
        end
        a[i], a[j] = a[j], a[i]
        reverse!(@view a[(i + 1):n])
        push!(result, copy(a))
    end
    return result
end

# --- Top-level canonicalization (spec 4.4 "Canonicalization Algorithm") ---

"""
    canonicalize(quads) -> Vector{Quad}

Returns `quads` with every blank node relabeled to its canonical identifier
(`_:c14n0`, `_:c14n1`, ...), in the exact scheme go-pflow/pflow-xyz use.
Caller still needs to sort+serialize (`serialize_canonical`) to get the
final N-Quads document — this function returns quads, not text, so tests
can inspect the relabeling directly.
"""
function canonicalize(quads::Vector{Quad})::Vector{Quad}
    state = CanonState(quads, index_bnode_quads(quads), IdentifierIssuer("c14n"))
    non_normalized = blank_node_labels(quads)

    # Step 1: group by first-degree hash.
    hash_to_labels = Dict{String,Vector{String}}()
    for label in non_normalized
        h = hash_first_degree_quads(state, label)
        push!(get!(hash_to_labels, h, String[]), label)
    end

    hashes_sorted = sort(collect(keys(hash_to_labels)))
    deferred_hashes = String[]

    for h in hashes_sorted
        labels = hash_to_labels[h]
        if length(labels) > 1
            push!(deferred_hashes, h)
            continue
        end
        issue_identifier!(state.canonical_issuer, labels[1])
    end

    # Step 2: hash n-degree quads for every hash that still has ties,
    # in hash order; within a tie group, in the ORDER their n-degree hash
    # comes out (spec: collect (hash, label, issuer) triples, sort by hash).
    for h in deferred_hashes
        results = Tuple{String,String,IdentifierIssuer}[]  # (ndegree_hash, label, temp_issuer)
        for label in hash_to_labels[h]
            has_id(state.canonical_issuer, label) && continue
            temp_issuer = IdentifierIssuer("b")
            issue_identifier!(temp_issuer, label)
            nd_hash, result_issuer = hash_n_degree_quads(state, label, temp_issuer)
            push!(results, (nd_hash, label, result_issuer))
        end
        sort!(results; by = r -> r[1])
        for (_, label, result_issuer) in results
            has_id(state.canonical_issuer, label) && continue
            for issued_label in result_issuer.issued_order
                issue_identifier!(state.canonical_issuer, issued_label)
            end
        end
    end

    # Step 3: relabel every quad with the canonical identifiers.
    relabel(t::BNode) = BNode(state.canonical_issuer.map[t.label])
    relabel(t::Term) = t
    return [(relabel(q[1]), q[2], relabel(q[3])) for q in quads]
end

"Canonicalize and serialize in one step — what callers actually want."
function canonical_nquads(quads::Vector{Quad})::String
    return serialize_canonical(canonicalize(quads))
end
