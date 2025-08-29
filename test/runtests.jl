using PEDDY
using Test

@testset "PEDDY.jl" begin
    # Include all test modules
    @testset "IO" begin
        include("test_io_dat_directory.jl")
        # include("test_icsv.jl")
        include("test_netcdf.jl")
        # include("test_output_splitter.jl")
    end
    @testset "QC" begin
        include("test_qc.jl")
    end
    @testset "Data Adjustment" begin
        include("test_interpolation.jl")
        include("test_h2o_correction.jl")
        include("test_despiking.jl")
    end
    @testset "Pipeline" begin
        include("test_pipeline_integration.jl")
    end
end
