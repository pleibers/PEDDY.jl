using Test
using PEDDY
using DimensionalData
using Statistics
using Dates

@testset "Despiking Tests" begin
    @testset "VariableGroup Construction" begin
        # Test VariableGroup construction
        wind_group = PEDDY.VariableGroup("Wind Components", [:Ux, :Uy, :Uz])
        @test wind_group.name == "Wind Components"
        @test wind_group.variables == [:Ux, :Uy, :Uz]
        @test wind_group.spike_threshold == 6.0  # Default threshold
        
        # Test VariableGroup with custom threshold
        temp_group = PEDDY.VariableGroup("Temperature", [:Ts], spike_threshold=5.0)
        @test temp_group.name == "Temperature"
        @test temp_group.variables == [:Ts]
        @test temp_group.spike_threshold == 5.0
    end
    
    @testset "SimpleSigmundDespiking Construction" begin
        # Test default construction
        despiking = SimpleSigmundDespiking()
        @test despiking.window_minutes == 5.0
        @test length(despiking.variable_groups) == 1
        @test despiking.variable_groups[1].name == "Default Sonic"
        @test despiking.variable_groups[1].variables == [:Ux, :Uy, :Uz, :Ts]
        @test despiking.variable_groups[1].spike_threshold == 6.0
        
        # Test custom construction with variable groups
        wind_group = PEDDY.VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=6.0)
        temp_group = PEDDY.VariableGroup("Temperature", [:Ts], spike_threshold=5.0)
        
        custom_despiking = SimpleSigmundDespiking(
            window_minutes=3.0,
            variable_groups=[wind_group, temp_group]
        )
        @test custom_despiking.window_minutes == 3.0
        @test length(custom_despiking.variable_groups) == 2
        @test custom_despiking.variable_groups[1].name == "Wind"
        @test custom_despiking.variable_groups[2].name == "Temperature"
        
        # Test that it implements AbstractDespiking
        @test despiking isa PEDDY.AbstractDespiking
    end
    
    @testset "Rolling Median Calculation" begin
        # Test basic rolling median
        data = [1.0, 2.0, 3.0, 4.0, 5.0]
        result = PEDDY.calculate_rolling_median(data, 3)
        @test result[3] ≈ 3.0  # Center point should be exact median
        
        # Test with NaN values
        data_with_nan = [1.0, NaN, 3.0, 4.0, 5.0]
        result_nan = PEDDY.calculate_rolling_median(data_with_nan, 3)
        @test result_nan[2] ≈ 2.0  # Should handle NaN by using valid neighbors
        
        # Test edge cases
        small_data = [1.0, 2.0]
        result_small = PEDDY.calculate_rolling_median(small_data, 3)
        @test length(result_small) == 2
        @test !isnan(result_small[1])
        @test !isnan(result_small[2])
    end
    
    @testset "Pattern Deviation Calculation" begin
        # Test pattern deviation calculation
        df_di = [1.0, 2.0, 10.0, 3.0, 4.0]  # Spike at position 3
        df_hat = PEDDY.calculate_pattern_deviation(df_di)
        
        # The spike should have higher pattern deviation
        @test df_hat[3] > df_hat[1]
        @test df_hat[3] > df_hat[2]
        @test df_hat[3] > df_hat[4]
        @test df_hat[3] > df_hat[5]
        
        # Test boundary conditions
        @test !isnan(df_hat[1])  # First element
        @test !isnan(df_hat[end])  # Last element
        
        # Test with uniform deviations (no spikes) - should be zero deviations
        uniform_deviations = [0.0, 0.0, 0.0, 0.0, 0.0]  # No deviations from median
        uniform_hat = PEDDY.calculate_pattern_deviation(uniform_deviations)
        @test all(x -> abs(x) < 1e-10, uniform_hat)  # Should be near zero
    end
    
    @testset "Spike Detection with Synthetic Data" begin
        # Create synthetic data with known spikes
        n_points = 1000
        freq_hz = 10.0  # 10 Hz sampling
        dt_ms = round(Int, 1000 / freq_hz)  # Millisecond
        
        # Create time dimension
        start_time = DateTime(2023, 1, 1, 12, 0, 0)
        times = [start_time + Millisecond(i * dt_ms) for i in 0:(n_points-1)]
        
        # Create clean synthetic data
        clean_ux = 2.0 .+ 0.5 .* sin.(2π .* (1:n_points) ./ (60 * freq_hz))  # 1-minute oscillation
        clean_uy = 1.0 .+ 0.3 .* cos.(2π .* (1:n_points) ./ (30 * freq_hz))  # 30-second oscillation
        clean_uz = 0.1 .+ 0.1 .* randn(n_points)  # Small random variations
        clean_ts = 20.0 .+ 2.0 .* sin.(2π .* (1:n_points) ./ (120 * freq_hz))  # 2-minute temperature cycle
        
        # Add spikes at known locations
        spike_indices = [100, 300, 500, 700]
        spike_ux = copy(clean_ux)
        spike_uy = copy(clean_uy)
        spike_uz = copy(clean_uz)
        spike_ts = copy(clean_ts)
        
        # Add large spikes
        for idx in spike_indices
            spike_ux[idx] += 10.0  # Large positive spike
            spike_uy[idx] -= 8.0   # Large negative spike
            spike_uz[idx] += 5.0   # Medium spike
            spike_ts[idx] += 15.0  # Temperature spike
        end
        
        # Create DimArray in proper format
        test_data = hcat(spike_ux, spike_uy, spike_uz, spike_ts)
        high_freq_data = DimArray(
            test_data,
            (Ti(times), Var([:Ux, :Uy, :Uz, :Ts]))
        )
        
        # Apply despiking with custom variable group
        sonic_group = PEDDY.VariableGroup("Sonic Variables", [:Ux, :Uy, :Uz, :Ts], spike_threshold=4.0)
        despiking = SimpleSigmundDespiking(window_minutes=2.0, variable_groups=[sonic_group])
        
        # Count original NaN values
        original_nan_count = sum(isnan.(spike_ux)) + sum(isnan.(spike_uy)) + 
                           sum(isnan.(spike_uz)) + sum(isnan.(spike_ts))
        
        # Apply despiking (this should work without low_frequency_data for this test)
        low_freq_data = nothing
        despike!(despiking, high_freq_data, low_freq_data)
        
        # Count NaN values after despiking
        final_nan_count = sum(isnan.(high_freq_data[Var=At(:Ux)])) + sum(isnan.(high_freq_data[Var=At(:Uy)])) + 
                         sum(isnan.(high_freq_data[Var=At(:Uz)])) + sum(isnan.(high_freq_data[Var=At(:Ts)]))
        
        # Should have detected and removed some spikes
        @test final_nan_count > original_nan_count
        
        # Check that at least some of the known spike locations were detected
        detected_spikes = 0
        for idx in spike_indices
            if isnan(high_freq_data[Var=At(:Ux)][idx]) || isnan(high_freq_data[Var=At(:Uy)][idx]) || 
               isnan(high_freq_data[Var=At(:Uz)][idx]) || isnan(high_freq_data[Var=At(:Ts)][idx])
                detected_spikes += 1
            end
        end
        
        @test detected_spikes > 0  # Should detect at least some spikes
        println("Detected $detected_spikes out of $(length(spike_indices)) artificial spikes")
    end
    
    @testset "H2O Variable Processing" begin
        # Create test data with H2O variable
        n_points = 500
        freq_hz = 10.0
        dt_ms = round(Int, 1000 / freq_hz)
        
        start_time = DateTime(2023, 1, 1, 12, 0, 0)
        times = [start_time + Millisecond(i * dt_ms) for i in 0:(n_points-1)]
        
        # Create synthetic data
        ux_data = 2.0 .+ 0.5 .* randn(n_points)
        uy_data = 1.0 .+ 0.3 .* randn(n_points)
        uz_data = 0.1 .+ 0.1 .* randn(n_points)
        ts_data = 20.0 .+ 2.0 .* randn(n_points)
        h2o_data = 15.0 .+ 3.0 .* randn(n_points)
        
        # Add spikes to H2O data
        h2o_data[100] += 50.0  # Large H2O spike
        h2o_data[200] -= 30.0  # Large negative H2O spike
        
        test_data = hcat(ux_data, uy_data, uz_data, ts_data, h2o_data)
        high_freq_data = DimArray(
            test_data,
            (Ti(times), Var([:Ux, :Uy, :Uz, :Ts, :LI_H2Om_corr]))
        )
        
        # Apply despiking with separate groups for sonic and H2O
        sonic_group = PEDDY.VariableGroup("Sonic", [:Ux, :Uy, :Uz, :Ts], spike_threshold=3.0)
        h2o_group = PEDDY.VariableGroup("H2O", [:LI_H2Om_corr], spike_threshold=3.0)
        despiking = SimpleSigmundDespiking(window_minutes=1.0, variable_groups=[sonic_group, h2o_group])
        low_freq_data = nothing
        
        original_h2o_nan = sum(isnan.(h2o_data))
        despike!(despiking, high_freq_data, low_freq_data)
        final_h2o_nan = sum(isnan.(high_freq_data[Var=At(:LI_H2Om_corr)]))
        
        # Should have detected H2O spikes
        @test final_h2o_nan > original_h2o_nan
        println("H2O spikes detected: $(final_h2o_nan - original_h2o_nan)")
    end
    
    @testset "Edge Cases and Error Handling" begin
        # Test with insufficient data points
        n_points = 5
        times = [DateTime(2023, 1, 1, 12, 0, 0) + Second(i) for i in 1:n_points]
        
        test_data = hcat([1.0, 2.0, 3.0, 4.0, 5.0], [1.0, 2.0, 3.0, 4.0, 5.0])
        small_data = DimArray(
            test_data,
            (Ti(times), Var([:Ux, :Uy]))
        )
        
        despiking = SimpleSigmundDespiking(window_minutes=10.0)  # Very large window
        low_freq_data = nothing
        
        # Should handle gracefully (may generate warnings about window size)
        @test_logs (:warn, r"Adjusted window size") despike!(despiking, small_data, low_freq_data)
        
        # Test with missing variables
        test_data = reshape([1.0, 2.0, 3.0, 4.0, 5.0], 5, 1)
        partial_data = DimArray(
            test_data,
            (Ti(times), Var([:Ux]))
        )
        
        @test_logs (:warn, r"Adjusted window size") despike!(despiking, partial_data, low_freq_data)
        
        # Test with all NaN data
        test_data = hcat(fill(NaN, 100), fill(NaN, 100))
        nan_data = DimArray(
            test_data,
            (Ti([DateTime(2023, 1, 1, 12, 0, 0) + Second(i) for i in 1:100]), Var([:Ux, :Uy]))
        )
        
        @test_logs (:warn, r"Adjusted window size") despike!(despiking, nan_data, low_freq_data)
    end
    
    @testset "Variable Group Functionality" begin
        # Test multiple groups with different thresholds
        n_points = 200
        freq_hz = 10.0
        dt_ms = round(Int, 1000 / freq_hz)
        
        start_time = DateTime(2023, 1, 1, 12, 0, 0)
        times = [start_time + Millisecond(i * dt_ms) for i in 0:(n_points-1)]
        
        # Create synthetic data with different spike characteristics
        ux_data = 2.0 .+ 0.5 .* randn(n_points)
        uy_data = 1.0 .+ 0.3 .* randn(n_points)
        uz_data = 0.1 .+ 0.1 .* randn(n_points)
        ts_data = 20.0 .+ 2.0 .* randn(n_points)
        co2_data = 400.0 .+ 10.0 .* randn(n_points)
        
        # Add different types of spikes
        ux_data[50] += 15.0   # Large wind spike
        ts_data[100] += 25.0  # Large temperature spike
        co2_data[150] += 100.0 # Large CO2 spike
        
        test_data = hcat(ux_data, uy_data, uz_data, ts_data, co2_data)
        high_freq_data = DimArray(
            test_data,
            (Ti(times), Var([:Ux, :Uy, :Uz, :Ts, :CO2]))
        )
        
        # Create groups with different thresholds
        wind_group = PEDDY.VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=5.0)
        temp_group = PEDDY.VariableGroup("Temperature", [:Ts], spike_threshold=4.0)  # More sensitive
        gas_group = PEDDY.VariableGroup("Gas", [:CO2], spike_threshold=8.0)  # Less sensitive
        
        despiking = SimpleSigmundDespiking(
            window_minutes=1.0,
            variable_groups=[wind_group, temp_group, gas_group]
        )
        
        # Count original NaN values
        original_nans = sum(isnan.(test_data))
        
        # Apply despiking
        low_freq_data = nothing
        despike!(despiking, high_freq_data, low_freq_data)
        
        # Count final NaN values
        final_nans = sum(isnan.(high_freq_data.data))
        
        # Should have detected some spikes
        @test final_nans > original_nans
        
        # Test that groups are processed independently
        @test length(despiking.variable_groups) == 3
        @test despiking.variable_groups[1].name == "Wind"
        @test despiking.variable_groups[2].name == "Temperature"
        @test despiking.variable_groups[3].name == "Gas"
        
        println("Variable group test: Detected $(final_nans - original_nans) spikes across all groups")
    end
end
