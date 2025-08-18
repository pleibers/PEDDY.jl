using CSV
using Glob
using Dates

"""
Options describing how to read a single .dat (CSV-like) file.

Fields:
- `header`: Header row index (0 means no header provided in file)
- `delimiter`: Field delimiter
- `comment`: Comment marker
- `timestamp_column`: Name of the timestamp column in the file
- `time_format`: Dates.DateFormat used to parse timestamps
- `nodata`: Numeric sentinel in files that should be replaced with `NaN`
"""
@kwdef struct FileOptions
    header::Int = 1
    delimiter::String = ","
    comment::String = "#"
    timestamp_column::Symbol = :TIMESTAMP
    # Default expects e.g. "2024-02-01 08:16:06.200"
    time_format::DateFormat = dateformat"yyyy-mm-dd HH:MM:SS.s"
    nodata = -9999.0
end

"""
Input that reads high-frequency (required) and optional low-frequency `.dat` files
from a directory using glob patterns.

Fields:
- `directory`: Root directory to search
- `high_frequency_file_glob`: Glob to find high-frequency files (e.g. "*fast*")
- `high_frequency_file_options`: `FileOptions` for the high-frequency files
- `low_frequency_file_glob`: Optional glob for low-frequency files
- `low_frequency_file_options`: Optional `FileOptions` for low-frequency files
"""
@kwdef struct DotDatDirectory <: AbstractInput
    directory::String
    high_frequency_file_glob::String = "*fast*"
    high_frequency_file_options::FileOptions = FileOptions()
    low_frequency_file_glob::Union{String,Nothing}=nothing
    low_frequency_file_options::Union{FileOptions,Nothing}=nothing
    nodata = -9999.0
end

"""
    read_data(input::DotDatDirectory, sensor::AbstractSensor; colnames=nothing, N=Float64)

Read high-frequency and optional low-frequency `.dat` files from `input.directory`.

Behavior:
- Selects only required columns for high-frequency data based on `needs_data_cols(sensor)` plus the timestamp column.
- Parses timestamps in-file using the provided `FileOptions.time_format`.
- Replaces `nodata` values with `NaN`.
- Returns `(high_frequency_data::DimArray, low_frequency_data::Union{DimArray,Nothing})`.

Keyword arguments:
- `colnames::Union{Nothing,Vector{Symbol}}`: Provide column names when files have no header (`header == 0`).
- `N::Type{<:Real}`: Element type for the returned data matrix (default `Float64`).
"""
function read_data(input::DotDatDirectory, sensor::AbstractSensor; colnames::Union{Nothing,Vector{Symbol}} = nothing, N::Type{R}=Float64) where {R<:Real}
    # --- Validate HF header/colnames contract ---
    if input.high_frequency_file_options.header == 0 && colnames === nothing
        throw(ArgumentError("Please provide either a header line, or a list of column names (kwarg: colnames) to use!"))
    end
    if input.high_frequency_file_options.header != 0 && colnames !== nothing
        @warn "Header line will be ignored, as column names are provided!"
    end

    # --- Resolve file lists ---
    hf_glob = ensure_dat_extension(input.high_frequency_file_glob)
    hf_files = glob(hf_glob, input.directory)

    lf_files = nothing
    if input.low_frequency_file_glob !== nothing
        lf_glob = ensure_dat_extension(input.low_frequency_file_glob)
        lf_files = glob(lf_glob, input.directory)
    end

    # --- Determine and validate required HF columns ---
    needed_cols = collect(needs_data_cols(sensor))
    hf_header = colnames === nothing ? input.high_frequency_file_options.header : colnames

    # --- Read HF files ---
    # Concrete container: specialize on first element type
    hf_data_arrays = nothing
    for path in hf_files
        # Selective CSV parsing: only needed columns + timestamp
        tscol = input.high_frequency_file_options.timestamp_column
        selected_cols = unique(vcat(needed_cols, [tscol]))
        types_map = Dict(tscol => DateTime)
        file = CSV.File(path;
            header=hf_header,
            delim=input.high_frequency_file_options.delimiter,
            comment=input.high_frequency_file_options.comment,
            select=selected_cols,
            types=types_map,
            dateformat=input.high_frequency_file_options.time_format,
        )
        check_colnames(file.names, needed_cols)
        timestamps = parse_timestamps(file, input.high_frequency_file_options)
        arr = build_dimarray_from_file(file, timestamps, needed_cols, N, input.nodata)
        # Initialize concrete container on first iteration
        if hf_data_arrays === nothing
            hf_data_arrays = Vector{typeof(arr)}()
        end
        push!(hf_data_arrays, arr)
    end
    high_frequency_data = vcat(hf_data_arrays...)

    # --- Read LF files (optional) ---
    low_frequency_data = nothing
    if lf_files !== nothing
        if input.low_frequency_file_options === nothing
            throw(ArgumentError("Please provide a FileOptions for the low frequency files"))
        end
        # Concrete container for LF as well
        lf_arrays = nothing
        for path in lf_files
            # In-CSV timestamp parsing for LF as well
            tscol_lf = input.low_frequency_file_options.timestamp_column
            types_map_lf = Dict(tscol_lf => DateTime)
            file = CSV.File(path;
                header=input.low_frequency_file_options.header,
                delim=input.low_frequency_file_options.delimiter,
                comment=input.low_frequency_file_options.comment,
                types=types_map_lf,
                dateformat=input.low_frequency_file_options.time_format,
            )
            timestamps = parse_timestamps(file, input.low_frequency_file_options)
            # Keep existing behavior: include all file columns
            variable_names = file.names
            arr = build_dimarray_from_file(file, timestamps, variable_names, N)
            if lf_arrays === nothing
                lf_arrays = Vector{typeof(arr)}()
            end
            push!(lf_arrays, arr)
        end
        low_frequency_data = vcat(lf_arrays...)
    end

    return high_frequency_data, low_frequency_data
