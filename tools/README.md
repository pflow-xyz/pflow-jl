# Tools Directory

This directory contains helper scripts for the pflow-jl project.

## Scripts

### patch_petri.sh

**Purpose:** Automated workaround for Petri.jl SteadyStateDiffEq precompilation error

**What it does:**
- Locates the installed Petri.jl package using Julia
- Comments out the `include("solvers.jl")` line that causes precompilation failures
- Removes any direct imports of `NLSolveTerminationCondition`
- Clears precompilation caches for affected packages
- Handles edge cases gracefully (package not found, etc.)

**Usage:**
```bash
sh tools/patch_petri.sh
```

**When to use:**
- Automatically called during Docker build (see Dockerfile)
- Can be run manually after `Pkg.instantiate()` for local development
- Required when using Julia 1.12+ with Petri.jl v1.3.0

**Exit codes:**
- `0`: Success (patch applied or gracefully skipped)
- `1`: Error (script failure)

### test_patch.sh

**Purpose:** Validation script to test the patch_petri.sh script

**What it does:**
1. Installs Julia dependencies using `Pkg.instantiate()`
2. Applies the patch using `patch_petri.sh`
3. Verifies precompilation succeeds
4. Verifies pflow can be loaded

**Usage:**
```bash
sh tools/test_patch.sh
```

**When to use:**
- Testing the patch locally before Docker build
- Validating the workaround in your environment
- CI/CD validation (optional)

**Exit codes:**
- `0`: All tests passed
- `1`: One or more tests failed

## Background

### Why These Scripts Exist

The Petri.jl package (v1.3.0) depends on SteadyStateDiffEq which has a compatibility issue where `NLSolveTerminationCondition` is not defined in newer Julia versions. This causes precompilation to fail.

Since pflow only uses `Petri.Model` for type conversion and doesn't need the solver functionality, we can safely comment out the problematic code without affecting pflow's functionality.

### When Can These Be Removed?

These scripts are temporary workarounds and can be removed when:
1. Petri.jl updates to support SteadyStateDiffEq v2.x, or
2. SteadyStateDiffEq v1.x is updated to be compatible with newer Julia versions

See [WORKAROUND.md](../WORKAROUND.md) in the root directory for more details.

## Maintenance

If you need to modify these scripts:
1. Ensure they remain POSIX-compliant shell scripts (use `/bin/sh`)
2. Test thoroughly before committing
3. Update this README if behavior changes
4. Validate syntax with: `sh -n tools/patch_petri.sh`

## Related Documentation

- [WORKAROUND.md](../WORKAROUND.md) - Detailed explanation of the issue and workaround
- [Dockerfile](../Dockerfile) - See how the patch is applied during Docker build
- [README.md](../README.md) - Main project documentation
