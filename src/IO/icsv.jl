using PYiCSV
try
    using PYiCSV
catch e
    @warn "Could not load PYiCSV, ICSVOutput will not be available"
end

struct ICSVOutput <: AbstractOutput
    base_filename::String
    location::LocationMetadata
    fields::Dict{Symbol,VariableMetadata} = DEFAULT_VARIABLE_METADATA
    field_delimiter::String = ","
end

# TODO: Currently only data is saved, were missing the timestamp, so extract timestamp index and append it to a dataframe

function write_data(out::ICSVOutput, high_frequency_data::DimArray, low_frequency_data::Union{Nothing,DimArray}; kwargs...)
    field_delimiter = out.field_delimiter
    location = Location(out.location.latitude, out.location.longitude, out.location.elevation)
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
    additional_metadata = Dict{"description"=>description}
    metadata = Metadata(field_delimiter, location; nodata, additional_metadata)
    field_metadata = create_field_metadata(out, data)
    fields = Fields(field_metadata)
    file = iCSV(metadata, fields, data.data)
    filename = base * suffix * ext
    PYiCSV.save(file, filename)
end

function create_field_metadata(out::ICSVOutput,data::DimArray)
    field_metadata = Dict{String, Vector{String}}("fields"=>Vector{String}(), "units"=>Vector{String}(), "long_names"=>Vector{String}(), "standard_names"=>Vector{String}(), "description"=>Vector{String}())
    var_dim = findfirst(x->typeof(x)<:Var,data.dims)
    for var in data.dims[var_dim] # Var shold be the second dimension
        var_metadata = get(out.fields, var, VariableMetadata(standard_name=String(var)))        
        push!(field_metadata["fields"], String(var))
        push!(field_metadata["units"], var_metadata.unit)
        push!(field_metadata["long_names"], var_metadata.long_name)
        push!(field_metadata["standard_names"], var_metadata.standard_name)
        push!(field_metadata["description"], var_metadata.description)
    end    
end