# CID parity fixtures

Byte-identical copies of `pflow-xyz/parity/fixtures/*.jsonld` and
`parity/golden.json` (pflow-xyz `main`, commit `1a800dd`), which are
themselves the Go/JS CID parity fixtures — `golden.json`'s CIDs are
`internal/seal.SealJSONLD`'s (Go) output, checked against
`public/seal-cid.mjs` (JS) by `make test-parity`. `test/test_cid.jl`
replays them against `compute_cid` and additionally asserts the full
canonical N-Quads text matches, not just the final CID — a wrong
canonicalization that happened to collide on the final hash would pass a
CID-only check and fail silently on the next fixture.

| file | sha256 |
|---|---|
| `coffee-shop.jsonld` | `b28adc89256254991ade9d746ebc2266e0d804faf84f18fed6aeda92f64349e1` |
| `knapsack.jsonld` | `7ceb53638f892c798febfd00faeef0fd9e64713618a75f852aa99ba3871509c3` |
| `net-a.jsonld` | `f3b7cc20962d9708179990ab503610bb7b6bcfc6708738a91676d71b56b703fb` |
| `net-b.jsonld` | `1acb58b38f1026d7e803d51ca3bceb0b4ccf1016d164bdb10b2c23f54ed5b424` |
| `with-parents.jsonld` | `ce75b8cd51e8ce4f13653ec9a3467b4f7fd857fef0286cfbbec3fb5fa884d767` |
| `golden.json` | `86d8c332e95b164bf735b8aa4e5aa9d96d3782f504625326c21b765c53261659` |

If pflow-xyz regenerates these (a schema/context change), re-copy the
files here and refresh the hashes above.

## `tie1.jsonld` / `tie2.jsonld` — not from pflow-xyz

These two are new, written during this port specifically to exercise
Hash N-Degree Quads' tie-breaking (URDNA2015's hardest case, and the one
a document this shape hits routinely: every arc with the same weight, or
every place with the same capacity, produces first-degree-identical
blank nodes distinguishable only by which arc or place owns them).
`tie1.jsonld` is three arcs sharing `weight: [1]`; `tie2.jsonld` adds
`capacity`/`initial` on three places sharing the same values, tripling
the tied-group count. Their golden CIDs, generated the same way (Go's
`seal.SealJSONLD`) at the same pflow-xyz commit:

| file | CID |
|---|---|
| `tie1.jsonld` | `z4EBG9jDqmAkYxzdaWnPVRZfBcpug1F45LeQJgck4MicFUDPFgS` |
| `tie2.jsonld` | `z4EBG9j8AZSNguvWsF6uwoo9PWqURQV2f5YFiYfLXBb9SpvXgt8` |

`tie2.jsonld` is the fixture that found the two real bugs in this port:
`hash_related_blank_node`'s `position` argument means the position of
`related` itself in the quad (not of the node being hashed — the spec
prose reads ambiguously enough that the reverse also looks plausible,
and produces a valid but wrong-relative-to-go-pflow canonicalization
since sha256 has no similar-input-similar-output property to visibly
betray it), and every issued canonical/temporary blank node identifier
used as hash input needs go-pflow's literal `"_:"` sigil prepended
(`piprate/json-gold`'s `IdentifierIssuer` bakes it into the id string
itself; this port's `BNode.label` deliberately doesn't, adding it only
at final N-Quads serialization). Both were found by instrumenting
go-pflow's actual `hashNDegreeQuads`/`hashFirstDegreeQuads` with debug
prints and comparing node-for-node against this port's output on
`tie2.jsonld`, not by re-reading the spec more carefully — the spec text
alone was not enough to catch either one.
