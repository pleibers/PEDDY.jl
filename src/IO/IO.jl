# Output
export ICSVOutput
export NetCDFOutput
export MemoryOutput
export OutputSplitter

export LocationMetadata

export VariableMetadata
export get_default_metadata
export metadata_for

# Input
export read_data

export DotDatDirectory
export FileOptions

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

# include("icsv.jl")
include("netcdf.jl")
include("output_splitter.jl")
include("memory_output.jl")
