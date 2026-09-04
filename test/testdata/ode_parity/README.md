# ODE parity fixtures

Byte-identical copies of `pflow-xyz/parity/ode/{fixtures.json,expected.json}`
(commit `2f909cd` on `main` — the Tsit5 error-estimate fix). `expected.json`
was generated from go-pflow's fixed solver.

| file | sha256 |
|---|---|
| `fixtures.json` | `63674827ffea51a728fcce8880b5b0b57bf65202e841e6b5ac404799f8f05142` |
| `expected.json` | `6d840239095c77b8b21c761d331e552d32f0be905c8b78711dbed9e965599c2f` |

`test/test_ode_parity.jl` replays them against `to_ode_problem` +
OrdinaryDiffEq's `Tsit5()`, at a tolerance rather than bit-for-bit — a
genuinely different solver implementation, not a byte-exact port like the
SSA fixtures in `test/testdata/ssa/`. If pflow-xyz regenerates these (a
Tsit5/solver change), re-copy both files here and refresh the hashes above.
