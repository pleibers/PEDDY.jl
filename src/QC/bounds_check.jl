struct Limit{N<:Real}
    min::N
    max::N
end

struct PhysicsBoundsCheck{N<:Real,LIM<:Limit{N}} <: AbstractQC
    Ux::LIM
    Uy::LIM
    Uz::LIM
    Ts::LIM
    CO2::LIM
    H2O::LIM
    Ta::LIM
    P::LIM
end

function PhysicsBoundsCheck(; number_type=Float64, kwargs...)
    defaults = default_physical_limits(; number_type=number_type)
    # Merge user-provided kwargs with defaults
    merged_limits = copy(defaults)
    for (key, value) in kwargs
        if !(key in keys(defaults))
            println("Valid keys: $(keys(defaults))")
            throw(ArgumentError("Invalid key: $key"))
        end
        merged_limits[key] = value
    end
    # Construct directly using the merged limits
    return PhysicsBoundsCheck(merged_limits[:Ux],
                              merged_limits[:Uy],
                              merged_limits[:Uz],
                              merged_limits[:Ts],
                              merged_limits[:CO2],
                              merged_limits[:H2O],
                              merged_limits[:Ta],
                              merged_limits[:P])
end

function default_physical_limits(; number_type::Type{N}) where {N<:Real} # FAQ: Is this Sensor dependent?
    return limits = Dict{Symbol,Limit{N}}(:Ux => Limit(N(-100), N(100)),
                                          :Uy => Limit(N(-100), N(100)),
                                          :Uz => Limit(N(-50), N(50)),
                                          :Ts => Limit(N(-50), N(50)),
                                          :CO2 => Limit(N(0), typemax(N)),
                                          :H2O => Limit(N(0), typemax(N)),
                                          :Ta => Limit(N(-50), N(50)),
                                          :P => Limit(N(0), typemax(N)))
end

function check_bounds!(variable::Symbol, data::DimArray,
                       physical_limits::PhysicsBoundsCheck{N,LIM}) where {N<:Real,
                                                                          LIM<:Limit{N}}
    col = view(data, Var(At(variable)))
    limit = getfield(physical_limits, variable)

    n_discarded = 0
    for i in eachindex(col)
        # We only check finite values, NaN and Inf are ignored
        @inbounds if isfinite(col[i]) && (col[i] < limit.min || col[i] > limit.max)
            n_discarded += 1
            col[i] = convert(N, NaN)
        end
    end

    if n_discarded > 0
        @debug "Plausibility limits for '$variable': Discarding $n_discarded records outside of [$(limit.min), $(limit.max)] range."
    end
end

function control_physical_limits!(qc::PhysicsBoundsCheck, data::DimArray, sensor::S;
                                  kwargs...) where {S<:AbstractSensor}
    for variable in has_variables(sensor)
        check_bounds!(variable, data, qc)
    end
end

function quality_control!(qc::PhysicsBoundsCheck, high_frequency_data::DimArray,
                          low_frequency_data, sensor::S;
                          kwargs...) where {S<:AbstractSensor}
    check_diagnostics!(sensor, high_frequency_data)
    return control_physical_limits!(qc, high_frequency_data, sensor; kwargs...)
end
