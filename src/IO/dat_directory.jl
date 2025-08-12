struct DotDatDirectory <: AbstractInput
    directory::String
end

function read_data(p::DotDatDirectory; kwargs...)
    data = nothing # Read some shit
    return data
end
