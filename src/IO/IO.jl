"""
Public exports for input/output and metadata utilities.

This file defines common IO abstractions and re-exports concrete input/output
implementations included from the `src/IO/` directory.
"""

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
export AbstractInput

export DotDatDirectory
export FileOptions

"""
    AbstractInput

Abstract supertype for data inputs. Implementations must provide a
`read_data(input::AbstractInput, sensor::AbstractSensor; kwargs...)` method
that returns a tuple `(high_frequency_data, low_frequency_data)` where the
second element may be `nothing` if not available.
"""
abstract type AbstractInput end

"""
    read_data(input::AbstractInput, sensor::AbstractSensor; kwargs...) -> (hf, lf)

Generic interface for reading data for the pipeline. Returns a high-frequency
`DimArray` and optionally a low-frequency `DimArray` (or `nothing`). Concrete
inputs such as `DotDatDirectory` implement this method.
"""
function read_data end

include("dat_directory.jl")

# Output
include("variable_metadata.jl")

"""
    LocationMetadata(; latitude, longitude, elevation=nothing, instrument_height=nothing)

Geospatial metadata for a site/instrument location.

Fields:
- `latitude::Float64`
- `longitude::Float64`
- `elevation::Union{Float64,Nothing}`: meters above ground (optional)
- `instrument_height::Union{Float64,Nothing}`: meters above ground (optional)
"""
@kwdef struct LocationMetadata
    latitude::Float64
    longitude::Float64
    elevation::Union{Float64, Nothing} = nothing
    instrument_height::Union{Float64, Nothing} = nothing
end

include("icsv.jl")
include("netcdf.jl")
include("output_splitter.jl")
include("memory_output.jl")
