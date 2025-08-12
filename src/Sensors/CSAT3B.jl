@kwdef struct CSAT3B <: AbstractSensor
    diag_sonic::Int = 0
    diag_csat::Int = 4096
end
needs_data_cols(sensor::CSAT3B) = (:diag_csat, :diag_sonic, :Ux, :Uy, :Uz, :Ts)
has_variables(sensor::CSAT3B) = (:Ux, :Uy, :Uz, :Ts)

function check_diagnostics!(sensor::CSAT3B, data::DimArray)
    # Now sonic and csat diagnostics both discard all Ux, Uy, Uz, Ts
    function discard_record!(i)
        data[i, :Ux] = data[i, :Uy] = data[i, :Uz] = data[i, :Ts] = convert(eltype(data), NaN)
    end
    diag_csat_col = view(data, Var(At(:diag_csat)))
    diag_sonic_col = view(data, Var(At(:diag_sonic)))
    for i in eachindex(diag_csat_col)
        if diag_csat_col[i] > sensor.diag_csat
            @debug "Discarding record $i due to csat diagnostic value $(diag_csat_col[i])"
            discard_record!(i)
            continue # already discarded the same, should be removed if it is changed
        end
        if diag_sonic_col[i] != sensor.diag_sonic
            @debug "Discarding record $i due to sonic diagnostic value $(diag_sonic_col[i])"
            discard_record!(i)
        end
    end
end
