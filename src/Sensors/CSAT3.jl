@kwdef struct CSAT3 <: AbstractSensor
    diag_sonic::Int = 63
end
needs_data_cols(sensor::CSAT3) = (:diag_sonic, :Ux, :Uy, :Uz, :Ts)
has_variables(sensor::CSAT3) = (:diag_sonic, :Ux, :Uy, :Uz, :Ts)

function check_diagnostics!(sensor::CSAT3, data::DimArray)
    # Now sonic and csat diagnostics both discard all Ux, Uy, Uz, Ts
    diag_sonic_col = view(data, Var(At(:diag_sonic)))
    for i in eachindex(diag_sonic_col)
        if diag_sonic_col[i] > sensor.diag_sonic
            @debug "Discarding record $i due to sonic diagnostic value $(diag_sonic_col[i])"
            data[Ti=i, Var=At(:Ux)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uy)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uz)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Ts)] = convert(eltype(data), NaN)
        end
    end
end