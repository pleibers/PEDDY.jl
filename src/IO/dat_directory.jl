using CSV
using Glob

@kwdef struct DotDatDirectory <: AbstractInput
    directory::String
    high_frequency_file_glob::String = "*fast*"
    low_frequency_file_glob::Union{String,Nothing}=nothing
    delimiter::String = ","
    header::Int = 1
    timestamp_column::Symbol = :TIMESTAMP
    time_format::DateFormat = ISODateTimeFormat
end

function read_data(input::DotDatDirectory, sensor::AbstractSensor;colnames::Union{Nothing,Vector{Symbol}} = nothing, N::Type{R}=Float64) where {R<:Real}
    if header == 0 && colnames === nothing
        throw(ArgumentError("Please provide either a header line, or a List of column names (kwarg: colnames) to use!"))
    end
    if header != 0 && colnames !== nothing
        @warn "Header Line will be ignored, as column names are provided!"
    end
    has_ext = occursin(".dat", input.high_frequency_file_glob)
    hf_glob = has_ext ? input.high_frequency_file_glob : input.high_frequency_file_glob * ".dat"
    hf_data_files = glob(hf_glob, input.directory)
    
    lf_data_files = nothing
    if input.low_frequency_file_glob !== nothing
        has_ext = occursin(".dat", input.low_frequency_file_glob)
        lf_glob = has_ext ? input.low_frequency_file_glob : input.low_frequency_file_glob * ".dat"
        lf_data_files = glob(lf_glob, input.directory)
    end

    needed_cols = collect(needs_data_cols(sensor))
    n_vars = length(needed_cols)
    if colnames !== nothing
        if !all(x-> x in colnames, needed_cols)
            throw(ArgumentError("Not all required columns are provided for sensor: $senosr.\nRequires: $needed_cols"))            
        end
    end
    hf_data = DimArray[]
    # High Frequency files
    for file_name in hf_data_files
        file = CSV.File(file_name)
        # Check if all necessary cols are there
        timestamps = file[input.timestamp_column]
        # Transform strings to Dates
        timestamps = Date.(timestamps, Ref(input.time_format))
        # Preallocate the DimArray
        dummy_data = Matrix{N}(undef,length(timestamps), n_vars)
        data = DimArray(dummy_data, (Ti(timestamps), Var(needed_cols)))
        # set the data
    end

    return fast_data, slow_data
end
