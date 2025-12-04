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

function check_diagnostics!(sensor::IRGASON, data::DimArray; kwargs...)
    # TODO: Is missing sonic diagnostics
    # TODO: Is missing gas diagnostics
    diag_gas_col = view(data, Var(At(:diag_gas)))
    diag_sonic_col = view(data, Var(At(:diag_sonic)))
    logger = get(kwargs, :logger, nothing)
    gas_indices = logger === nothing ? nothing : Int[]
    sonic_indices = logger === nothing ? nothing : Int[]
    for i in eachindex(diag_gas_col)
        if diag_gas_col[i] > sensor.diag_gas
            @debug "Discarding record $i due to diagnostic value $(diag_gas_col[i])"
            logger === nothing || push!(gas_indices, i)
            data[Ti=i, Var=At(:H2O)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:CO2)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:T)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:P)] = convert(eltype(data), NaN)
        end
        if diag_sonic_col[i] > sensor.diag_sonic
            @debug "Discarding record $i due to sonic diagnostic value $(diag_sonic_col[i])"
            logger === nothing || push!(sonic_indices, i)
            data[Ti=i, Var=At(:Ux)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uy)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Uz)] = convert(eltype(data), NaN)
            data[Ti=i, Var=At(:Ts)] = convert(eltype(data), NaN)
        end
            
    end
    if logger !== nothing
        times = collect(dims(data, Ti))
        if gas_indices !== nothing && !isempty(gas_indices)
            log_index_runs!(logger, :quality_control, :diagnostic_flag, :diag_gas, times, gas_indices;
                            include_run_length=true, threshold=sensor.diag_gas, affected_variables=[:H2O, :CO2, :T, :P])
        end
        if sonic_indices !== nothing && !isempty(sonic_indices)
            log_index_runs!(logger, :quality_control, :diagnostic_flag, :diag_sonic, times, sonic_indices;
                            include_run_length=true, threshold=sensor.diag_sonic, affected_variables=[:Ux, :Uy, :Uz, :Ts])
        end
    end
end
