struct DotDatDirectory <: AbstractInput
    directory::String
end

function read_data(p::DotDatDirectory; kwargs...)
    fast_data = nothing # Read some shit
    slow_data = nothing
    return fast_data, slow_data
end
