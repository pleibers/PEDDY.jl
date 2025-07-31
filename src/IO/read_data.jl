struct ReadData <: AbstractInput
    filename::String
end

function read_data(p::ReadData; kwargs...)
    data = nothing # Read some shit
    return data
end
