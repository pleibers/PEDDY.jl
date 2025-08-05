using Test
using PEDDY
using DimensionalData
using Statistics

@testset "H2O Correction Tests" begin
    @testset "H2OCalibrationCoefficients struct" begin
        # Test struct creation
        coeffs = H2OCalibrationCoefficients(; A=4.82004E3,
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
        sensor_sfc = LICOR("SFC", 2024)
        @test sensor_sfc.calibration_coefficients !== nothing
        @test sensor_sfc.calibration_coefficients.A ≈ 4.82004E3

        sensor_lower = LICOR("LOWER")
        @test sensor_lower.calibration_coefficients !== nothing
        @test sensor_lower.calibration_coefficients.A ≈ 5.49957E3

        sensor_upper = LICOR("UPPER")
        @test sensor_upper.calibration_coefficients !== nothing
        @test sensor_upper.calibration_coefficients.A ≈ 4.76480E3

        sensor_bottom = LICOR("BOTTOM")
        @test sensor_bottom.calibration_coefficients === nothing

        # Test default LICOR (no calibration)
        sensor_default = LICOR()
        @test sensor_default.calibration_coefficients === nothing
    end

    @testset "get_calibration_coefficients function" begin
        # Test with LICOR sensor that has coefficients
        sensor_with_coeffs = LICOR("SFC", 2024)
        coeffs = get_calibration_coefficients(sensor_with_coeffs)
        @test coeffs !== nothing
        @test coeffs.A ≈ 4.82004E3

        # Test with LICOR sensor without coefficients
        sensor_without_coeffs = LICOR()
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

        h2o_conc = compute_h2o_concentration(RH, TA)
        @test h2o_conc > 0
        @test h2o_conc ≈ 14.1 atol = 0.5  # Approximate expected value

        # Test with edge cases
        @test compute_h2o_concentration(0.0, 20.0) ≈ 0.0 atol = 1e-6
        @test compute_h2o_concentration(100.0, 0.0) > 0

        # Test with arrays
        RH_array = [50.0, 60.0, 70.0]
        TA_array = [15.0, 20.0, 25.0]
        h2o_array = compute_h2o_concentration.(RH_array, TA_array)
        @test length(h2o_array) == 3
        @test all(h2o_array .> 0)
    end

    @testset "solve_polynomial_absorptance function" begin
        coeffs = H2OCalibrationCoefficients(; A=4.82004E3,
                                            B=3.79290E6,
                                            C=-1.15477E8,
                                            H2O_Zero=0.7087,
                                            H20_Span=0.9885)

        # Test with typical y value
        y = -0.001
        absorptance = solve_polynomial_absorptance(y, coeffs)
        @test !isnan(absorptance)
        @test absorptance > 0

        # Test with NaN input
        absorptance_nan = solve_polynomial_absorptance(NaN, coeffs)
        @test isnan(absorptance_nan)

        # Test with zero
        absorptance_zero = solve_polynomial_absorptance(0.0, coeffs)
        @test absorptance_zero ≈ 0.0 atol = 1e-10
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
        hf_data = DimArray([h2o_data pressure_data]',
                           (Var([:H2O, :P]), Ti(hf_times)))

        lf_data = DimArray([temp_data rh_data]',
                           (Var([:TA, :RH]), Ti(lf_times)))

        # Create sensor with calibration coefficients
        sensor = LICOR("SFC", 2024)
        gas_analyzer = H2OCalibration()

        # Test that correction runs without error
        original_h2o = copy(hf_data[:H2O, :])
        @test_nowarn correct_gas_analyzer!(gas_analyzer, hf_data, lf_data, sensor)

        # Test that H2O data was modified
        corrected_h2o = hf_data[:H2O, :]
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

        hf_data = DimArray([h2o_data pressure_data]',
                           (Var([:H2O, :P]), Ti(hf_times)))

        lf_data = DimArray([temp_data rh_data]',
                           (Var([:TA, :RH]), Ti(lf_times)))

        # Test with IRGASON sensor (no coefficients)
        irgason_sensor = IRGASON()
        gas_analyzer = H2OCalibration()

        original_h2o = copy(hf_data[:H2O, :])

        # Should return nothing and issue warning, but not error
        result = correct_gas_analyzer!(gas_analyzer, hf_data, lf_data, irgason_sensor)
        @test result === nothing

        # H2O data should be unchanged
        @test all(hf_data[:H2O, :] .≈ original_h2o)
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

        hf_test_data = DimArray([h2o_test pressure_test]',
                                (Var([:H2O, :P]), Ti(hf_times)))

        h2o_lf, pres_lf = resample_to_low_frequency(hf_test_data, :H2O, :P, n_lf,
                                                    n_hf_per_lf, hf_times)

        @test length(h2o_lf) == n_lf
        @test length(pres_lf) == n_lf
        @test h2o_lf[1] ≈ mean(1:10)  # First 10 values
        @test pres_lf[1] ≈ 101.3 * 1000  # Converted to Pa

        # Test calculate_reference_absorptances
        coeffs = H2OCalibrationCoefficients(; A=4.82004E3, B=3.79290E6, C=-1.15477E8,
                                            H2O_Zero=0.7087, H20_Span=0.9885)

        h2o_lf_test = fill(15.0, 5)
        pres_lf_test = fill(101300.0, 5)  # Pa
        rh_test = fill(60.0, 5)  # %
        temp_test = fill(20.0, 5)  # °C

        li_a_raw, rh_a_raw = calculate_reference_absorptances(h2o_lf_test, pres_lf_test,
                                                              rh_test, temp_test, coeffs)

        @test length(li_a_raw) == 5
        @test length(rh_a_raw) == 5
        @test all(.!isnan.(li_a_raw))
        @test all(.!isnan.(rh_a_raw))
        @test all(li_a_raw .> 0)
        @test all(rh_a_raw .> 0)
    end
end
