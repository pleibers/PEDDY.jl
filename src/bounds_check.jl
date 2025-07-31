struct Limit{N <: Real}
    min::N
    max::N
end

struct BoundsCheck{PL <: NamedTuple, DS <: Real, DG <: Real, CS <: Real, HS <: Real} <: AbstractLimitCheck
    physical_limits::PL
    diag_sonic::DS # so these can be anything
    diag_gas::DG # so these can be anything
    CO2_signal::CS# so these can be anything
    H2O_signal::HS# so these can be anything
    
    function BoundsCheck(physical_limits::Dict{Symbol, Limit{N}}; diag_sonic = nothing, diag_gas = nothing, CO2_signal = nothing, H2O_signal = nothing) where N <: Real
        limits = NamedTuple{keys(physical_limits)}(values(physical_limits))
        return new{typeof(limits), typeof(diag_sonic), typeof(diag_gas), typeof(CO2_signal), typeof(H2O_signal)}(limits, diag_sonic, diag_gas, CO2_signal, H2O_signal)
    end
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

function control_physical_limits!(bounds_check::BoundsCheck, data; kwargs...)
    # TODO: Implement this
end