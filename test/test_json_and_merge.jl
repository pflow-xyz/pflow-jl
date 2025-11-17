using Test
using pflow: Pflow, place!, arc!, guard!, transition!, to_json, from_json, merge

@testset "JSON-LD Parsing and Model Merging Tests" begin
    
    @testset "from_json - Parse JSON-LD format" begin
        # Test with the example from the problem statement
        json_str = """{
          "@context": "https://pflow.xyz/schema",
          "@id": "z2xFpT8KDD7FU8tiWSMcB8n6dxJriy2PtZJrcyCwHkn9fmug732",
          "@type": "PetriNet",
          "@version": "1.1",
          "arcs": [
            {
              "@type": "Arrow",
              "inhibitTransition": false,
              "source": "txn0",
              "target": "place0",
              "weight": [1]
            },
            {
              "@type": "Arrow",
              "inhibitTransition": false,
              "source": "place0",
              "target": "txn1",
              "weight": [3]
            },
            {
              "@type": "Arrow",
              "inhibitTransition": true,
              "source": "txn2",
              "target": "place0",
              "weight": [3]
            },
            {
              "@type": "Arrow",
              "inhibitTransition": true,
              "source": "place0",
              "target": "txn3",
              "weight": [1]
            }
          ],
          "places": {
            "place0": {
              "@type": "Place",
              "capacity": [3],
              "initial": [1],
              "offset": 0,
              "x": 130,
              "y": 207
            }
          },
          "token": [
            "https://pflow.xyz/tokens/black"
          ],
          "transitions": {
            "txn0": {
              "@type": "Transition",
              "x": 46,
              "y": 116
            },
            "txn1": {
              "@type": "Transition",
              "x": 227,
              "y": 112
            },
            "txn2": {
              "@type": "Transition",
              "x": 43,
              "y": 307
            },
            "txn3": {
              "@type": "Transition",
              "x": 235,
              "y": 306
            }
          }
        }"""
        
        m = from_json(json_str)
        
        # Check model properties
        @test m.model_type == "PetriNet"
        @test m.version == "1.1"
        @test m.token == ["https://pflow.xyz/tokens/black"]
        
        # Check places
        @test length(m.places) == 1
        @test haskey(m.places, "place0")
        place = m.places["place0"]
        @test place.initial == [1]
        @test place.capacity == [3.0]
        @test place.offset == 0
        @test place.x == 130
        @test place.y == 207
        
        # Check transitions
        @test length(m.transitions) == 4
        @test haskey(m.transitions, "txn0")
        @test haskey(m.transitions, "txn1")
        @test haskey(m.transitions, "txn2")
        @test haskey(m.transitions, "txn3")
        
        txn0 = m.transitions["txn0"]
        @test txn0.x == 46
        @test txn0.y == 116
        
        # Check arcs
        @test length(m.arcs) == 4
        
        # Check regular arcs (not inhibitors)
        regular_arcs = filter(arc -> !arc.inhibit_transition, m.arcs)
        @test length(regular_arcs) == 2
        
        # Check inhibitor arcs
        inhibitor_arcs = filter(arc -> arc.inhibit_transition, m.arcs)
        @test length(inhibitor_arcs) == 2
        
        # Verify specific arcs
        arc1 = filter(arc -> arc.source == "txn0" && arc.target == "place0", m.arcs)[1]
        @test arc1.weight == [1]
        @test arc1.inhibit_transition == false
        
        arc2 = filter(arc -> arc.source == "place0" && arc.target == "txn1", m.arcs)[1]
        @test arc2.weight == [3]
        @test arc2.inhibit_transition == false
        
        arc3 = filter(arc -> arc.source == "txn2" && arc.target == "place0", m.arcs)[1]
        @test arc3.weight == [3]
        @test arc3.inhibit_transition == true
        
        arc4 = filter(arc -> arc.source == "place0" && arc.target == "txn3", m.arcs)[1]
        @test arc4.weight == [1]
        @test arc4.inhibit_transition == true
    end
    
    @testset "from_json - Roundtrip test" begin
        # Create a model, export to JSON, and parse it back
        m1 = Pflow()
        m1.token = ["#ff0000", "#00ff00"]
        
        place!(m1, "p1", initial=[2, 1], capacity=[10.0, 5.0], x=100, y=200, label_text="Place 1")
        place!(m1, "p2", initial=[0], x=200, y=200)
        transition!(m1, "t1", x=150, y=100, role="input", label_text="Trans 1")
        arc!(m1, source="t1", target="p1", weight=[1, 1])
        arc!(m1, source="p1", target="t1", weight=[2])
        guard!(m1, "p2", "t1", [3])
        
        json_str = to_json(m1)
        m2 = from_json(json_str)
        
        # Check that the parsed model matches the original
        @test m2.token == m1.token
        @test length(m2.places) == length(m1.places)
        @test length(m2.transitions) == length(m1.transitions)
        @test length(m2.arcs) == length(m1.arcs)
        
        # Check places
        @test m2.places["p1"].initial == m1.places["p1"].initial
        @test m2.places["p1"].capacity == m1.places["p1"].capacity
        @test m2.places["p1"].label_text == m1.places["p1"].label_text
        
        # Check transitions
        @test m2.transitions["t1"].role == m1.transitions["t1"].role
        @test m2.transitions["t1"].label_text == m1.transitions["t1"].label_text
        
        # Check inhibitor arcs are preserved
        inhibitor_arcs_m1 = filter(arc -> arc.inhibit_transition, m1.arcs)
        inhibitor_arcs_m2 = filter(arc -> arc.inhibit_transition, m2.arcs)
        @test length(inhibitor_arcs_m2) == length(inhibitor_arcs_m1)
    end
    
    @testset "Model merging with merge()" begin
        # Create two simple models
        m1 = Pflow()
        place!(m1, "p1", initial=1, x=100, y=100)
        transition!(m1, "t1", x=150, y=100)
        arc!(m1, source="p1", target="t1", weight=1)
        
        m2 = Pflow()
        place!(m2, "p2", initial=2, x=200, y=100)
        transition!(m2, "t2", x=250, y=100)
        arc!(m2, source="p2", target="t2", weight=2)
        
        # Merge models
        m3 = merge(m1, m2)
        
        # Check merged model has elements from both
        @test length(m3.places) == 2
        @test length(m3.transitions) == 2
        @test length(m3.arcs) == 2
        
        @test haskey(m3.places, "p1")
        @test haskey(m3.places, "p2")
        @test haskey(m3.transitions, "t1")
        @test haskey(m3.transitions, "t2")
    end
    
    @testset "Model merging with name conflicts" begin
        # Create two models with conflicting names
        m1 = Pflow()
        place!(m1, "p1", initial=1, x=100, y=100)
        transition!(m1, "t1", x=150, y=100)
        arc!(m1, source="p1", target="t1", weight=1)
        
        m2 = Pflow()
        place!(m2, "p1", initial=2, x=200, y=100)  # Same name as m1
        transition!(m2, "t1", x=250, y=100)        # Same name as m1
        arc!(m2, source="p1", target="t1", weight=2)
        
        # Merge models
        m3 = merge(m1, m2)
        
        # Check that conflicts are resolved with suffixes
        @test length(m3.places) == 2
        @test length(m3.transitions) == 2
        @test haskey(m3.places, "p1")
        @test haskey(m3.places, "p1_1")
        @test haskey(m3.transitions, "t1")
        @test haskey(m3.transitions, "t1_1")
        
        # Check that arcs reference the renamed elements
        @test length(m3.arcs) == 2
        arc_for_renamed = filter(arc -> arc.source == "p1_1" && arc.target == "t1_1", m3.arcs)
        @test length(arc_for_renamed) == 1
        @test arc_for_renamed[1].weight == [2]
    end
    
    @testset "Model merging with + operator" begin
        # Create two simple models
        m1 = Pflow()
        place!(m1, "p1", initial=1, x=100, y=100)
        
        m2 = Pflow()
        place!(m2, "p2", initial=2, x=200, y=100)
        
        # Use + operator
        m3 = m1 + m2
        
        # Check merged model
        @test length(m3.places) == 2
        @test haskey(m3.places, "p1")
        @test haskey(m3.places, "p2")
    end
    
    @testset "Model merging preserves token colors" begin
        m1 = Pflow()
        m1.token = ["#ff0000", "#00ff00"]
        place!(m1, "p1", initial=1, x=100, y=100)
        
        m2 = Pflow()
        m2.token = ["#0000ff", "#00ff00"]  # One new, one duplicate
        place!(m2, "p2", initial=2, x=200, y=100)
        
        m3 = merge(m1, m2)
        
        # Check that tokens are unioned
        @test length(m3.token) == 3
        @test "#ff0000" in m3.token
        @test "#00ff00" in m3.token
        @test "#0000ff" in m3.token
    end
    
    @testset "Model merging with inhibitor arcs" begin
        m1 = Pflow()
        place!(m1, "p1", initial=5, x=100, y=100)
        transition!(m1, "t1", x=150, y=100)
        guard!(m1, "p1", "t1", 3)
        
        m2 = Pflow()
        place!(m2, "p2", initial=2, x=200, y=100)
        transition!(m2, "t2", x=250, y=100)
        arc!(m2, source="p2", target="t2", weight=1)
        
        m3 = merge(m1, m2)
        
        # Check inhibitor arcs are preserved
        inhibitor_arcs = filter(arc -> arc.inhibit_transition, m3.arcs)
        @test length(inhibitor_arcs) == 1
        @test inhibitor_arcs[1].source == "p1"
        @test inhibitor_arcs[1].target == "t1"
    end
    
    @testset "Complex model merge" begin
        # Create two more complex models
        m1 = Pflow()
        m1.token = ["#ff0000"]
        place!(m1, "input", initial=[3], x=50, y=100, label_text="Input")
        place!(m1, "buffer", initial=[0], x=150, y=100)
        transition!(m1, "process", x=100, y=100, label_text="Process")
        arc!(m1, source="input", target="process", weight=[1])
        arc!(m1, source="process", target="buffer", weight=[1])
        
        m2 = Pflow()
        m2.token = ["#00ff00"]
        place!(m2, "buffer", initial=[0], x=250, y=100)  # Name conflict
        place!(m2, "output", initial=[0], x=350, y=100, label_text="Output")
        transition!(m2, "finalize", x=300, y=100, label_text="Finalize")
        arc!(m2, source="buffer", target="finalize", weight=[1])
        arc!(m2, source="finalize", target="output", weight=[1])
        
        m3 = merge(m1, m2)
        
        # Check the merged model
        @test length(m3.places) == 4  # input, buffer, buffer_1, output
        @test length(m3.transitions) == 2
        @test length(m3.arcs) == 4
        @test length(m3.token) == 2
        
        # Verify both buffers exist
        @test haskey(m3.places, "buffer")
        @test haskey(m3.places, "buffer_1")
    end
    
end
