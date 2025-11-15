#!/bin/sh
# Workaround script for Petri.jl SteadyStateDiffEq precompilation error
# This script patches the installed Petri.jl package to comment out the solvers module
# which causes precompilation failures due to NLSolveTerminationCondition not being defined.
#
# See: WORKAROUND.md for more details about the issue and when this can be removed.

set -e

echo "==> Attempting to locate and patch Petri.jl package..."

# Try to find the Petri package path using Julia
PETRI_PATH=$(julia -e 'using Pkg; println(dirname(Base.find_package("Petri")))' 2>/dev/null | tail -1 || true)

# Check if we found a valid Petri path
if [ -z "$PETRI_PATH" ] || [ ! -f "$PETRI_PATH/Petri.jl" ]; then
  echo "WARNING: Petri package source not found at '$PETRI_PATH'"
  echo "         Skipping patch (package may not be installed yet or is a binary artifact)."
  exit 0
fi

echo "==> Found Petri.jl at: $PETRI_PATH"

# Backup the original file
if [ ! -f "$PETRI_PATH/Petri.jl.bak" ]; then
  echo "==> Creating backup of Petri.jl..."
  cp "$PETRI_PATH/Petri.jl" "$PETRI_PATH/Petri.jl.bak"
fi

# Apply patches to Petri.jl
echo "==> Patching Petri.jl to comment out include(\"solvers.jl\")..."
sed -i 's/^\([[:space:]]*\)include("solvers.jl")/\1# include("solvers.jl")  # Patched for CI to avoid SteadyStateDiffEq precompile error/' "$PETRI_PATH/Petri.jl"

# Remove any direct import lines referencing NLSolveTerminationCondition
echo "==> Removing direct imports of NLSolveTerminationCondition (if any)..."
sed -i '/NLSolveTerminationCondition/d' "$PETRI_PATH/Petri.jl" || true

# Remove compiled caches for the affected packages
echo "==> Clearing precompilation caches..."
rm -rf ~/.julia/compiled/v*/Petri ~/.julia/compiled/v*/SteadyStateDiffEq ~/.julia/compiled/v*/pflow 2>/dev/null || true
rm -rf /root/.julia/compiled/v*/Petri /root/.julia/compiled/v*/SteadyStateDiffEq /root/.julia/compiled/v*/pflow 2>/dev/null || true

echo "==> Patch completed successfully!"
echo ""
echo "Note: This is a temporary workaround. The patched functionality (solvers)"
echo "      is not used by pflow, which only needs Petri.Model for type conversion."
echo "      See WORKAROUND.md for details on when this patch can be removed."
