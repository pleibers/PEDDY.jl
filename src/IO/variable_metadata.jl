@kwdef struct VariableMetadata
    standard_name::String
    unit::String = ""
    long_name::String = ""
    description = ""
end

const DEFAULT_VARIABLE_METADATA = Dict{Symbol,VariableMetadata}(
    :timestamp => VariableMetadata(
        standard_name = "timestamp",
        unit = "",
        long_name = "Timestamp",
        description = "Timestamp in the ISO format"
    ),
    :Ux => VariableMetadata(
        standard_name = "eastward_wind",
        unit = "m s^-1",
        long_name = "u wind component",
        description = "East-west wind component"
    ),
    :Uy => VariableMetadata(
        standard_name = "northward_wind",
        unit = "m s^-1",
        long_name = "v wind component",
        description = "North-south wind component"
    ),
    :Uz => VariableMetadata(
        standard_name = "upward_air_velocity",
        unit = "m s^-1",
        long_name = "w wind component",
        description = "Vertical wind component"
    ),
    :Ts => VariableMetadata(
        standard_name = "surface_temperature",
        unit = "K",
        long_name = "surface temperature",
        description = "Surface temperature"
    ),
    :CO2 => VariableMetadata(
        standard_name = "carbon_dioxide",
        unit = "ppm",
        long_name = "carbon dioxide",
        description = "Carbon dioxide"
    ),
    :H2O => VariableMetadata(
        standard_name = "water_vapor",
        unit = "ppm",
        long_name = "water vapor",
        description = "Water vapor"
    ),
    :P => VariableMetadata(
        standard_name = "air_pressure",
        unit = "Pa",
        long_name = "air pressure",
        description = "Air pressure"
    ),
    :RH => VariableMetadata(
        standard_name = "relative_humidity",
        unit = "%",
        long_name = "relative humidity",
        description = "Relative humidity"
    )
)

metadata_for(name::Symbol) = get(DEFAULT_VARIABLE_METADATA, name, VariableMetadata(standard_name=String(name)))
metadata_for(name::AbstractString) = metadata_for(Symbol(name))

get_default_metadata() = DEFAULT_VARIABLE_METADATA