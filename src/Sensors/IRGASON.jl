@kwdef struct IRGASON <: AbstractSensor
    diag_sonic::Int = 0
    diag_gas::Int = 240 # There was no values
    # H2O calibration coefficients (optional, but IRGASON sensors don't have them)
    calibration_coefficients::Union{Nothing,H2OCalibrationCoefficients} = nothing
end

# Note: IRGASON sensors do not have H2O calibration coefficients.
# H2O calibration is specific to LICOR gas analyzers (LI-COR Inc.).

function needs_cols(sensor::IRGASON)
    return (:diag_sonic, :diag_gas, :Ux, :Uy, :Uz, :Ts, :CO2, :H2O, :T, :P)
end
has_variables(sensor::IRGASON) = (:Ux, :Uy, :Uz, :Ts, :CO2, :H2O, :T, :P)

function check_diagnostics!(sensor::IRGASON, data::DimArray)
    # TODO: Is missing sonic diagnostics
    # TODO: Is missing gas diagnostics
end
