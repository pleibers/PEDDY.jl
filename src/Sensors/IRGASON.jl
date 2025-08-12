@kwdef struct IRGASON <: AbstractSensor
    diag_sonic::Int = 0
    diag_gas::Int = 240 # There was no values
    diag_irgason::Int = 42
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
    diag_gas_col = view(data, Var(At(:diag_gas)))
    diag_sonic_col = view(data, Var(At(:diag_sonic)))
    diag_irgason_col = view(data, Var(At(:diag_irgason)))
    nan = convert(eltype(diag_gas_col), NaN)
    for i in eachindex(diag_gas_col)
        if diag_irgason_col[i] >= sensor.diag_irgason
            @debug "Discarding record $i due to diagnostic value $(diag_irgason_col[i])"
            data[i,:] .= nan
            continue
        end
        if diag_gas_col[i] > sensor.diag_gas
            @debug "Discarding record $i due to diagnostic value $(diag_gas_col[i])"
            data[i, :H2O] = nan
            data[i, :P] = nan
        end
        if diag_sonic_col[i] != sensor.diag_sonic
            @debug "Discarding record $i due to sonic diagnostic value $(diag_sonic_col[i])"
            data[i, :Ux] = data[i, :Uy] = data[i, :Uz] = data[i, :Ts] = nan # is this what should be discarded?
        end
    end
end
