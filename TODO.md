WIP
---


BACKLOG
-------
- [ ] fix active/disabled hilighting in svg - should we do this without calculating delta vectors ?
- [ ] fix arc attributes to have proper boolean values set
- [ ] add `to_jump_problem` alongside `to_ode_problem` in src/algebraic.jl —
      AlgebraicPetri.jl (already a dep) can generate a JumpProblem/SDEProblem
      via DifferentialEquations.jl for discrete-stochastic (Gillespie)
      simulation of the same net; only the ODE path is wired up today.
      Tracked ecosystem-wide as go-pflow ROADMAP.md's G4 (discrete-stochastic
      simulation track / "Petri.jl parity") — the Go side needs to promote
      petri-pilot's existing SSA engine first (G1-G3); this is the much
      smaller, independent Julia-side half of the same goal.

DONE
----
- [x] add a StateMachine to apply transformations & store rates
- [x] fix token count missing in svg
- [x] modify html to scale image when using to_html()
- [x] add white background
- [x] can convert json -> ODE system
    consider building on top of the nets defined w/ named tuples
    idea 

ICEBOX
------
- [ ] add a POST route on pflow.dev to accept input json and return the CID + defs
    likely this is an on-submit form pre-populated w/ the json
