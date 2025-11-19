#!/usr/bin/env node

/**
 * Test script for psolver.js
 * Tests the ODE solver with the knapsack problem
 */

import { fromJSON, setState, setRates, ODEProblem, solve, Tsit5, SVGPlotter } from './psolver.js';

// Test data - Knapsack problem from notebook
const knapsackData = {
    "@context": "https://pflow.xyz/schema",
    "@type": "PetriNet",
    "@version": "1.1",
    "places": {
        "item0": { "@type": "Place", "initial": [1], "x": 351, "y": 140 },
        "item1": { "@type": "Place", "initial": [1], "x": 353, "y": 265 },
        "item2": { "@type": "Place", "initial": [1], "x": 351, "y": 417 },
        "item3": { "@type": "Place", "initial": [1], "x": 350, "y": 543 },
        "weight": { "@type": "Place", "x": 880, "y": 320 },
        "value": { "@type": "Place", "x": 765, "y": 145 },
        "capacity": { "@type": "Place", "initial": [15], "x": 730, "y": 541 }
    },
    "transitions": {
        "txn0": { "@type": "Transition", "x": 465, "y": 139 },
        "txn1": { "@type": "Transition", "x": 466, "y": 264 },
        "txn2": { "@type": "Transition", "x": 462, "y": 418 },
        "txn3": { "@type": "Transition", "x": 464, "y": 542 }
    },
    "arcs": [
        { "@type": "Arrow", "source": "txn0", "target": "weight", "weight": [2], "inhibitTransition": false },
        { "@type": "Arrow", "source": "txn0", "target": "value", "weight": [10], "inhibitTransition": false },
        { "@type": "Arrow", "source": "txn1", "target": "weight", "weight": [4], "inhibitTransition": false },
        { "@type": "Arrow", "source": "item0", "target": "txn0", "weight": [1], "inhibitTransition": false },
        { "@type": "Arrow", "source": "txn1", "target": "value", "weight": [10], "inhibitTransition": false },
        { "@type": "Arrow", "source": "item1", "target": "txn1", "weight": [1], "inhibitTransition": false },
        { "@type": "Arrow", "source": "item2", "target": "txn2", "weight": [1], "inhibitTransition": false },
        { "@type": "Arrow", "source": "item3", "target": "txn3", "weight": [1], "inhibitTransition": false },
        { "@type": "Arrow", "source": "txn2", "target": "weight", "weight": [6], "inhibitTransition": false },
        { "@type": "Arrow", "source": "txn2", "target": "value", "weight": [12], "inhibitTransition": false },
        { "@type": "Arrow", "source": "txn3", "target": "value", "weight": [18], "inhibitTransition": false },
        { "@type": "Arrow", "source": "txn3", "target": "weight", "weight": [9], "inhibitTransition": false },
        { "@type": "Arrow", "source": "capacity", "target": "txn0", "weight": [2], "inhibitTransition": false },
        { "@type": "Arrow", "source": "capacity", "target": "txn1", "weight": [4], "inhibitTransition": false },
        { "@type": "Arrow", "source": "capacity", "target": "txn2", "weight": [6], "inhibitTransition": false },
        { "@type": "Arrow", "source": "capacity", "target": "txn3", "weight": [9], "inhibitTransition": false }
    ]
};

console.log('='.repeat(60));
console.log('Testing psolver.js - ODE Solver for Petri Nets');
console.log('='.repeat(60));
console.log();

try {
    // Test 1: Parse JSON-LD
    console.log('Test 1: Parsing JSON-LD format...');
    const net = fromJSON(knapsackData);
    console.log(`✓ Loaded Petri net with ${net.places.size} places and ${net.transitions.size} transitions`);
    console.log();

    // Test 2: Set state and rates
    console.log('Test 2: Setting initial state and rates...');
    const initialState = setState(net);
    const rates = setRates(net);
    console.log('✓ Initial state:', JSON.stringify(initialState, null, 2));
    console.log('✓ Rates:', JSON.stringify(rates, null, 2));
    console.log();

    // Test 3: Create ODE problem
    console.log('Test 3: Creating ODE problem...');
    const tspan = [0.0, 5.0];
    const prob = new ODEProblem(net, initialState, tspan, rates);
    console.log(`✓ Created ODE problem for time span [${tspan[0]}, ${tspan[1]}]`);
    console.log();

    // Test 4: Solve using Tsit5
    console.log('Test 4: Solving ODE with Tsit5 solver...');
    const startTime = Date.now();
    const sol = solve(prob, Tsit5());
    const endTime = Date.now();
    console.log(`✓ Solution computed in ${endTime - startTime}ms`);
    console.log(`✓ Number of time points: ${sol.t.length}`);
    console.log(`✓ Final time: ${sol.t[sol.t.length - 1].toFixed(4)}`);
    console.log();

    // Test 5: Examine solution
    console.log('Test 5: Examining solution...');
    const finalState = sol.getFinalState();
    console.log('✓ Final state:');
    for (const [key, value] of Object.entries(finalState)) {
        console.log(`  - ${key}: ${value.toFixed(6)}`);
    }
    console.log();

    // Test 6: Extract specific variable
    console.log('Test 6: Extracting value trajectory...');
    const valueTrajectory = sol.getVariable('value');
    console.log(`✓ Value at t=0: ${valueTrajectory[0].toFixed(6)}`);
    console.log(`✓ Value at t=end: ${valueTrajectory[valueTrajectory.length - 1].toFixed(6)}`);
    console.log();

    // Test 7: Generate plot
    console.log('Test 7: Generating SVG plot...');
    const svg = SVGPlotter.plotSolution(sol, ['value'], {
        title: 'Knapsack Simulation',
        xlabel: 'Time',
        ylabel: 'Value (tokens)',
        width: 800,
        height: 400
    });
    console.log(`✓ Generated SVG plot (${svg.length} characters)`);
    console.log();

    // Summary
    console.log('='.repeat(60));
    console.log('All tests passed! ✓');
    console.log('='.repeat(60));
    console.log();
    console.log('Summary:');
    console.log(`  - Final value: ${finalState.value.toFixed(3)}`);
    console.log(`  - Simulation time: ${sol.t[sol.t.length - 1].toFixed(2)} time units`);
    console.log(`  - Time steps: ${sol.t.length}`);
    console.log(`  - Computation time: ${endTime - startTime}ms`);
    console.log();

    // Save plot to file
    console.log('Saving plot to test_output.svg...');
    const fs = await import('fs');
    fs.writeFileSync('test_output.svg', svg);
    console.log('✓ Plot saved successfully');

    process.exit(0);
} catch (error) {
    console.error('✗ Test failed:', error.message);
    console.error(error.stack);
    process.exit(1);
}
