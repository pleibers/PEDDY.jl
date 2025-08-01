@kwdef struct CSAT3 <: AbstractSensor 
    diag_sonic::Int = 64
    diag::Int = 4096
end
needs_cols(sensor::CSAT3) = (:diag, :Ux, :Uy, :Uz, :Ts)
has_variables(sensor::CSAT3) = (:Ux, :Uy, :Uz, :Ts)

function check_diagnostics!(sensor::CSAT3, data::DimArray)
    # TODO: Is missing sonic diagnostics
    diag_col = view(data, Var(At(:diag)))
    nan = convert(eltype(diag_col), NaN)
    for i in eachindex(diag_col)
        if diag_col[i] > sensor.diag
            @debug "Discarding record $i due to diagnostic value $(diag_col[i])"
            data[i, :Ux] = nan
            data[i, :Uy] = nan
            data[i, :Uz] = nan
            data[i, :Ts] = nan
        end
    end
end