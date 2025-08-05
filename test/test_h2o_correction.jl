using Test
using PEDDY
using DimensionalData
using Statistics

@testset "H2O Correction Tests" begin
    @testset "H2OCalibrationCoefficients struct" begin
        # Test struct creation
        coeffs = H2OCalibrationCoefficients{Float64}(; A=4.82004E3,
                                            B=3.79290E6,
                                            C=-1.15477E8,
                                            H2O_Zero=0.7087,
                                            H20_Span=0.9885)

        @test coeffs.A ≈ 4.82004E3
        @test coeffs.B ≈ 3.79290E6
        @test coeffs.C ≈ -1.15477E8
        @test coeffs.H2O_Zero ≈ 0.7087
        @test coeffs.H20_Span ≈ 0.9885
    end

    @testset "H2OCalibration struct" begin
        # Test default construction
        gas_analyzer = H2OCalibration()
        @test gas_analyzer.h2o_variable == :H2O
        @test gas_analyzer.pressure_var == :P
        @test gas_analyzer.temp_var == :TA
        @test gas_analyzer.rh_var == :RH

        # Test custom construction
        custom_analyzer = H2OCalibration(; h2o_variable=:H2O_custom,
                                         pressure_var=:P_custom,
                                         temp_var=:T_custom,
                                         rh_var=:RH_custom)
        @test custom_analyzer.h2o_variable == :H2O_custom
        @test custom_analyzer.pressure_var == :P_custom
        @test custom_analyzer.temp_var == :T_custom
        @test custom_analyzer.rh_var == :RH_custom
    end

    @testset "LICOR sensor with calibration coefficients" begin
        # Test predefined sensor configurations
        calibration_coefficients = PEDDY.default_calibration_coefficients("SFC", 2024)
        @test calibration_coefficients !== nothing
        @test calibration_coefficients.A ≈ 4.82004E3

        calibration_coefficients_lower = PEDDY.default_calibration_coefficients("LOWER")
        @test calibration_coefficients_lower !== nothing
        @test calibration_coefficients_lower.A ≈ 5.49957E3

        calibration_coefficients_upper = PEDDY.default_calibration_coefficients("UPPER")
        @test calibration_coefficients_upper !== nothing
        @test calibration_coefficients_upper.A ≈ 4.76480E3

        calibration_coefficients_bottom = PEDDY.default_calibration_coefficients("BOTTOM")
        @test calibration_coefficients_bottom === nothing

        # Test default LICOR (no calibration)
        calibration_coefficients_default = PEDDY.default_calibration_coefficients()
        @test calibration_coefficients_default === nothing
    end

    @testset "get_calibration_coefficients function" begin
        # Test with LICOR sensor that has coefficients
        coeffs = PEDDY.default_calibration_coefficients("SFC", 2024)
        sensor_with_coeffs = LICOR(; calibration_coefficients=coeffs)
        coeffs = get_calibration_coefficients(sensor_with_coeffs)
        @test coeffs !== nothing
        @test coeffs.A ≈ 4.82004E3

        # Test with LICOR sensor without coefficients
        sensor_without_coeffs = LICOR(; calibration_coefficients=nothing)
        coeffs_none = get_calibration_coefficients(sensor_without_coeffs)
        @test coeffs_none === nothing

        # Test with IRGASON sensor (no coefficients)
        irgason_sensor = IRGASON()
        irgason_coeffs = get_calibration_coefficients(irgason_sensor)
        @test irgason_coeffs === nothing
    end

    @testset "compute_h2o_concentration function" begin
        # Test with typical values
        RH = 60.0  # 60% relative humidity
        TA = 20.0  # 20°C temperature

        h2o_conc = PEDDY.compute_h2o_concentration(RH, TA)
        @test h2o_conc > 0
        @test h2o_conc ≈ 575.0 atol = 1.0  # Approximate expected value

        # Test with edge cases
        @test PEDDY.compute_h2o_concentration(0.0, 20.0) ≈ 0.0 atol = 1e-6
        @test PEDDY.compute_h2o_concentration(100.0, 0.0) > 0

        # Test with arrays
        RH_array = [50.0, 60.0, 70.0]
        TA_array = [15.0, 20.0, 25.0]
        h2o_array = PEDDY.compute_h2o_concentration.(RH_array, TA_array)
        @test length(h2o_array) == 3
        @test all(h2o_array .> 0)
    end

    @testset "solve_polynomial_absorptance function" begin
        coeffs = H2OCalibrationCoefficients{Float64}(; A=4.82004E3,
                                            B=3.79290E6,
                                            C=-1.15477E8,
                                            H2O_Zero=0.7087,
                                            H20_Span=0.9885)

        # Test with typical y value
        y = -0.001
        absorptance = PEDDY.solve_polynomial_absorptance(y, coeffs)
        @test !isnan(absorptance)
        @test absorptance < 0

        # Test with NaN input
        absorptance_nan = PEDDY.solve_polynomial_absorptance(NaN, coeffs)
        @test isnan(absorptance_nan)

        # Test with zero (polynomial solver may not return exactly zero)
        absorptance_zero = PEDDY.solve_polynomial_absorptance(0.0, coeffs)
        @test absorptance_zero ≈ 0.0 atol = 5e-3
    end

    @testset "H2O correction integration test" begin
        # Create test data
        n_hf = 1800  # 30 minutes at 1 Hz (simplified)
        n_lf = 30    # 30 minutes at 1/60 Hz

        # Create time dimensions
        hf_times = collect(1:n_hf)
        lf_times = collect(1:60:n_hf)  # Every 60 seconds

        # Create synthetic high-frequency data
        h2o_data = 15.0 .+ 2.0 .* randn(n_hf)  # ~15 mmol/m³ with noise
        pressure_data = 101.3 .+ 0.1 .* randn(n_hf)  # ~101.3 kPa with noise

        # Create synthetic low-frequency data
        temp_data = 20.0 .+ 1.0 .* randn(n_lf)  # ~20°C with noise
        rh_data = 0.6 .+ 0.1 .* randn(n_lf)  # ~60% RH with noise

        # Create DimArrays
        hf_data = DimArray(hcat(h2o_data, pressure_data),
                           (Ti(hf_times), Var([:H2O, :P])))

        lf_data = DimArray(hcat(temp_data, rh_data),
                           (Ti(lf_times), Var([:TA, :RH])))

        # Create sensor with calibration coefficients
        sensor = LICOR(; calibration_coefficients=PEDDY.default_calibration_coefficients("SFC", 2024))
        gas_analyzer = H2OCalibration()

        # Test that correction runs without error
        original_h2o = copy(hf_data[Var=At(:H2O)])
        @test_nowarn correct_gas_analyzer!(gas_analyzer, hf_data, lf_data, sensor)

        # Test that H2O data was modified
        corrected_h2o = hf_data[Var=At(:H2O)]
        @test !all(original_h2o .≈ corrected_h2o)

        # Test that corrected values are reasonable
        @test all(.!isnan.(corrected_h2o))
        @test all(corrected_h2o .> 0)  # H2O should be positive
        @test mean(corrected_h2o) > 0
    end

    @testset "H2O correction with sensor without coefficients" begin
        # Create minimal test data
        n_hf = 100
        n_lf = 10

        hf_times = collect(1:n_hf)
        lf_times = collect(1:10:n_hf)

        h2o_data = fill(15.0, n_hf)
        pressure_data = fill(101.3, n_hf)
        temp_data = fill(20.0, n_lf)
        rh_data = fill(0.6, n_lf)

        hf_data = DimArray(hcat(h2o_data, pressure_data),
                           (Ti(hf_times), Var([:H2O, :P])))

        lf_data = DimArray(hcat(temp_data, rh_data),
                           (Ti(lf_times), Var([:TA, :RH])))

        # Test with IRGASON sensor (no coefficients)
        irgason_sensor = IRGASON()
        gas_analyzer = H2OCalibration()

        original_h2o = copy(hf_data[Var=At(:H2O)])

        # Should return nothing and issue warning, but not error
        result = correct_gas_analyzer!(gas_analyzer, hf_data, lf_data, irgason_sensor)
        @test result === nothing

        # H2O data should be unchanged
        @test all(hf_data[Var=At(:H2O)] .≈ original_h2o)
    end

    @testset "Helper functions unit tests" begin
        # Test resample_to_low_frequency
        n_hf = 120
        n_lf = 12
        n_hf_per_lf = 10
        hf_times = collect(1:n_hf)

        # Create test data
        h2o_test = collect(1.0:n_hf)  # Linear increasing
        pressure_test = fill(101.3, n_hf)

        hf_test_data = DimArray(hcat(h2o_test, pressure_test),
                                (Ti(hf_times), Var([:H2O, :P])))

        h2o_lf, pres_lf = PEDDY.resample_to_low_frequency(hf_test_data, :H2O, :P, n_lf,
                                                    n_hf_per_lf, hf_times)

        @test length(h2o_lf) == n_lf
        @test length(pres_lf) == n_lf
        @test h2o_lf[1] ≈ mean(1:10)  # First 10 values
        @test pres_lf[1] ≈ 101.3 * 1000  # Converted to Pa

        # Test calculate_reference_absorptances
        coeffs = H2OCalibrationCoefficients{Float64}(; A=4.82004E3, B=3.79290E6, C=-1.15477E8,
                                            H2O_Zero=0.7087, H20_Span=0.9885)

        h2o_lf_test = fill(15.0, 5)
        pres_lf_test = fill(101300.0, 5)  # Pa
        rh_test = fill(60.0, 5)  # %
        temp_test = fill(20.0, 5)  # °C

        li_a_raw, rh_a_raw = PEDDY.calculate_reference_absorptances(h2o_lf_test, pres_lf_test,
                                                              rh_test, temp_test, coeffs)

        @test length(li_a_raw) == 5
        @test length(rh_a_raw) == 5
        @test all(.!isnan.(li_a_raw))
        @test all(.!isnan.(rh_a_raw))
        # Absorptance values can be negative in some conditions
        @test all(isfinite.(li_a_raw))
        @test all(isfinite.(rh_a_raw))
    end
end
