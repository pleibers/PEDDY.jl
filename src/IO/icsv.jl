struct ICSV <: AbstractOutput
    filename::String
end

function write_data(p::ICSV, data; kwargs...)
    # Write some shit
end
