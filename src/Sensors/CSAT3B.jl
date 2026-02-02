"""
     CSAT3B(; diag_sonic=0)

 Campbell Scientific CSAT3B sonic anemometer.

 The `diag_sonic` threshold controls which diagnostic values are considered invalid.
 During `check_diagnostics!`, records exceeding this threshold are set to `NaN` for
 wind components and sonic temperature.
 """
@kwdef struct CSAT3B <: AbstractSensor
    diag_sonic::Int = 0
end
needs_data_cols(sensor::CSAT3B) = (:diag_sonic, :Ux, :Uy, :Uz, :Ts)
has_variables(sensor::CSAT3B) = (:diag_sonic, :Ux, :Uy, :Uz, :Ts)

function check_diagnostics!(sensor::CSAT3B, data::DimArray; kwargs...)
    # Now sonic and csat diagnostics both discard all Ux, Uy, Uz, Ts
    diag_sonic_col = view(data, Var(At(:diag_sonic)))
    logger = get(kwargs, :logger, nothing)
    flagged = logger === nothing ? nothing : Int[]
    for i in eachindex(diag_sonic_col)
        if diag_sonic_col[i] > sensor.diag_sonic
            @debug "Discarding record $i due to sonic diagnostic value $(diag_sonic_col[i])"
            logger === nothing || push!(flagged, i)
            data[Ti=i, Var=At(:Ux)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uy)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uz)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Ts)] = convert(eltype(data), NaN)
        end
    end
    if logger !== nothing && flagged !== nothing && !isempty(flagged)
        times = collect(dims(data, Ti))
        log_index_runs!(logger, :quality_control, :diagnostic_flag, :diag_sonic, times, flagged;
                        include_run_length=true, threshold=sensor.diag_sonic, affected_variables=[:Ux, :Uy, :Uz, :Ts])
    end
end
