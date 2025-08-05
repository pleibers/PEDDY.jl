export H2OCalibration
export correct_gas_analyzer!
export get_calibration_coefficients

using Polynomials
using Statistics

"""
    get_calibration_coefficients(sensor)

Extract H2O calibration coefficients from sensor if available.
Returns nothing if sensor doesn't have calibration coefficients.
"""
function get_calibration_coefficients(sensor::AbstractSensor)
    return hasfield(typeof(sensor), :calibration_coefficients) ?
           sensor.calibration_coefficients : nothing
end

"""
    H2OCalibration

Gas analyzer correction for H2O measurements using calibration coefficients.
Implements bias correction based on relative humidity reference measurements.
Calibration coefficients are extracted from the sensor during correction.

Fields:
- `h2o_variable`: H2O variable name, must be in high frequency data (default: :H2O)
- `pressure_var`: Pressure variable name, must be in high frequency data (default: :P)
- `temp_var`: Temperature variable name in slow data (default: :TA)
- `rh_var`: Relative humidity variable name in slow data (default: :RH)
"""
@kwdef struct H2OCalibration <: AbstractGasAnalyzer
    h2o_variable::Symbol = :H2O
    pressure_var::Symbol = :P
    temp_var::Symbol = :TA
    rh_var::Symbol = :RH
end

"""
    compute_h2o_concentration(RH, TA)

Compute H2O concentration from relative humidity (RH) and temperature (TA).

Parameters:
- RH: Relative humidity in percentage
- TA: Temperature in degrees Celsius

Returns:
- H2O concentration in mmol m⁻³
"""
function compute_h2o_concentration(RH, TA)
    es = 611.2 * exp(17.67 * TA / (TA + 243.5)) * (RH / 100)  # Pa
    h2o_concentration = (1000 * es / (8.314 * (TA + 273.15)))  # mmol m⁻³
    return h2o_concentration
end

"""
    solve_polynomial_absorptance(y, coeffs)

Solve the cubic polynomial to find absorptance from normalized y value.
Polynomial: A*a + B*a² + C*a³ + y = 0

Parameters:
- y: Normalized y value (negated)
- coeffs: H2OCalibrationCoefficients struct with polynomial coefficients A, B, C

Returns:
- Real root of the polynomial (absorptance)
"""
function solve_polynomial_absorptance(y, coeffs)
    if isnan(y)
        return NaN
    end

    # Create polynomial: C*a³ + B*a² + A*a + y = 0
    poly = Polynomial([y, coeffs.A, coeffs.B, coeffs.C])
    roots_poly = roots(poly)

    # Find the real root (should be only one for physical solution)
    real_roots = [r for r in roots_poly if abs(imag(r)) < 1e-10]

    if isempty(real_roots)
        return NaN
    end

    return real(real_roots[1])
end

"""
    resample_to_low_frequency(high_frequency_data, h2o_var, pressure_var, n_lf, n_hf_per_lf, hf_time)

Resample high-frequency H2O and pressure data to low-frequency averages.

Returns:
- h2o_lf_avg: Low-frequency averaged H2O data
- pres_lf_avg: Low-frequency averaged pressure data (in Pa)
"""
function resample_to_low_frequency(high_frequency_data, h2o_var, pressure_var, n_lf,
                                   n_hf_per_lf, hf_time)
    h2o_lf_avg = Vector{Float64}(undef, n_lf)
    pres_lf_avg = Vector{Float64}(undef, n_lf)

    for i in 1:n_lf
        start_idx = (i - 1) * n_hf_per_lf + 1
        end_idx = min(i * n_hf_per_lf, length(hf_time))

        if start_idx <= length(hf_time)
            h2o_lf_avg[i] = mean(skipmissing(high_frequency_data[h2o_var,
                                                                 start_idx:end_idx]))
            pres_lf_avg[i] = mean(skipmissing(high_frequency_data[pressure_var,
                                                                  start_idx:end_idx]))
        else
            h2o_lf_avg[i] = NaN
            pres_lf_avg[i] = NaN
        end
    end

    # Convert pressure to Pa
    pres_lf_avg .*= 1000

    return h2o_lf_avg, pres_lf_avg
