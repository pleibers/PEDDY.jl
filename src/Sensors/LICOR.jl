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
@kwdef struct H2OCalibrationCoefficients
    A::Float64
    B::Float64
    C::Float64
    H2O_Zero::Float64
    H20_Span::Float64
end

@kwdef struct LICOR <: AbstractSensor 
    diag_sonic::Int = 0
    diag_gas::Int = 240
    # H2O calibration coefficients (optional)
    calibration_coefficients::Union{Nothing, H2OCalibrationCoefficients} = nothing
end

# Predefined constructors with calibration coefficients based on sensor_info.py

"""
    LICOR(sensor_name::String, year=nothing; kwargs...)

Create LICOR sensor with predefined calibration coefficients.
Supported sensor_name values: "SFC", "LOWER", "UPPER", "BOTTOM".
"""
function default_calibration_coefficients(sensor_name::String, year=nothing; kwargs...)
    coeffs = nothing
    
    if sensor_name == "SFC" && (year == 2024 || year == 2025)
        coeffs = H2OCalibrationCoefficients(
            A = 4.82004E3,
            B = 3.79290E6,
            C = -1.15477E8,
            H2O_Zero = 0.7087,
            H20_Span = 0.9885
        )
    elseif sensor_name == "LOWER"
        coeffs = H2OCalibrationCoefficients(
            A = 5.49957E3,
            B = 4.00024E6,
            C = -1.11280E8,
            H2O_Zero = 0.8164,
            H20_Span = 1.0103
        )
    elseif sensor_name == "UPPER"
        coeffs = H2OCalibrationCoefficients(
            A = 4.76480E3,
            B = 3.84869E6,
            C = -1.15477E8,  # Corrected from original typo
            H2O_Zero = 0.7311,
            H20_Span = 0.9883
        )
    elseif sensor_name == "BOTTOM"
        # BOTTOM sensor has no calibration coefficients in Python version
        coeffs = nothing
    else
        @warn "Unknown sensor name: $sensor_name. No calibration coefficients will be set."
        coeffs = nothing
    end
    
    return coeffs
end

needs_cols(sensor::LICOR) = (:diag_sonic, :diag_gas, :Ux, :Uy, :Uz, :Ts, :CO2, :H2O, :T, :P)
has_variables(sensor::LICOR) = (:Ux, :Uy, :Uz, :Ts, :CO2, :H2O, :T, :P)

function check_diagnostics!(sensor::LICOR, data::DimArray)
    # TODO: Is missing sonic diagnostics
    diag_gas_col = view(data, Var(At(:diag_gas)))
    nan = convert(eltype(diag_gas_col), NaN)
    for i in eachindex(diag_gas_col)
        if diag_gas_col[i] > sensor.diag_gas
            @debug "Discarding record $i due to diagnostic value $(diag_gas_col[i])"
            data[i, :H2O] = nan
            data[i, :P] = nan
        end
    end
end
