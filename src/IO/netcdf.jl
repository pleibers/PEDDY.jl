struct NetCDF <: AbstractOutput
    filename::String
end

function write_data(p::NetCDF, data; kwargs...)
    # Write some shit
end