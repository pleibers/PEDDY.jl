@kwdef struct NetCDFOutput <: AbstractOutput
    base_filename::String
    location::LocationMetadata
    fields::Dict{Symbol,VariableMetadata} = DEFAULT_VARIABLE_METADATA
    fill_value::Float64 = -9999.0
end

# Lazy loader for NCDatasets to avoid hard dependency at module load time
function _ncd()
    # If already available in this module, return it
    if isdefined(@__MODULE__, :NCDatasets)
        return getfield(@__MODULE__, :NCDatasets)
    end
    # Try to import at module scope via eval
    try
        @eval import NCDatasets
        return getfield(@__MODULE__, :NCDatasets)
    catch e
        error("NCDatasets not available: $(sprint(showerror, e))")
    end
end

function write_data(out::NetCDFOutput, high_frequency_data::DimArray, low_frequency_data::Union{Nothing,DimArray}; kwargs...)
    # Load NCDatasets lazily to avoid module-load-time dependency issues
    ncd = _ncd()
    base, ext = splitext(out.base_filename)
    if ext == ""
        ext = ".nc"
    end
    # High frequency
    _save_netcdf_dataset(base * "_hf" * ext, out, high_frequency_data; title="High frequency data")
    # Low frequency (optional)
    if !isnothing(low_frequency_data)
        _save_netcdf_dataset(base * "_lf" * ext, out, low_frequency_data; title="Low frequency data")
    end
    return nothing
end

function _save_netcdf_dataset(path::AbstractString, out::NetCDFOutput, data::DimArray; title::AbstractString)
    ddims = dims(data)
    time_dim_idx = findfirst(d -> d isa Ti, ddims)
    var_dim_idx = findfirst(d -> d isa Var, ddims)
    isnothing(time_dim_idx) && error("NetCDFOutput: time dimension (Ti) not found in data.dims")
    isnothing(var_dim_idx) && error("NetCDFOutput: variable dimension (Var) not found in data.dims")

    time_labels = collect(ddims[time_dim_idx])
    time_values, time_units, calendar = _prepare_time_values(time_labels)

    # Create dataset
    ncd = _ncd()
    ds = ncd.NCDataset(path, "c"; attrib = Dict(
        "title" => String(title),
        "Conventions" => "CF-1.6",
        "history" => string("created on ", Dates.format(now(), dateformat"yyyy-mm-ddTHH:MM:SS")),
        "geospatial_lat_min" => out.location.latitude,
        "geospatial_lat_max" => out.location.latitude,
        "geospatial_lon_min" => out.location.longitude,
        "geospatial_lon_max" => out.location.longitude,
        "geospatial_vertical_min" => something(out.location.elevation, NaN),
        "geospatial_vertical_max" => something(out.location.elevation, NaN),
    ))
    try
        # Dimensions
        ncd.defDim(ds, "time", length(time_values))

        # Coordinate variables (scalar coords allowed by CF)
        lat = ncd.defVar(ds, "latitude", Float64, (); attrib = Dict(
            "standard_name" => "latitude",
            "long_name" => "latitude",
            "units" => "degrees_north",
        ))
        lon = ncd.defVar(ds, "longitude", Float64, (); attrib = Dict(
            "standard_name" => "longitude",
            "long_name" => "longitude",
            "units" => "degrees_east",
        ))
        if out.location.elevation !== nothing
            height = ncd.defVar(ds, "height", Float64, (); attrib = Dict(
                "standard_name" => "height",
                "long_name" => "instrument height above ground",
                "units" => "m",
                "positive" => "up",
            ))
            height[] = out.location.elevation
        end
        lat[] = out.location.latitude
        lon[] = out.location.longitude

        # Time coordinate variable
        time = ncd.defVar(ds, "time", Float64, ("time",); attrib = Dict(
            "standard_name" => "time",
            "long_name" => "time",
            "units" => time_units,
            "calendar" => calendar,
        ))
        time[:] = time_values

        # Data variables: one variable per entry of Var dimension
        for var in ddims[var_dim_idx]
            name = String(var)
            vm = get(out.fields, var, VariableMetadata(standard_name=name))
            # Ensure Float64 storage and apply fill value for missings
            vec = collect(data[Var=At(var)])
            vals = Vector{Float64}(undef, length(vec))
            @inbounds for i in eachindex(vec)
                v = vec[i]
                vals[i] = isnan(v) ? out.fill_value : Float64(v)
            end
            vdef = ncd.defVar(ds, name, Float64, ("time",); attrib = Dict(
                "standard_name" => vm.standard_name,
                "long_name" => vm.long_name,
                "units" => vm.unit,
                "description" => string(vm.description),
                "_FillValue" => out.fill_value,
                "missing_value" => out.fill_value,
                "coordinates" => "time latitude longitude" * (out.location.elevation === nothing ? "" : " height"),
            ))
            vdef[:] = vals
        end
    finally
        ncd.close(ds)
    end
    return nothing
end

function _prepare_time_values(time_labels)
    # Returns (values::Vector{Float64}, units::String, calendar::String)
    calendar = "gregorian"
    if eltype(time_labels) <: DateTime
        epoch = DateTime(1970, 1, 1)
        vals = similar(time_labels, Float64)
        @inbounds for i in eachindex(time_labels)
            dt = time_labels[i]
            # seconds since epoch as Float64
            vals[i] = (Dates.value(dt - epoch) / 1000)
        end
        return vals, "seconds since 1970-01-01 00:00:00", calendar
    elseif eltype(time_labels) <: Date
        epoch = Date(1970, 1, 1)
        vals = similar(time_labels, Float64)
        @inbounds for i in eachindex(time_labels)
            d = time_labels[i]
            vals[i] = Float64(Dates.value(d - epoch)) # days since epoch
        end
        return vals, "days since 1970-01-01", calendar
    else
        @warn "NetCDFOutput: time dimension is not of type Date or DateTime; writing as integer index with arbitrary units"
        vals = collect(0:length(time_labels)-1)
        valsf = Float64.(vals)
        return valsf, "seconds since 1970-01-01 00:00:00", calendar
    end
end
