export ICSVOutput
export NetCDFOutput
export MemoryOutput

#Input
abstract type AbstractInput end
function read_data end
include("dat_directory.jl")

# Output
include("variable_metadata.jl")

@kwdef struct LocationMetadata
    latitude::Float64
    longitude::Float64
    elevation::Union{Float64, Nothing} = nothing
    instrument_height::Union{Float64, Nothing} = nothing
end

include("icsv.jl")
include("netcdf.jl")
include("memory_output.jl")
