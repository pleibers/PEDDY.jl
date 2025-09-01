export H2OCalibrationCoefficients

"""
    H2OCalibrationCoefficients

Calibration coefficients for H2O gas analyzer correction.

Fields:
- `A`: Linear coefficient
- `B`: Quadratic coefficient  
- `C`: Cubic coefficient
- `H2O_Zero`: Zero offset
- `H20_Span`: Span coefficient
"""
@kwdef struct H2OCalibrationCoefficients{N<:Real}
    A::N
    B::N
    C::N
    H2O_Zero::N
    H20_Span::N
end

@kwdef struct LICOR{N<:Real, COEFF <: Union{Nothing,H2OCalibrationCoefficients{N}}} <: AbstractSensor
    number_type::Type{N} = Float64 # needed for calls where COEFF = Nothing
    diag_sonic::Int = 0
    diag_gas::Int = 240
    # H2O calibration coefficients (optional)
    calibration_coefficients::COEFF = nothing
end

# Predefined constructors with calibration coefficients based on sensor_info.py

"""
    LICOR(sensor_name::String, year=nothing; kwargs...)

Create LICOR sensor with predefined calibration coefficients.
Supported sensor_name values: "SFC", "LOWER", "UPPER", "BOTTOM".
"""
function default_calibration_coefficients(sensor_name::String="", year=nothing; number_type=Float64)
    coeffs = nothing

    if sensor_name == "SFC" && (year == 2024 || year == 2025)
        coeffs = H2OCalibrationCoefficients{number_type}(; A=4.82004E3,
                                            B=3.79290E6,
                                            C=-1.15477E8,
                                            H2O_Zero=0.7087,
                                            H20_Span=0.9885)
    elseif sensor_name == "LOWER"
        coeffs = H2OCalibrationCoefficients{number_type}(; A=5.49957E3,
                                            B=4.00024E6,
                                            C=-1.11280E8,
                                            H2O_Zero=0.8164,
                                            H20_Span=1.0103)
    elseif sensor_name == "UPPER"
        coeffs = H2OCalibrationCoefficients{number_type}(; A=4.76480E3,
                                            B=3.84869E6,
                                            C=-1.15477E8,  # Corrected from original typo
                                            H2O_Zero=0.7311,
                                            H20_Span=0.9883)
    elseif sensor_name == "BOTTOM"
        # BOTTOM sensor has no calibration coefficients in Python version
        coeffs = nothing
    else
        @warn "Unknown sensor name: $sensor_name. No calibration coefficients will be set."
        coeffs = nothing
    end

    return coeffs
end

needs_data_cols(sensor::LICOR) = (:diag_sonic, :diag_gas, :Ux, :Uy, :Uz, :Ts, :CO2, :H2O, :T, :P)
has_variables(sensor::LICOR) = (:Ux, :Uy, :Uz, :Ts, :CO2, :H2O, :T, :P)

function check_diagnostics!(sensor::LICOR, data::DimArray)
    # TODO: Is missing sonic diagnostics
    diag_gas_col = view(data, Var(At(:diag_gas)))
    diag_sonic_col = view(data, Var(At(:diag_sonic)))
    nan = convert(eltype(diag_gas_col), NaN)
    for i in eachindex(diag_gas_col)
        if diag_gas_col[i] > sensor.diag_gas
            @debug "Discarding record $i due to diagnostic value $(diag_gas_col[i])"
            data[Ti=i, Var=At(:H2O)] = nan
            data[Ti=i, Var=At(:P)] = nan
        end
        if diag_sonic_col[i] != sensor.diag_sonic
            @debug "Discarding record $i due to sonic diagnostic value $(diag_sonic_col[i])"
            data[Ti=i, Var=At(:Ux)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uy)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uz)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Ts)] = convert(eltype(data), NaN)
        end
    end
end
