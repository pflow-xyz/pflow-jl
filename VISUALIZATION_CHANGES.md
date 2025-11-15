# Petri Net Visualization Improvements

## Summary
This update improves the Petri net SVG visualization to match the requirements specified in the issue, with labels appearing below elements and enabled transitions highlighted in green.

## Changes Made

### 1. Label Positioning
**Before:** Labels appeared above elements at `y - 20`
**After:** Labels appear below elements at `y + 28`

**Files Changed:**
- `src/pflow.jl` - `place_element()` function (line ~387)
- `src/pflow.jl` - `transition_element()` function (line ~502)

### 2. Transition State Detection
**New Feature:** Added logic to determine if a transition is enabled

**Implementation:**
- New function `is_transition_enabled(model::Pflow, transition_label::String)::Bool`
- Checks all input arcs (place → transition)
- Verifies each input place has sufficient tokens
- Returns `true` only if all inputs satisfy their weight requirements

**Files Changed:**
- `src/pflow.jl` - Added new function (lines ~359-377)

### 3. Transition Highlighting
**Before:** All transitions displayed with white fill
**After:** Enabled transitions display with green fill (#62fa75)

**Implementation:**
- Modified `transition_element()` to call `is_transition_enabled()`
- Applies `"transition transition-active"` class when enabled
- CSS class `.transition-active` already existed with correct green color

**Files Changed:**
- `src/pflow.jl` - `transition_element()` function (lines ~493-506)

## Visual Result

The improvements can be seen in `demo_visualization.html`:

- **p1** has 2 tokens → **t1** is enabled (green)
- **p2** has 0 tokens → **t2** is disabled (white)
- All labels positioned below their elements
- Token counts visible inside place circles

## Testing

### Unit Test
Created standalone tests verifying:
- Enabled detection works correctly (transition with sufficient input tokens)
- Disabled detection works correctly (transition without sufficient input tokens)

### Visual Test
Created demonstration files:
- `demo_petri_net.svg` - Standalone SVG showing the improvements
- `demo_visualization.html` - Interactive demo with explanations

## Backward Compatibility

These changes are fully backward compatible:
- No changes to the API or function signatures
- No changes to data structures
- Only visual rendering is affected
- Existing Petri nets will automatically benefit from the improvements

## Future Enhancements

Potential future improvements could include:
- Highlighting enabled arcs connected to enabled transitions
- Animation of token flow when transitions fire
- Interactive enabling/disabling of transitions
- Visual indication of transition firing in simulations