end

"""
    calculate_reference_absorptances(h2o_lf_avg, pres_lf_avg, rh_data, temp_data, coeffs)

Calculate reference absorptances from LI measurements and RH/temperature data.

Returns:
- li_a_raw_lf: LI raw absorptances at low frequency
- rh_a_raw_lf: RH reference raw absorptances at low frequency
"""
function calculate_reference_absorptances(h2o_lf_avg, pres_lf_avg, rh_data, temp_data,
                                          coeffs)
    # Compute reference H2O concentration from RH and temperature
    rh_h2o_avg = compute_h2o_concentration.(rh_data, temp_data)

    # Calculate normalized y values for polynomial
    li_y_lf = h2o_lf_avg ./ pres_lf_avg .* 1000  # mmol m⁻³ kPa⁻¹
    rh_y_lf = rh_h2o_avg ./ pres_lf_avg .* 1000  # mmol m⁻³ kPa⁻¹

    # Calculate absorptances using polynomial
    li_a_lf = [solve_polynomial_absorptance(-y, coeffs) for y in li_y_lf]
    rh_a_lf = [solve_polynomial_absorptance(-y, coeffs) for y in rh_y_lf]

    # Calculate raw absorptances
    li_a_raw_lf = li_a_lf .* pres_lf_avg ./ 1000 ./ coeffs.H20_Span
    rh_a_raw_lf = rh_a_lf .* pres_lf_avg ./ 1000 ./ coeffs.H20_Span

    return li_a_raw_lf, rh_a_raw_lf
end

"""
    interpolate_to_high_frequency(li_a_raw_lf, rh_a_raw_lf, n_hf_per_lf, hf_time, n_lf)

Interpolate low-frequency absorptances to high-frequency using forward fill.

Returns:
- li_a_raw_hf: LI raw absorptances at high frequency
- rh_a_raw_hf: RH reference raw absorptances at high frequency
"""
function interpolate_to_high_frequency(li_a_raw_lf, rh_a_raw_lf, n_hf_per_lf, hf_time, n_lf)
    li_a_raw_hf = Vector{Float64}(undef, length(hf_time))
    rh_a_raw_hf = Vector{Float64}(undef, length(hf_time))

    for i in 1:length(hf_time)
        lf_idx = min(div(i - 1, n_hf_per_lf) + 1, n_lf)
        li_a_raw_hf[i] = li_a_raw_lf[lf_idx]
        rh_a_raw_hf[i] = rh_a_raw_lf[lf_idx]
    end

    return li_a_raw_hf, rh_a_raw_hf
end

"""
    apply_bias_correction(h2o_data, pres_data, li_a_raw_hf, rh_a_raw_hf, coeffs)

Apply bias correction to high-frequency H2O measurements.

Returns:
- h2o_corrected: Bias-corrected H2O concentrations
"""
function apply_bias_correction(h2o_data, pres_data, li_a_raw_hf, rh_a_raw_hf, coeffs)
    # Calculate high-frequency normalized y and absorptance
    li_y_hf = h2o_data ./ pres_data .* 1000
    li_a_hf = [solve_polynomial_absorptance(-y, coeffs) for y in li_y_hf]
    li_a_raw_hf_calc = li_a_hf .* pres_data ./ 1000 ./ coeffs.H20_Span

    # Apply bias correction formula
    li_a_corr_hf = ((1 .- rh_a_raw_hf) .* li_a_raw_hf_calc .- li_a_raw_hf .+ rh_a_raw_hf) ./
                   (1 .- li_a_raw_hf)

    # Convert back to concentration
    li_a_norm_hf = li_a_corr_hf ./ pres_data .* 1000 .* coeffs.H20_Span
    li_y_norm_hf = coeffs.A .* li_a_norm_hf .+ coeffs.B .* li_a_norm_hf .^ 2 .+
                   coeffs.C .* li_a_norm_hf .^ 3
    h2o_corrected = li_y_norm_hf .* pres_data ./ 1000  # mmol/m³

    # Round to 1 decimal place
    return round.(h2o_corrected, digits=1)
