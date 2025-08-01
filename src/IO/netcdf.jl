struct NetCDFOutput <: AbstractOutput
    filename::String
end

function write_data(p::NetCDFOutput, high_frequency_data, low_frequency_data; kwargs...)
    # Write some shit
end