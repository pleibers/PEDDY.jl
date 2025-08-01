struct ICSVOutput <: AbstractOutput
    filename::String
end

function write_data(p::ICSVOutput, high_frequency_data, low_frequency_data; kwargs...)
    # Write some shit
end