end

"""
    correct_gas_analyzer!(gas_analyzer::H2OCalibration, high_frequency_data, low_frequency_data, sensor; kwargs...)

Apply H2O calibration correction to gas analyzer measurements.

This function:
1. Extracts calibration coefficients from gas_analyzer or sensor
2. Resamples high-frequency data to low-frequency intervals
3. Computes reference H2O from RH and temperature in slow data
4. Calculates absorptances using calibration polynomial
5. Applies bias correction to high-frequency H2O measurements
6. Replaces original H2O variable with corrected data in-place

Parameters:
- gas_analyzer: H2OCalibration configuration
- high_frequency_data: High-frequency measurements (DimArray)
- low_frequency_data: Low-frequency/slow measurements (DimArray)
- sensor: Sensor instance (used to extract calibration coefficients if not provided in gas_analyzer)
"""
function correct_gas_analyzer!(gas_analyzer::H2OCalibration, high_frequency_data,
                               low_frequency_data, sensor; kwargs...)
    # Get calibration coefficients from sensor
    coeffs = get_calibration_coefficients(sensor)
    if coeffs === nothing
        @warn "No calibration coefficients found in sensor $(typeof(sensor)). H2O calibration will be skipped. Only LICOR sensors with calibration coefficients support H2O correction."
        return nothing
    end

    println("Using calibration coefficients from sensor: $(typeof(sensor))")

    # Get time dimensions and frequencies
    hf_time = dims(high_frequency_data, Ti)
    lf_time = dims(low_frequency_data, Ti)

    # Calculate frequencies (assuming regular sampling)
    freq_lf = lf_time[2] - lf_time[1]
    freq_hf = hf_time[2] - hf_time[1]
    n_lf = length(lf_time)
    n_hf_per_lf = Int(round(freq_lf / freq_hf))

    # Extract required variables
    temp_data = low_frequency_data[gas_analyzer.temp_var, :]
    rh_data = low_frequency_data[gas_analyzer.rh_var, :] * 100  # Convert to percentage
    h2o_var = gas_analyzer.h2o_variable
    pressure_var = gas_analyzer.pressure_var

    # Step 1: Resample high-frequency data to low-frequency
    h2o_lf_avg, pres_lf_avg = resample_to_low_frequency(high_frequency_data, h2o_var,
                                                        pressure_var, n_lf, n_hf_per_lf,
                                                        hf_time)

    # Step 2: Calculate reference absorptances
    li_a_raw_lf, rh_a_raw_lf = calculate_reference_absorptances(h2o_lf_avg, pres_lf_avg,
                                                                rh_data, temp_data, coeffs)

    # Step 3: Interpolate absorptances to high frequency
    li_a_raw_hf, rh_a_raw_hf = interpolate_to_high_frequency(li_a_raw_lf, rh_a_raw_lf,
                                                             n_hf_per_lf, hf_time, n_lf)

    # Step 4: Apply bias correction to high-frequency data
    h2o_data = high_frequency_data[h2o_var, :]
    pres_data = high_frequency_data[pressure_var, :] .* 1000  # Convert to Pa

    h2o_corrected = apply_bias_correction(h2o_data, pres_data, li_a_raw_hf, rh_a_raw_hf,
                                          coeffs)

    # Step 5: Replace the original H2O variable with corrected data in-place
    high_frequency_data.data[h2o_var] = h2o_corrected

    println("H2O calibration correction applied. Variable $h2o_var has been corrected in-place.")

    return nothing
end
