# Portable SSA goldens

Byte-exact fixtures for `simulate_ssa` (`src/ssa.jl`), consumed by
`test/test_ssa.jl`. Shape and semantics: `ssa-spec.md` §4 (the portable SSA
specification shared by go-pflow, pflow-rs, pflow-xyz and pflow-jl). Tests
compare parsed doubles with `===`; never loosen to a tolerance and never
regenerate a fixture to make a test pass.

## Provenance

Canonical goldens are `go-pflow/stochastic/testdata/portable/<name>.json`,
written by go-pflow's `cmd/ssa-goldens` (`make ssa-goldens`) on the portable
path (`Options{Portable: true}`). The files here are byte-identical copies
(`cp`, then `sha256sum` both sides).

Source: go-pflow branch `discrete-stochastic`, commit
`9e67d06bf66c60ca641c8e515d15545deafcb060` (each file's `_comment` names it). If go-pflow
ever re-runs `make ssa-goldens`, no double may change — only the `_comment`
text — and the files and hashes below must be refreshed together.

These Go files were compared double-for-double against the earlier Python
reference goldens (1785 doubles over chain/sir/dimer/coffeeshop): zero
differences. The Julia port reproduces every one of them bit-for-bit.

| file | sha256 |
|---|---|
| chain.json | 892de18e6c8d7899ed8a7081b0da3b1de5c4eda143f16c627ab21919cea61832 |
| sir.json | 192035da7d6b848479a8f2586f1330caed19c8bf26ece2f4743017aef240e683 |
| dimer.json | 5b260cc9b3027c660d87d5a041839941f4deb1107a22728782549bc700e23341 |
| coffeeshop.json | 2e0402f8d6e0ec32956538e480f76d6e3ec28861cb03211eb97be6a68f9f0c53 |
| gates.json | 9a2a35ef18b5218a1afcda49f1755e47feb9942bf07254533971e1d490df7009 |

Options per fixture: chain `{10, 11, 3, 42}`, sir `{40, 81, 8, 11}`, dimer
`{5, 21, 4, 7}`, coffeeshop `{8, 60, 5, 42}`, gates `{20, 41, 4, 5}` (horizon,
samples, realizations, seed).

`gates` is the fifth fixture, beyond the four in ssa-spec.md §4.3: it reaches
the read-arc, inhibitor, non-kinetic input (`kinetic: false`) and capacity
branches of §3.1/§3.3 that the other four never exercise.

Verify a copy against the canonical file:

```sh
sha256sum ../../../../go-pflow/stochastic/testdata/portable/*.json | sed 's#[^ ]*/##' | sha256sum -c
```
