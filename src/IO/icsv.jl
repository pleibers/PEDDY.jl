using InteroperableCSV
using Dates

"""
    ICSVOutput(; base_filename, location, fields=DEFAULT_VARIABLE_METADATA,
                field_delimiter=",", nodata=-9999.0, other_metadata=Dict())

Output backend that writes data in the `.icsv` format using the `InteroperableCSV.jl` package.

Fields:
- `base_filename::String`: Base path without suffix; `_hf`/`_lf` and `.icsv` are appended.
- `location`: Site location metadata (accepts `LocationMetadata` or `InteroperableCSV.Loc`).
- `fields::Dict{Symbol,VariableMetadata}`: Per-variable metadata written to the Fields section.
- `field_delimiter::String`: Delimiter for the data section.
- `nodata::Float64`: Fill value used for NaN/missing.
- `other_metadata::Dict{Symbol,String}`: Additional key-value pairs for the MetaData section.

Writes one file for high-frequency data and, if provided, one for low-frequency data.
"""
@kwdef struct ICSVOutput <: AbstractOutput
    base_filename::String
    location::Union{Loc, LocationMetadata}
    fields::Dict{Symbol,VariableMetadata} = DEFAULT_VARIABLE_METADATA
    field_delimiter::String = ","
    nodata::Float64 = -9999.0
    other_metadata::Dict{Symbol,String} = Dict{Symbol,String}()
end

"""
    _to_loc(loc)

Convert supported location metadata types to `InteroperableCSV.Loc`.
"""
_to_loc(loc::Loc) = loc
function _to_loc(loc::LocationMetadata)
    # InteroperableCSV.Loc expects (x, y, z) where z can be `nothing`; map elevation to z.
    return Loc(loc.latitude, loc.longitude, loc.elevation)
end

"""
    write_data(out::ICSVOutput, hf::DimArray, lf::Union{Nothing,DimArray}; kwargs...)

Write `hf` (and optionally `lf`) to `.icsv` files with suffixes `_hf` and `_lf`.
Returns `nothing`.
"""
function write_data(out::ICSVOutput, high_frequency_data::DimArray, low_frequency_data::Union{Nothing,DimArray}; kwargs...)
    field_delimiter = out.field_delimiter
    base, ext = splitext(out.base_filename)
    if ext == ""
        ext = ".icsv"
    end
    # HF Data
    _save_icsv_dataset(base, ext, field_delimiter, out, high_frequency_data, "High frequency data", "_hf")
    # LF Data
    if !isnothing(low_frequency_data)
        _save_icsv_dataset(base, ext, field_delimiter, out, low_frequency_data, "Low frequency data", "_lf")
    end
end

"""
    _save_icsv_dataset(base, ext, field_delimiter, out, data, description, suffix)

Internal helper that assembles the iCSV sections and writes one dataset.
"""
function _save_icsv_dataset(base::AbstractString, ext::AbstractString,
                            field_delimiter::AbstractString, out::ICSVOutput, data::DimArray,
                            description::AbstractString, suffix::AbstractString)
    out.other_metadata[:description] = description
    geometry = Geometry(4326, _to_loc(out.location))
    metadata = MetaDataSection(;field_delimiter, geometry, nodata=out.nodata, out.other_metadata...)
    field_metadata = _create_field_metadata(out, data)
    fields = FieldsSection(;field_metadata...)
    replace!(data, NaN => out.nodata)

    # Build a column dictionary that includes the timestamp as the first field
    ddims = dims(data)
    time_dim = findfirst(x -> x isa Ti, ddims)
    var_dim = findfirst(x -> x isa Var, ddims)
    isnothing(time_dim) && error("ICSVOutput: time dimension (Ti) not found in data.dims")
    isnothing(var_dim) && error("ICSVOutput: variable dimension (Var) not found in data.dims")

    time_values = collect(ddims[time_dim])
    if !(eltype(time_values) <: Union{Date, DateTime})
        @warn "ICSVOutput: time dimension is not of type Date or DateTime"
    end

    columns = Dict{String, Any}()
    columns["timestamp"] = time_values
    for (j, var) in enumerate(ddims[var_dim])
        columns[String(var)] = @view data.data[:, j]
    end

    file = ICSVBase(metadata, fields, geometry, columns)
    filename = base * suffix * ext
    InteroperableCSV.write(file, filename)
end

"""
    _create_field_metadata(out, data)

Builds vectors for the Fields section including the timestamp column.
"""
function _create_field_metadata(out::ICSVOutput,data::DimArray)
    field_metadata = Dict{Symbol, Vector{String}}(:fields=>Vector{String}(), :units=>Vector{String}(), :long_names=>Vector{String}(), :standard_names=>Vector{String}(), :description=>Vector{String}())
    ddims = dims(data)
    var_dim = findfirst(x -> x isa Var, ddims)
    isnothing(var_dim) && error("ICSVOutput: variable dimension (Var) not found in data.dims")
    # Timestamp is the first column
    time_metadata = get(out.fields, :timestamp, VariableMetadata(standard_name="timestamp"))
    push!(field_metadata[:fields], "timestamp")
    push!(field_metadata[:units], time_metadata.unit)
    push!(field_metadata[:long_names], time_metadata.long_name)
    push!(field_metadata[:standard_names], time_metadata.standard_name)
    push!(field_metadata[:description], time_metadata.description)
    for var in ddims[var_dim] # Var should be the second dimension
        var_metadata = get(out.fields, var, VariableMetadata(standard_name=String(var)))        
        push!(field_metadata[:fields], String(var))
        push!(field_metadata[:units], var_metadata.unit)
        push!(field_metadata[:long_names], var_metadata.long_name)
        push!(field_metadata[:standard_names], var_metadata.standard_name)
        push!(field_metadata[:description], var_metadata.description)
    end
    return field_metadata
end