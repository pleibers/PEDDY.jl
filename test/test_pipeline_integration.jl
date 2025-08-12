using Test
using PEDDY
using DimensionalData

@testset "Pipeline Integration Tests" begin
    @testset "MemoryOutput Functionality" begin
        # Test MemoryOutput creation and usage
        output = PEDDY.MemoryOutput()
        @test output isa PEDDY.MemoryOutput

        # Create test data
        test_hf = [1.0 2.0; 3.0 4.0]
        test_lf = [5.0 6.0; 7.0 8.0]

        # Test write_data
        PEDDY.write_data(output, test_hf, test_lf)

        # Test get_results
        hf_result, lf_result = PEDDY.get_results(output)
        @test hf_result == test_hf
        @test lf_result == test_lf
    end

    @testset "Full Pipeline with Interpolation" begin
        # Create test sensor and data
        sensor = PEDDY.CSAT3()
        needed_cols = collect(PEDDY.needs_data_cols(sensor))  # Convert tuple to vector
        n_points = 50
        n_vars = length(needed_cols)

        # Create realistic test data with gaps
        test_data = randn(n_points, n_vars) .* 2 .+ 10  # Wind-like data

        # Create DimArrays
        hd = DimArray(test_data, (Ti(1:n_points), Var(needed_cols)))
         # Add systematic gaps to test interpolation
        # Small gaps that should be filled (≤10 points)
        hd[Ti=10:12, Var=At(:Ux)] .= NaN  # Ux gap (size 3)
        hd[Ti=20:22, Var=At(:Uy)] .= NaN  # Uy gap (size 3) 
        hd[Ti=30:32, Var=At(:Uz)] .= NaN  # Uz gap (size 3)
        hd[Ti=40:42, Var=At(:Ts)] .= NaN  # Ts gap (size 3)
        # Large gaps that should NOT be filled (>10 points)
        hd[Ti=15:30, Var=At(:Ux)] .= NaN  # Large Ux gap (size 16)

        ld = DimArray(rand(10, n_vars), (Ti(1:10), Var(needed_cols)))  # Dummy low freq data

        # Store original data for comparison
        original_data = copy(test_data)

        # Set up pipeline components
        input = PEDDY.PassData(hd, ld)
        output = PEDDY.MemoryOutput()
        gap_filling = PEDDY.GeneralInterpolation(; max_gap_size=10,
                                                 variables=needed_cols,
                                                 method=PEDDY.Linear())

        # Create pipeline with only gap filling enabled
        pipeline = PEDDY.EddyPipeline(; sensor=sensor,
                                      input=input,
                                      quality_control=nothing,
                                      despiking=nothing,
                                      gap_filling=gap_filling,
                                      gas_analyzer=nothing,
                                      double_rotation=nothing,
                                      mrd=nothing,
                                      output=output)

        # Run pipeline
        PEDDY.process(pipeline)

        # Get results
        processed_hf, processed_lf = PEDDY.get_results(output)

        # Test that small gaps were filled
        @test !isnan(processed_hf[Ti=10, Var=At(:Ux)])  # Small gap filled
        @test !isnan(processed_hf[Ti=11, Var=At(:Ux)])
        @test !isnan(processed_hf[Ti=12, Var=At(:Ux)])

        @test !isnan(processed_hf[Ti=20, Var=At(:Uy)])  # Small gap filled
        @test !isnan(processed_hf[Ti=21, Var=At(:Uy)])
        @test !isnan(processed_hf[Ti=22, Var=At(:Uy)])

        @test !isnan(processed_hf[Ti=30, Var=At(:Uz)])  # Small gap filled
        @test !isnan(processed_hf[Ti=40, Var=At(:Ts)])  # Small gap filled

        # Test that large gaps were NOT filled
        @test isnan(processed_hf[Ti=20, Var=At(:Ux)])  # Large gap not filled
        @test isnan(processed_hf[Ti=25, Var=At(:Ux)])  # Large gap not filled

        # Test that valid data was preserved
        valid_indices = .!isnan.(original_data)
        @test processed_hf.data[valid_indices] ≈ original_data[valid_indices]

        # Test that low frequency data was passed through unchanged
        @test processed_lf == ld
    end

    @testset "Pipeline with Multiple Steps" begin
        # Test pipeline with QC + interpolation
        sensor = PEDDY.CSAT3()
        needed_cols = collect(PEDDY.needs_data_cols(sensor))  # Convert tuple to vector
        n_points = 30
        n_vars = length(needed_cols)

        # Create mixed data: some normal, some extreme
        test_data = randn(n_points, n_vars) .* 3 .+ 2  # Mostly normal
        # Column mapping: 1=:diag, 2=:Ux, 3=:Uy, 4=:Uz, 5=:Ts

        # Add some gaps for interpolation testing


        hd = DimArray(test_data, (Ti(1:n_points), Var(needed_cols)))
        hd[Ti=5:7, Var=At(:Ux)] .= NaN   # Small Ux gap (size 3)
        hd[Ti=10:25, Var=At(:Uy)] .= NaN  # Large Uy gap (size 16) that should not be filled

        # Set extreme values at indices that don't overlap with gaps
        hd[Ti=8, Var=At(:Ux)] = 150.0   # Extreme Ux value (outside gap)
        hd[Ti=26, Var=At(:Uy)] = -150.0  # Extreme Uy value (outside gap)
        ld = DimArray(rand(5, n_vars), (Ti(1:5), Var(needed_cols)))

        # Set up pipeline with QC and gap filling
        input = PEDDY.PassData(hd, ld)
        output = PEDDY.MemoryOutput()
        qc = PEDDY.PhysicsBoundsCheck()  # Default physics bounds
        gap_filling = PEDDY.GeneralInterpolation(; max_gap_size=2, variables=[:Ux, :Uy])  # Don't fill single QC-flagged values

        pipeline = PEDDY.EddyPipeline(; sensor=sensor,
                                      input=input,
                                      quality_control=qc,
                                      despiking=nothing,
                                      gap_filling=gap_filling,
                                      gas_analyzer=nothing,
                                      double_rotation=nothing,
                                      mrd=nothing,
                                      output=output)

        # Run pipeline
        PEDDY.process(pipeline)

        # Get results
        processed_hf, processed_lf = PEDDY.get_results(output)

        # Test that extreme values were removed by QC (should be NaN)
        @test isnan(processed_hf[Ti=8, Var=At(:Ux)])   # Extreme Ux value (150.0) removed by QC
        @test isnan(processed_hf[Ti=26, Var=At(:Uy)])  # Extreme Uy value (-150.0) removed by QC

        # Test that large gaps remain unfilled
        @test isnan(processed_hf[Ti=15, Var=At(:Uy)])  # Large gap not filled (part of 10:25 range)
    end

    @testset "Different Interpolation Methods in Pipeline" begin
        # Test pipeline with different interpolation methods
        sensor = PEDDY.CSAT3()
        needed_cols = collect(PEDDY.needs_data_cols(sensor))  # Convert tuple to vector
        n_points = 20
        n_vars = length(needed_cols)

        # Create smooth test data for better interpolation testing
        t = 1:n_points
        smooth_data = zeros(n_points, n_vars)
        for i in 1:n_vars
            smooth_data[:, i] = sin.(t * π / 10) .+ i  # Smooth sinusoidal data
        end

        # Add gaps
        smooth_data[8:9, 1] .= NaN  # Gap in Ux

        hd = DimArray(smooth_data, (Ti(t), Var(needed_cols)))
        ld = DimArray(rand(5, n_vars), (Ti(1:5), Var(needed_cols)))

        # Test different interpolation methods
        methods_to_test = [PEDDY.Linear(), PEDDY.Quadratic(), PEDDY.Cubic()]

        for method in methods_to_test
            input = PEDDY.PassData(copy(hd), ld)
            output = PEDDY.MemoryOutput()
            gap_filling = PEDDY.GeneralInterpolation(; max_gap_size=5,
                                                     variables=[:Ux],
                                                     method=method)

            pipeline = PEDDY.EddyPipeline(; sensor=sensor,
                                          input=input,
                                          quality_control=nothing,
                                          despiking=nothing,
                                          gap_filling=gap_filling,
                                          gas_analyzer=nothing,
                                          double_rotation=nothing,
                                          mrd=nothing,
                                          output=output)

            # Run pipeline
            PEDDY.process(pipeline)

            # Get results
            processed_hf, _ = PEDDY.get_results(output)

            # Test that gaps were filled
            @test !isnan(processed_hf[Ti=8, Var=At(:Ux)])
            @test !isnan(processed_hf[Ti=9, Var=At(:Ux)])

            # Test that interpolated values are reasonable
            @test -2 < processed_hf[Ti=8, Var=At(:Ux)] < 4  # Should be within reasonable range
            @test -2 < processed_hf[Ti=9, Var=At(:Ux)] < 4
        end
    end
end
