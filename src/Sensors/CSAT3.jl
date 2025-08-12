@kwdef struct CSAT3 <: AbstractSensor
    diag_sonic::Int = 64
    diag_csat::Int = 4096
end
needs_cols(sensor::CSAT3) = (:diag_sonic, :diag_csat, :Ux, :Uy, :Uz, :Ts)
has_variables(sensor::CSAT3) = (:Ux, :Uy, :Uz, :Ts)

function check_diagnostics!(sensor::CSAT3, data::DimArray)
    # Now sonic and csat diagnostics both discard all Ux, Uy, Uz, Ts
    function discard_record!(i, value, name)
        if value > getfield(sensor, name)
            @debug "Discarding record $i due to $name diagnostic value $value"
            data[i, :Ux] = data[i, :Uy] = data[i, :Uz] = data[i, :Ts] = convert(eltype(data), NaN)
            return true
        end
        return false
    end
    for i in eachindex(view(data, Var(At(:diag_csat))))
        if !discard_record!(i, data[i, :diag_csat], :diag_csat) # so we only call it once
            discard_record!(i, data[i, :diag_sonic], :diag_sonic)
        end
    end
end
