using PEDDY
using Test

@testset "PEDDY.jl" begin
    # Include all test modules
    include("test_interpolation.jl")
    include("test_pipeline_integration.jl")
    include("test_qc.jl")
end
