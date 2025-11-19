# psolver.js - ODE Solver for Petri Nets

A pure ES6 JavaScript module that provides ODE (Ordinary Differential Equation) solver functionality for Petri net simulation, compatible with the JSON-LD schema from [pflow.xyz](https://pflow.xyz).

## Features

- **ES Module Format**: Modern JavaScript with import/export syntax
- **JSON-LD Compatible**: Parses Petri net models in JSON-LD format from pflow.xyz
- **Tsit5 Solver**: 5th order Runge-Kutta method with adaptive time stepping
- **Built-in Plotting**: SVG-based plotting functionality (no external dependencies)
- **Zero Dependencies**: Pure JavaScript implementation
- **Mass Action Kinetics**: Converts Petri nets to ODE systems

## Quick Start

### Import the Module

```javascript
import { fromJSON, setState, setRates, ODEProblem, solve, Tsit5, SVGPlotter } from './psolver.js';
```

### Load a Petri Net

```javascript
const petriNetData = {
    "@context": "https://pflow.xyz/schema",
    "@type": "PetriNet",
    "@version": "1.1",
    "places": {
        "A": { "@type": "Place", "initial": [10], "x": 100, "y": 100 },
        "B": { "@type": "Place", "initial": [0], "x": 200, "y": 100 }
    },
    "transitions": {
        "t1": { "@type": "Transition", "x": 150, "y": 100 }
    },
    "arcs": [
        { "@type": "Arrow", "source": "A", "target": "t1", "weight": [1] },
        { "@type": "Arrow", "source": "t1", "target": "B", "weight": [1] }
    ]
};

const net = fromJSON(petriNetData);
```

### Set Up and Solve

```javascript
// Set initial conditions and rates
const initialState = setState(net);
const rates = setRates(net);

// Create ODE problem
const prob = new ODEProblem(net, initialState, [0.0, 10.0], rates);

// Solve using Tsit5 solver
const sol = solve(prob, Tsit5());

// Access results
console.log('Final state:', sol.getFinalState());
console.log('Value trajectory:', sol.getVariable('A'));
```

### Plot Results

```javascript
// Plot specific variables
const svg = SVGPlotter.plotSolution(sol, ['A', 'B'], {
    title: 'Petri Net Simulation',
    xlabel: 'Time',
    ylabel: 'Tokens',
    width: 800,
    height: 400
});

// Insert into DOM
document.getElementById('plot').innerHTML = svg;
```

## API Reference

### Data Structures

#### `PetriNet`
Represents a Petri net model with places, transitions, and arcs.

#### `Place`
A place in the Petri net with initial marking, capacity, and position.

#### `Transition`
A transition in the Petri net with role and position.

#### `Arc`
An arc connecting places and transitions with weight and inhibitor properties.

### Functions

#### `fromJSON(data)`
Parse JSON-LD format to create a PetriNet object.

**Parameters:**
- `data`: Object or string containing JSON-LD Petri net definition

**Returns:** `PetriNet` object

#### `setState(net, customState?)`
Create initial state vector from Petri net.

**Parameters:**
- `net`: PetriNet object
- `customState`: Optional custom initial state object

**Returns:** State object mapping place names to token counts

#### `setRates(net, customRates?)`
Create rate vector for transitions.

**Parameters:**
- `net`: PetriNet object
- `customRates`: Optional custom rates object

**Returns:** Rates object mapping transition names to rate constants

#### `ODEProblem(net, initialState, tspan, rates)`
Create an ODE problem for solving.

**Parameters:**
- `net`: PetriNet object
- `initialState`: Initial state object
- `tspan`: Time span array `[t0, tf]`
- `rates`: Rates object

#### `solve(prob, solver, options?)`
Solve the ODE problem.

**Parameters:**
- `prob`: ODEProblem object
- `solver`: Solver object (e.g., `Tsit5()`)
- `options`: Optional solver options
  - `dt`: Initial time step (default: 0.01)
  - `abstol`: Absolute tolerance (default: 1e-6)
  - `reltol`: Relative tolerance (default: 1e-3)
  - `adaptive`: Use adaptive stepping (default: true)

**Returns:** `ODESolution` object

#### `Tsit5()`
Create a Tsit5 solver (5th order Runge-Kutta).

**Returns:** Solver object

### Classes

#### `ODESolution`
Represents the solution to an ODE problem.

**Methods:**
- `getVariable(index)`: Get trajectory for a specific state variable
- `getFinalState()`: Get the final state
- `getState(index)`: Get state at a specific time index

**Properties:**
- `t`: Array of time points
- `u`: Array of state objects
- `stateLabels`: Array of state variable names

#### `SVGPlotter`
Generate SVG plots of simulation results.

**Static Methods:**
- `plotSolution(sol, variables, options)`: Plot ODE solution

**Instance Methods:**
- `setTitle(title)`: Set plot title
- `setXLabel(label)`: Set x-axis label
- `setYLabel(label)`: Set y-axis label
- `addSeries(x, y, label, color)`: Add a data series
- `render()`: Generate SVG string

## Examples

### Example 1: Simple Decay

```javascript
import { fromJSON, setState, setRates, ODEProblem, solve, Tsit5 } from './psolver.js';

const decayNet = fromJSON({
    "@context": "https://pflow.xyz/schema",
    "@type": "PetriNet",
    "places": {
        "substrate": { "initial": [100] }
    },
    "transitions": {
        "decay": {}
    },
    "arcs": [
        { "source": "substrate", "target": "decay", "weight": [1] }
    ]
});

const initialState = setState(decayNet);
const rates = setRates(decayNet, { decay: 0.5 });
const prob = new ODEProblem(decayNet, initialState, [0, 10], rates);
const sol = solve(prob, Tsit5());

console.log('Substrate at t=0:', sol.getVariable('substrate')[0]);
console.log('Substrate at t=10:', sol.getVariable('substrate')[sol.t.length - 1]);
```

### Example 2: Knapsack Problem

See `examples/knapsack_js.html` for a complete interactive example demonstrating the knapsack optimization problem using Petri nets.

## Technical Details

### ODE Conversion

The module converts Petri nets to ODEs using mass action kinetics:

For each transition `t` with rate `k_t`:
- Flux = k_t × ∏(concentration of input places)
- Each input place loses tokens at rate: flux × arc_weight
- Each output place gains tokens at rate: flux × arc_weight

### Tsit5 Solver

The Tsit5 (Tsitouras 5th order) Runge-Kutta method is a modern, efficient ODE solver with:
- 5th order accuracy
- Adaptive time stepping
- Embedded error estimation
- Optimized for non-stiff problems

### JSON-LD Schema

The module is fully compatible with the pflow.xyz JSON-LD schema version 1.1:
- Supports places with initial markings and capacities
- Supports transitions with roles
- Supports arcs with weights and inhibitor properties
- Supports colored Petri nets (arrays collapse to token counts)

## Browser Compatibility

- Modern browsers with ES6 module support
- Chrome 61+
- Firefox 60+
- Safari 11+
- Edge 16+

## Node.js Compatibility

- Node.js 14+ with ES modules enabled

## Testing

Run the test suite:

```bash
node test_psolver.js
```

View the interactive demo:

```bash
# Start a local server
python3 -m http.server 8000

# Open browser to http://localhost:8000/examples/knapsack_js.html
```

## License

See LICENSE file in the repository root.

## Related Projects

- [pflow-jl](https://github.com/pflow-xyz/pflow-jl) - Julia package for Petri net modeling
- [pflow.xyz](https://pflow.xyz) - Visual Petri net editor
- [Petri.jl](https://github.com/AlgebraicJulia/Petri.jl) - Petri net analysis in Julia

## Contributing

Contributions are welcome! Please ensure:
- Code follows ES6 standards
- No external dependencies are added
- All tests pass
- Documentation is updated
