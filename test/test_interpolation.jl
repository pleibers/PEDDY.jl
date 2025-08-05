using Test
using PEDDY
using DimensionalData
using Statistics

@testset "Interpolation Tests" begin
    @testset "Gap Group Identification" begin
        # Test identify_gap_groups function
        @test PEDDY.identify_gap_groups([false, false, false]) == []
        @test PEDDY.identify_gap_groups([true, true, false, true]) == [(1, 2), (4, 4)]
        @test PEDDY.identify_gap_groups([false, true, true, true, false]) == [(2, 4)]
        @test PEDDY.identify_gap_groups([true, false, true, true]) == [(1, 1), (3, 4)]
    end

    @testset "Interpolation Methods" begin
        # Test different interpolation method types
        @test PEDDY.Linear() isa PEDDY.InterpolationMethod
        @test PEDDY.Quadratic() isa PEDDY.InterpolationMethod
        @test PEDDY.Cubic() isa PEDDY.InterpolationMethod

        # Test points needed for each method
        @test PEDDY.get_points_needed(PEDDY.Linear()) == 1
        @test PEDDY.get_points_needed(PEDDY.Quadratic()) == 2
        @test PEDDY.get_points_needed(PEDDY.Cubic()) == 2
    end

    @testset "Small Gap Interpolation" begin
        # Create test data with NaN gaps
        data = [1.0, 2.0, NaN, NaN, 5.0, 6.0, NaN, NaN, NaN, NaN, NaN, 12.0]
        original_data = copy(data)

        # Test linear interpolation with max_gap_size = 3
        PEDDY.interpolate_small_gaps!(data, 3, PEDDY.Linear())

        # Small gaps (≤3) should be filled
        @test !isnan(data[3])  # Gap of size 2
        @test !isnan(data[4])  # Gap of size 2
        @test data[3] ≈ 3.0    # Linear interpolation: 2 + (5-2)*1/3
        @test data[4] ≈ 4.0    # Linear interpolation: 2 + (5-2)*2/3

        # Large gaps (>3) should remain NaN
        @test isnan(data[7])   # Gap of size 5
        @test isnan(data[8])   # Gap of size 5
        @test isnan(data[9])   # Gap of size 5
        @test isnan(data[10])  # Gap of size 5
        @test isnan(data[11])  # Gap of size 5

        # Valid data should be unchanged
        @test data[1] == 1.0
        @test data[2] == 2.0
        @test data[5] == 5.0
        @test data[6] == 6.0
        @test data[12] == 12.0
    end

    @testset "Edge Cases" begin
        # Test empty array
        empty_data = Float64[]
        PEDDY.interpolate_small_gaps!(empty_data, 5, PEDDY.Linear())
        @test length(empty_data) == 0

        # Test array with no missing values
        no_missing = [1.0, 2.0, 3.0, 4.0]
        original = copy(no_missing)
        PEDDY.interpolate_small_gaps!(no_missing, 5, PEDDY.Linear())
        @test no_missing == original

        # Test array with all missing values
        all_missing = [NaN, NaN, NaN, NaN]
        PEDDY.interpolate_small_gaps!(all_missing, 5, PEDDY.Linear())
        @test all(isnan, all_missing)

        # Test gap at beginning (backward fill)
        begin_gap = [NaN, NaN, 3.0, 4.0]
        PEDDY.interpolate_small_gaps!(begin_gap, 5, PEDDY.Linear())
        @test begin_gap[1] == 3.0  # Backward fill
        @test begin_gap[2] == 3.0  # Backward fill

        # Test gap at end (forward fill)
        end_gap = [1.0, 2.0, NaN, NaN]
        PEDDY.interpolate_small_gaps!(end_gap, 5, PEDDY.Linear())
        @test end_gap[3] == 2.0  # Forward fill
        @test end_gap[4] == 2.0  # Forward fill
    end

    @testset "GeneralInterpolation Constructor" begin
        # Test default constructor
        gap_filling = PEDDY.GeneralInterpolation()
        @test gap_filling.max_gap_size == 10
        @test gap_filling.method isa PEDDY.Linear
        @test :Ux in gap_filling.variables
        @test :Uy in gap_filling.variables
        @test :Uz in gap_filling.variables
        @test :Ts in gap_filling.variables
        @test :H2O in gap_filling.variables

        # Test custom constructor
        custom_gap_filling = PEDDY.GeneralInterpolation(; max_gap_size=5,
                                                        variables=[:Ux, :Uy],
                                                        method=PEDDY.Cubic())
        @test custom_gap_filling.max_gap_size == 5
        @test custom_gap_filling.variables == [:Ux, :Uy]
        @test custom_gap_filling.method isa PEDDY.Cubic
    end

    @testset "DimArray Integration" begin
        # Create test DimArray with gaps
        sensor = PEDDY.CSAT3()
        needed_cols = collect(PEDDY.needs_cols(sensor))  # Convert tuple to vector
        n_points = 20
        n_vars = length(needed_cols)

        # Create data with some NaN gaps
        test_data = rand(n_points, n_vars)
        # Column mapping: 1=:diag, 2=:Ux, 3=:Uy, 4=:Uz, 5=:Ts
        # Add gaps to Ux (column 2)
        test_data[5:6, 2] .= NaN  # Small gap (size 2)
        test_data[10:15, 2] .= NaN  # Large gap (size 6)
        # Add gaps to Uy (column 3)  
        test_data[8:9, 3] .= NaN  # Small gap (size 2)

        hd = DimArray(test_data, (Ti(1:n_points), Var(needed_cols)))

        # Test gap filling
        gap_filling = PEDDY.GeneralInterpolation(; max_gap_size=3)
        PEDDY.fill_gaps!(gap_filling, hd, nothing)

        # Small gaps should be filled
        @test !isnan(hd[Ti=5, Var=At(:Ux)])
        @test !isnan(hd[Ti=6, Var=At(:Ux)])
        @test !isnan(hd[Ti=8, Var=At(:Uy)])
        @test !isnan(hd[Ti=9, Var=At(:Uy)])

        # Large gaps should remain
        @test isnan(hd[Ti=10, Var=At(:Ux)])
        @test isnan(hd[Ti=15, Var=At(:Ux)])
    end

    @testset "Method Fallback" begin
        # Test that higher-order methods fall back to linear when insufficient points
        data = [1.0, NaN, 3.0]  # Only 2 valid points

        # Cubic should fall back to linear
        cubic_data = copy(data)
        PEDDY.interpolate_small_gaps!(cubic_data, 5, PEDDY.Cubic())
        @test !isnan(cubic_data[2])
        @test cubic_data[2] ≈ 2.0  # Linear interpolation result

        # Quadratic should fall back to linear
        quad_data = copy(data)
        PEDDY.interpolate_small_gaps!(quad_data, 5, PEDDY.Quadratic())
        @test !isnan(quad_data[2])
        @test quad_data[2] ≈ 2.0  # Linear interpolation result
    end
end
