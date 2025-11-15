# Workaround for SteadyStateDiffEq Precompilation Error

## Issue
The package Petri.jl v1.3.0 depends on SteadyStateDiffEq v1.16.1, which has a compatibility issue with Julia 1.12. The error occurs because `NLSolveTerminationCondition` was removed or relocated in newer versions of SciMLBase.

## Temporary Workaround

### Automated Docker Build Workaround
The Docker build process automatically applies this patch using the `tools/patch_petri.sh` script. No manual intervention is required when using Docker.

To test the Docker build locally:
```bash
docker build --progress=plain -t pflow-jl:local .
```

### Manual Workaround for Local Development
After running `Pkg.instantiate()`, manually patch the Petri.jl source file to comment out the solvers module:

```bash
chmod u+w ~/.julia/packages/Petri/x8N4V/src/Petri.jl
sed -i 's/include("solvers.jl")/# include("solvers.jl")  # Commented out to avoid SteadyStateDiffEq precompilation error/' ~/.julia/packages/Petri/x8N4V/src/Petri.jl
rm -rf ~/.julia/compiled/v1.12/Petri ~/.julia/compiled/v1.12/SteadyStateDiffEq ~/.julia/compiled/v1.12/pflow
```

Alternatively, use the provided patch script:
```bash
sh tools/patch_petri.sh
```

### Testing the Patch
To verify the patch works correctly in your environment:
```bash
sh tools/test_patch.sh
```

This script will:
1. Install dependencies using `Pkg.instantiate()`
2. Apply the patch using `tools/patch_petri.sh`
3. Verify precompilation succeeds
4. Verify pflow can be loaded

## Impact
This workaround disables the solver functionality from Petri.jl. Since pflow only uses `Petri.Model` for type conversion and does not use the solver functions, this does not affect pflow's functionality.

## Permanent Solution
This issue should be resolved when:
1. Petri.jl updates to support SteadyStateDiffEq v2.x, or
2. SteadyStateDiffEq v1.x is updated to be compatible with Julia 1.12

## What pflow Uses from Petri
- `Petri.Model` - a simple struct for representing Petri net models
- Type conversions via `to_model()` function

pflow does NOT use:
- `SteadyStateProblem` from SteadyStateDiffEq
- Any solver functionality from Petri.jl
