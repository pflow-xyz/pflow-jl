#!/bin/sh
# Test script to validate the patch_petri.sh script works correctly
# This can be run locally or in CI to verify the patching mechanism

set -e

echo "=========================================="
echo "Testing Petri.jl Patch Script"
echo "=========================================="
echo ""

# Step 1: Install Julia dependencies
echo "Step 1: Installing Julia dependencies..."
julia --project=. -e 'using Pkg; Pkg.instantiate()'
echo "✓ Dependencies installed"
echo ""

# Step 2: Run the patch script
echo "Step 2: Running patch_petri.sh..."
sh tools/patch_petri.sh
echo "✓ Patch script completed"
echo ""

# Step 3: Try to precompile
echo "Step 3: Attempting to precompile packages..."
if julia --project=. -e 'using Pkg; Pkg.precompile()'; then
    echo "✓ Precompilation successful"
else
    echo "✗ Precompilation failed"
    exit 1
fi
echo ""

# Step 4: Verify pflow can be loaded
echo "Step 4: Verifying pflow can be loaded..."
if julia --project=. -e 'using pflow; println("✓ pflow loaded successfully")'; then
    echo "✓ Package load successful"
else
    echo "✗ Package load failed"
    exit 1
fi
echo ""

echo "=========================================="
echo "All tests passed!"
echo "=========================================="
