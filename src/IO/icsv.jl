try
    using PYiCSV
catch e
    @warn "Could not load PYiCSV, ICSVOutput will not be available"
end

struct ICSVOutput <: AbstractOutput
    filename::String
end

function write_data(p::ICSVOutput, high_frequency_data::DimArray, low_frequency_data::Union{Nothing,DimArray}; kwargs...)
    # Write some shit
end
