@kwdef struct IRGASON <: AbstractSensor
    diag_sonic::Int = 0
    diag_gas::Int = 0 
end

# Note: IRGASON sensors do not have H2O calibration coefficients.
# H2O calibration is specific to LICOR gas analyzers (LI-COR Inc.).

needs_data_cols(sensor::IRGASON) = (
    :diag_sonic, :diag_gas, :Ux, :Uy, :Uz, :Ts, :CO2, :H2O, :T, :P
)
has_variables(sensor::IRGASON) = (
    :Ux, :Uy, :Uz, :Ts, :CO2, :H2O, :T, :P
)

function check_diagnostics!(sensor::IRGASON, data::DimArray)
    # TODO: Is missing sonic diagnostics
    # TODO: Is missing gas diagnostics
    diag_gas_col = view(data, Var(At(:diag_gas)))
    diag_sonic_col = view(data, Var(At(:diag_sonic)))
    for i in eachindex(diag_gas_col)
        if diag_gas_col[i] > sensor.diag_gas
            @debug "Discarding record $i due to diagnostic value $(diag_gas_col[i])"
            data[Ti=i, Var=At(:H2O)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:CO2)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:T)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:P)] = convert(eltype(data), NaN)
        end
        if diag_sonic_col[i] > sensor.diag_sonic
            @debug "Discarding record $i due to sonic diagnostic value $(diag_sonic_col[i])"
            data[Ti=i, Var=At(:Ux)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uy)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uz)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Ts)] = convert(eltype(data), NaN)
        end
            
    end
end
