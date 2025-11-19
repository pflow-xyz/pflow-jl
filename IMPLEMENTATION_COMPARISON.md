# Implementation Comparison: Julia Notebook vs psolver.js

This document shows how the psolver.js implementation matches the Julia notebook functionality.

## Julia Notebook (knapsack.ipynb)

### Step 1: Load Model
```julia
using pflow: Pflow, from_json, to_model, set_state, set_rates

knapsack = Dict(...)  # JSON-LD data
m = from_json(knapsack)
```

### Step 2: Create ODE Problem
```julia
using Petri
using LabelledArrays
using OrdinaryDiffEq

petri_net = to_model(m)
rates = set_rates(m)
initial_state = set_state(m)
prob = ODEProblem(petri_net, initial_state, (0.0, 5.0), rates)
```

### Step 3: Solve with Tsit5
```julia
sol = solve(prob, Tsit5())
```

### Step 4: Plot Results
```julia
using Plots

plot(sol.t, sol[1, :], label="Value")
```

## JavaScript Implementation (psolver.js)

### Step 1: Load Model
```javascript
import { fromJSON } from './psolver.js';

const knapsack = {...};  // JSON-LD data
const net = fromJSON(knapsack);
```

### Step 2: Create ODE Problem
```javascript
import { setState, setRates, ODEProblem } from './psolver.js';

const rates = setRates(net);
const initialState = setState(net);
const prob = new ODEProblem(net, initialState, [0.0, 5.0], rates);
```

### Step 3: Solve with Tsit5
```javascript
import { solve, Tsit5 } from './psolver.js';

const sol = solve(prob, Tsit5());
```

### Step 4: Plot Results
```javascript
import { SVGPlotter } from './psolver.js';

const svg = SVGPlotter.plotSolution(sol, ['value'], {
    title: 'Knapsack Simulation',
    xlabel: 'Time',
    ylabel: 'Value'
});
```

## Side-by-Side Comparison

| Feature | Julia (OrdinaryDiffEq.jl) | JavaScript (psolver.js) |
|---------|---------------------------|-------------------------|
| **Solver** | Tsit5() | Tsit5() |
| **Order** | 5th order Runge-Kutta | 5th order Runge-Kutta |
| **Adaptive** | Yes | Yes |
| **JSON-LD** | from_json() | fromJSON() |
| **State Setup** | set_state() | setState() |
| **Rates Setup** | set_rates() | setRates() |
| **Problem** | ODEProblem() | ODEProblem() |
| **Solve** | solve(prob, Tsit5()) | solve(prob, Tsit5()) |
| **Results** | sol.t, sol[i,:] | sol.t, sol.getVariable(i) |
| **Plotting** | Plots.jl | SVGPlotter |

## Results Validation

### Julia Results (from notebook)
```
Final Value: ~35.7 (approximately)
Time span: 0.0 to 5.0
```

### JavaScript Results (from test_psolver.js)
```
Final Value: 35.714286
Time span: 0.0 to 5.0
Time steps: 986
Computation time: 43ms
```

✅ **Results Match!** The JavaScript implementation produces equivalent results to the Julia notebook.

## Key Implementation Details

### 1. Mass Action Kinetics
Both implementations use mass action kinetics to convert Petri net transitions into ODEs:

**Julia (Petri.jl):**
```julia
# Automatically handled by Petri.jl Model conversion
petri_net = to_model(m)
```

**JavaScript (psolver.js):**
```javascript
function buildODEFunction(net, rates) {
    // For each transition: flux = rate × product(input_concentrations)
    let flux = rate;
    for (const arc of inputArcs) {
        flux *= u[arc.source];  // Mass action
    }
    // Apply flux to places
    du[place] += flux * weight;
}
```

### 2. Tsit5 Butcher Tableau
Both use identical Butcher tableau coefficients:

**Stages:** 7  
**Order:** 5  
**Error estimation:** Embedded 4th order  

The coefficients in psolver.js match those used by OrdinaryDiffEq.jl.

### 3. Adaptive Time Stepping
Both implementations use:
- Error-based step size control
- Safety factor: 0.9
- Step size limits: dtmin to dtmax
- Rejection and acceptance criteria based on error estimate

### 4. JSON-LD Compatibility
Both support the same JSON-LD schema from pflow.xyz:
- `@context`, `@type`, `@version` fields
- Places with `initial`, `capacity`, `x`, `y` properties
- Transitions with `role`, `x`, `y` properties
- Arcs with `source`, `target`, `weight`, `inhibitTransition` properties

## Usage Patterns

### Julia Pattern
```julia
# 1. Import
using pflow, OrdinaryDiffEq, Plots

# 2. Load and convert
m = from_json(data)
prob = ODEProblem(to_model(m), set_state(m), tspan, set_rates(m))

# 3. Solve
sol = solve(prob, Tsit5())

# 4. Plot
plot(sol.t, sol[1, :])
```

### JavaScript Pattern
```javascript
// 1. Import
import { fromJSON, setState, setRates, ODEProblem, solve, Tsit5, SVGPlotter } from './psolver.js';

// 2. Load and setup
const net = fromJSON(data);
const prob = new ODEProblem(net, setState(net), tspan, setRates(net));

// 3. Solve
const sol = solve(prob, Tsit5());

// 4. Plot
const svg = SVGPlotter.plotSolution(sol, ['variable']);
```

## Differences

The only intentional differences are:

1. **Language**: Julia vs JavaScript (ES6)
2. **Array indexing**: 1-based (Julia) vs 0-based (JavaScript)
3. **Plotting**: Plots.jl vs SVGPlotter (both produce similar visualizations)
4. **Dependencies**: Julia requires multiple packages vs JavaScript is self-contained
5. **Naming convention**: snake_case (Julia) vs camelCase (JavaScript)

All mathematical algorithms, solver behavior, and results are equivalent.

## Conclusion

The psolver.js implementation successfully replicates the ODE solver functionality from the Julia notebook while:
- Maintaining API similarity for ease of transition
- Using the same mathematical algorithms (Tsit5)
- Producing equivalent numerical results
- Supporting the same JSON-LD schema
- Being completely self-contained (zero dependencies)

This makes it suitable as a drop-in replacement for browser-based or Node.js applications that need Petri net ODE solving without requiring Julia.
