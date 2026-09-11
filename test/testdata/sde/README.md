# Portable chemical Langevin (SDE) goldens

Byte-exact fixtures for `simulate_sde` (`src/sde.jl`), consumed by
`test/test_sde.jl`. Same portable-path randomness as `test/testdata/ssa/`
(SplitMix64 → xoshiro256\*\*, ported fdlibm log via `plog`, Marsaglia-polar
`normal!`), the same five models as `test/testdata/ssa/`'s
`chain`/`sir`/`dimer`/`gates`/`coffeeshop`, and the same per-model options, so
the two golden sets describe identical nets under two different engines.
Tests compare parsed doubles with `===`; never loosen to a tolerance and
never regenerate a fixture to make a test pass.

## Two of the five carry no series

`gates.json` and `coffeeshop.json` both gate firing in ways continuous
diffusion cannot express (a read arc, an inhibitor, a non-kinetic input, or a
reachable capacity — `gates` by construction, `coffeeshop` because its three
restock transitions make `coffee_beans`/`milk`/`cups`'s capacities reachable).
Their goldens record `"diverged": true` and the engine's own `reason`/
`caveats` strings — copied from `metamodel.Model.Gating()`'s exact wording
(arc counts, `[a b c]`-style place lists) — rather than a fabricated series.
That refusal string is itself part of the byte-exact contract: it must match
`simulate_sde`'s `diverged`/`reason`/`caveats` output field for field, not
just "contains". `chain`, `sir` and `dimer` are unconstrained mass-action nets
and carry a normal `series`/`final` section.

## Provenance

Canonical goldens are `go-pflow/stochastic/testdata/sde/<name>.json`, written
by go-pflow's `cmd/sde-goldens` (the SDE counterpart of `cmd/ssa-goldens`) on
the portable path. The five files here are `cp` copies of those bytes; each
file's `_comment` names the generating commit:
`d84dc017bfe42acd03176b74a7bb91878d72d5f1-dirty` (`cmd/sde-goldens` was
itself a new, uncommitted file in the go-pflow working tree when these were
generated — the commit they were generated *against* is the same one
`test/testdata/ssa/README.md` already pins). If go-pflow ever re-runs
`cmd/sde-goldens`, no double may change — only the `_comment` text — and the
copies and the hashes below must be refreshed.

| file | sha256 |
|---|---|
| chain.json | 0afa2284abbc62464a37df970f795ca1410e507b3b5dcc9d23b81efdd0645458 |
| sir.json | fe17111fa4842ed39935f818a908139a587e47ce720f365f397b75ce1bff75b3 |
| dimer.json | f6636b62b9af2a32cceb70ed9aa10b622e9bdd37e3c8c33d1e3b340a302147bf |
| gates.json | e7fb8473dc55f2e725eed8033e28d9c02f28cf22ce391f127969340353d0fb0b (diverged — no series) |
| coffeeshop.json | d302701c86ca40d7a37e986d5b8308db08b81b015e939b945ae415bc6e2aee7a (diverged — no series) |

These are byte-identical to the copies pflow-rs and pflow-xyz already vendor
(`pflow-rs/crates/pflow-solver/tests/fixtures/sde/`,
`pflow-xyz/parity/sde/`) — verified via `sha256sum` — so this directory
closes the pflow-jl side of the same four-way contract SSA already has:
go-pflow generates, pflow-rs/pflow-xyz/pflow-jl all replay.
