struct Limit{N <: Real}
    min::N
    max::N
end

struct PhysicsBoundsCheck{N <: Real, LIM <: Limit{N}} <: AbstractQC
    Ux::LIM
    Uy::LIM
    Uz::LIM
    Ts::LIM
    CO2::LIM
    H2O::LIM
    Ta::LIM
    P::LIM
end

function PhysicsBoundsCheck(;number_type=Float64, kwargs...)
    defaults = default_physical_limits(number_type=number_type)
    for (key, value) in kwargs
        if !(key in keys(defaults))
            println("Valid keys: $(keys(defaults))")
            throw(ArgumentError("Invalid key: $key"))
        end
    end
    return PhysicsBoundsCheck(;defaults...)
end

function default_physical_limits(;number_type::Type{N}) where N <: Real # FAQ: Is this Sensor dependent?
    limits = Dict{Symbol, Limit{N}}(
        :Ux => Limit(-100, 100),
        :Uy => Limit(-100, 100),
        :Uz => Limit(-50, 50),
        :Ts => Limit(-50, 50),
        :CO2 => Limit(0, typemax(N)),
        :H2O => Limit(0, typemax(N)),
        :Ta => Limit(-50, 50),
        :P => Limit(0, typemax(N))
    )
end

function check_bounds!(variable::Symbol, data::DimArray, physical_limits::PhysicsBoundsCheck{N, LIM}) where {N <: Real, LIM <: Limit{N}}
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

function control_physical_limits!(qc::PhysicsBoundsCheck, data::DimArray, sensor::S; kwargs...) where S <: AbstractSensor
    for variable in has_variables(sensor)
        check_bounds!(variable, data, qc)
    end
end

function quality_control!(qc::PhysicsBoundsCheck, high_frequency_data::DimArray, low_frequency_data::DimArray, sensor::S; kwargs...) where S <: AbstractSensor
    check_diagnostics!(sensor, high_frequency_data)
    control_physical_limits!(qc, high_frequency_data, sensor; kwargs...)
end