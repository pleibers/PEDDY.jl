@kwdef struct LICOR <: AbstractSensor 
    diag_sonic::Int = 0
    diag_gas::Int = 240
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
