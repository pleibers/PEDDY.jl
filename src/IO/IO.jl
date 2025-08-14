# Output
export ICSVOutput
export NetCDFOutput
export MemoryOutput

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

PYiCSV_loaded::Ref{Bool} = Ref(false)

try
    using PYiCSV
    PYiCSV.install_dependencies()
    PYiCSV_loaded[] = true
catch e
    @warn "Could not load PYiCSV, ICSVOutput will not be available"
end

if PYiCSV_loaded[]
    include("icsv.jl")
end
include("netcdf.jl")
include("memory_output.jl")
