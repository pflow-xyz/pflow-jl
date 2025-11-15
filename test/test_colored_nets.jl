using Test
using pflow: Pflow, place!, arc!, transition!, to_json, to_svg

@testset "Colored Petri Net Tests" begin
    
    @testset "Array-based data structures" begin
        m = Pflow()
        
        # Test array-based initial values
        place!(m, "p1", initial=[2, 1, 3], x=100, y=100)
        @test m.places["p1"].initial == [2, 1, 3]
        @test isa(m.places["p1"].initial, Vector{Int})
        
        # Test array-based capacity
        place!(m, "p2", initial=[0], capacity=[10.0, 5.0], x=200, y=100)
        @test m.places["p2"].capacity == [10.0, 5.0]
        @test isa(m.places["p2"].capacity, Vector{Float64})
        
        # Test array-based weights
        transition!(m, "t1", x=150, y=100)
        arc!(m, source="p1", target="t1", weight=[1, 1, 2])
        @test m.arcs[1].weight == [1, 1, 2]
        @test isa(m.arcs[1].weight, Vector{Int})
    end
    
    @testset "Backward compatibility - scalar to array conversion" begin
        m = Pflow()
        
        # Scalar initial should be converted to array
        place!(m, "p1", initial=5, x=100, y=100)
        @test m.places["p1"].initial == [5]
        
        # Scalar capacity should be converted to array
        place!(m, "p2", initial=0, capacity=10, x=200, y=100)
        @test m.places["p2"].capacity == [10.0]
        
        # Scalar weight should be converted to array
        transition!(m, "t1", x=150, y=100)
        arc!(m, source="p1", target="t1", weight=2)
        @test m.arcs[1].weight == [2]
        
        # Nothing values should create empty arrays
        place!(m, "p3", x=300, y=100)
        @test m.places["p3"].initial == []
        @test m.places["p3"].capacity == []
    end
    
    @testset "Token color definitions" begin
        m = Pflow()
        
        # Test default empty token array
        @test m.token == []
        @test isa(m.token, Vector{String})
        
        # Test setting token colors
        m.token = ["#ff0000", "#00ff00", "#0000ff"]
        @test length(m.token) == 3
        @test m.token[1] == "#ff0000"
    end
    
    @testset "JSON-LD output format" begin
        m = Pflow()
        m.token = ["#ff0000"]
        
        place!(m, "p1", initial=[2], x=100, y=100)
        transition!(m, "t1", x=150, y=100)
        arc!(m, source="p1", target="t1", weight=[1])
        
        json_str = to_json(m)
        
        # Check JSON-LD @type fields
        @test occursin("\"@type\":\"Place\"", replace(json_str, " " => ""))
        @test occursin("\"@type\":\"Transition\"", replace(json_str, " " => ""))
        @test occursin("\"@type\":\"Arc\"", replace(json_str, " " => ""))
        
        # Check token field
        @test occursin("\"token\"", json_str)
        @test occursin("#ff0000", json_str)
        
        # Check array values in JSON
        @test occursin("[2]", json_str)  # initial as array
        @test occursin("[1]", json_str)  # weight as array
    end
    
    @testset "Label support" begin
        m = Pflow()
        
        place!(m, "p1", initial=1, x=100, y=100, label_text="Input")
        transition!(m, "t1", x=150, y=100, label_text="Process")
        
        @test m.places["p1"].label_text == "Input"
        @test m.transitions["t1"].label_text == "Process"
        
        # Test JSON output includes labels
        json_str = to_json(m)
        @test occursin("\"label\":\"Input\"", replace(json_str, " " => ""))
        @test occursin("\"label\":\"Process\"", replace(json_str, " " => ""))
    end
    
    @testset "SVG with CSS classes" begin
        m = Pflow()
        place!(m, "p1", initial=2, x=100, y=100)
        transition!(m, "t1", x=150, y=100)
        arc!(m, source="p1", target="t1", weight=1)
        
        svg_str = to_svg(m)
        
        # Check for CSS classes matching pflow-xyz style
        @test occursin("class=\"place\"", svg_str) || occursin("class=\"place ", svg_str)
        @test occursin("class=\"transition\"", svg_str) || occursin("class=\"transition ", svg_str)
        @test occursin("class=\"arc\"", svg_str)
        @test occursin("class=\"weight-bg\"", svg_str)
        @test occursin("<style>", svg_str)
        
        # Check for proper SVG structure
        @test occursin("<svg", svg_str)
        @test occursin("xmlns=\"http://www.w3.org/2000/svg\"", svg_str)
        @test occursin("viewBox=", svg_str)
    end
    
    @testset "Inhibitor arcs" begin
        m = Pflow()
        place!(m, "p1", initial=5, x=100, y=100)
        transition!(m, "t1", x=150, y=100)
        guard!(m, "p1", "t1", 3)
        
        @test m.arcs[1].inhibit_transition == true
        @test m.arcs[1].weight == [3]
        
        # Check JSON output
        json_str = to_json(m)
        @test occursin("\"inhibitTransition\":true", replace(json_str, " " => ""))
    end
end
