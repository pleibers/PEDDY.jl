@kwdef struct ICSVOutput <: AbstractOutput
    base_filename::String
    location::LocationMetadata
    fields::Dict{Symbol,VariableMetadata} = DEFAULT_VARIABLE_METADATA
    field_delimiter::String = ","
end

function write_data(out::ICSVOutput, high_frequency_data::DimArray, low_frequency_data::Union{Nothing,DimArray}; kwargs...)
    field_delimiter = out.field_delimiter
    location = PYiCSV.Location(out.location.latitude, out.location.longitude, out.location.elevation)
    nodata = -9999.0
    base, ext = splitext(out.base_filename)
    if ext == ""
        ext = ".icsv"
    end
    # HF Data
    _save_icsv_dataset(base, ext, field_delimiter, location, nodata, out, high_frequency_data, "High frequency data", "_hf")
    # LF Data
    if !isnothing(low_frequency_data)
        _save_icsv_dataset(base, ext, field_delimiter, location, nodata, out, low_frequency_data, "Low frequency data", "_lf")
    end
end

function _save_icsv_dataset(base::AbstractString, ext::AbstractString,
                            field_delimiter::AbstractString, location,
                            nodata, out::ICSVOutput, data::DimArray,
                            description::AbstractString, suffix::AbstractString)
    additional_metadata = Dict("description" => description)
    metadata = Metadata(field_delimiter, location; nodata, additional_metadata)
    field_metadata = _create_field_metadata(out, data)
    fields = Fields(field_metadata)
    # Convert DimArray to a dictionary of column vectors. Allow heterogeneous column types.
    data_dict = Dict{String, AbstractVector}()
    ddims = dims(data)
    time_dim_idx = findfirst(d -> d isa Ti, ddims)
    var_dim_idx = findfirst(d -> d isa Var, ddims)
    isnothing(time_dim_idx) && error("ICSVOutput: time dimension (Ti) not found in data.dims")
    isnothing(var_dim_idx) && error("ICSVOutput: variable dimension (Var) not found in data.dims")
    # Timestamp handling
    time_labels = collect(ddims[time_dim_idx])
    if !(eltype(time_labels) <: Union{Date, DateTime})
        @warn "ICSVOutput: time dimension is not of type Date or DateTime, might cause troubles when writing data"
    end
    # First column: timestamp
    data_dict["timestamp"] = time_labels
    # Variables
    for var in ddims[var_dim_idx]
        # keep missing values as-is; PYiCSV will use nodata metadata if needed
        data_dict[String(var)] = collect(data[Var=At(var)])
    end
    file = iCSV(metadata, fields, data_dict)
    filename = base * suffix * ext
    PYiCSV.save(filename, file)
end

function _create_field_metadata(out::ICSVOutput,data::DimArray)
    field_metadata = Dict{String, Vector{String}}("fields"=>Vector{String}(), "units"=>Vector{String}(), "long_names"=>Vector{String}(), "standard_names"=>Vector{String}(), "description"=>Vector{String}())
    ddims = dims(data)
    var_dim = findfirst(x -> x isa Var, ddims)
    isnothing(var_dim) && error("ICSVOutput: variable dimension (Var) not found in data.dims")
    # Timestamp is the first column
    time_metadata = get(out.fields, :timestamp, VariableMetadata(standard_name="timestamp"))
    push!(field_metadata["fields"], "timestamp")
    push!(field_metadata["units"], time_metadata.unit)
    push!(field_metadata["long_names"], time_metadata.long_name)
    push!(field_metadata["standard_names"], time_metadata.standard_name)
    push!(field_metadata["description"], time_metadata.description)
    for var in ddims[var_dim] # Var should be the second dimension
        var_metadata = get(out.fields, var, VariableMetadata(standard_name=String(var)))        
        push!(field_metadata["fields"], String(var))
        push!(field_metadata["units"], var_metadata.unit)
        push!(field_metadata["long_names"], var_metadata.long_name)
        push!(field_metadata["standard_names"], var_metadata.standard_name)
        push!(field_metadata["description"], var_metadata.description)
    end
    return field_metadata
end