#!/bin/sh
# tools/patch_petri.sh
# Locate the installed Petri package source and apply a minimal patch to avoid
# SteadyStateDiffEq precompilation errors in CI / Docker builds.
set -eu

PETRI_PATH=$(julia -e 'try using Pkg; p = Base.find_package("Petri"); println(dirname(p)) catch e; println(""); end' 2>/dev/null | tail -1 || true)

if [ -z "$PETRI_PATH" ] || [ ! -f "$PETRI_PATH/src/Petri.jl" ]; then
  echo "Petri package source not found at '$PETRI_PATH' — skipping patch (package may be a binary or not present)."
  exit 0
fi

echo "Patching Petri at: $PETRI_PATH/src/Petri.jl"
backup="$PETRI_PATH/src/Petri.jl.bak.$(date +%s)"
cp "$PETRI_PATH/src/Petri.jl" "$backup"
echo "Backup saved to $backup"

# Comment out include("solvers.jl") safely (only first match)
if grep -q 'include("solvers.jl")' "$PETRI_PATH/src/Petri.jl"; then
  sed -i '0,/include("solvers.jl")/s//# include("solvers.jl")  # Patched by CI to avoid SteadyStateDiffEq precompile error/' "$PETRI_PATH/src/Petri.jl"
  echo "Commented include(\"solvers.jl\")"
else
  echo "No include(\"solvers.jl\") found — nothing to change for include."
fi

# Remove any direct imports/lines referencing NLSolveTerminationCondition to avoid undefined symbol
if grep -q 'NLSolveTerminationCondition' "$PETRI_PATH/src/Petri.jl"; then
  sed -i '/NLSolveTerminationCondition/d' "$PETRI_PATH/src/Petri.jl"
  echo "Removed lines referencing NLSolveTerminationCondition"
else
  echo "No direct references to NLSolveTerminationCondition found in Petri.jl"
fi

# Remove compiled caches to ensure precompilation uses the patched file
echo "Clearing Julia precompile caches for Petri / SteadyStateDiffEq / pflow (if present)"
# Use wildcard to match any Julia version
rm -rf /root/.julia/compiled/v*/Petri /root/.julia/compiled/v*/SteadyStateDiffEq /root/.julia/compiled/v*/pflow || true

echo "Patch completed."