end

"""
    check_colnames(data_cols::Vector{Symbol}, needed_cols::Vector{Symbol})

Validate that all `needed_cols` are present in `data_cols`. Throws `ArgumentError`
if a required column is missing.
"""
function check_colnames(data_cols::Vector{Symbol}, needed_cols::Vector{Symbol})
    if !all(x-> x in data_cols, needed_cols)
        throw(ArgumentError("Not all required columns are provided for sensor.\nRequires: $needed_cols\nFound: $data_cols"))            
    end
end

# -----------------------------------------------------------------------------
# Helper utilities (internal)
# -----------------------------------------------------------------------------

"""Ensure the glob pattern matches `.dat` files by appending the extension if missing."""
function ensure_dat_extension(glob_pattern::String)
    return occursin(".dat", glob_pattern) ? glob_pattern : glob_pattern * ".dat"
end

"""Parse the timestamp column of a CSV.File with the provided `FileOptions`.
Timestamps are parsed by CSV.jl directly using `types` and `dateformat`; this
function simply returns the typed column to keep call sites uniform.
"""
function parse_timestamps(file::CSV.File, opts::FileOptions)
    return file[opts.timestamp_column]
end

"""
Construct a `DimArray` from a CSV.File, given parsed timestamps and the list of
variable names to extract as columns.
"""
function build_dimarray_from_file(file::CSV.File, timestamps, variable_names::Vector{Symbol}, ::Type{N}, nodata::Real) where {N<:Real}
    n_times = length(timestamps)
    n_vars = length(variable_names)
    # Smarter sorting: only reorder if timestamps are not ordered
    ordered = issorted(timestamps)
    perm = ordered ? nothing : sortperm(timestamps)

    data_matrix = Matrix{N}(undef, n_times, n_vars)
    # Fill columns, reordering rows if needed
    if perm === nothing
        for col in variable_names
            data_matrix[:, findfirst(==(col), variable_names)] .= file[col]
        end
        dimarray = DimArray(data_matrix, (Ti(timestamps), Var(variable_names)))
    else
        for (j, col) in pairs(variable_names)
            data_matrix[:, j] .= @view(file[col][perm])
        end
        dimarray = DimArray(data_matrix, (Ti(timestamps[perm]), Var(variable_names)))
    end
    replace!(dimarray, nodata => NaN) # can be OOP if we use missing instead
    return dimarray
end