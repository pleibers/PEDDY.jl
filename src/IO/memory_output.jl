"""
    MemoryOutput{T} <: AbstractOutput

Output struct that stores processed data in memory instead of writing to files.
Useful for testing and when you want to keep results in memory for further processing.

# Fields
- `high_frequency_data::T`: Processed high frequency data
- `low_frequency_data::T`: Processed low frequency data
"""
mutable struct MemoryOutput{T} <: AbstractOutput
    high_frequency_data::T
    low_frequency_data::T
    
    # Constructor for empty output
    MemoryOutput{T}() where T = new{T}()
end

# Convenience constructor
function MemoryOutput()
    @warn "MemoryOutput created without type specification. Defaulting to Any. Might cause performance issues."; 
    return MemoryOutput{Any}()
end

"""
    write_data(output::MemoryOutput, high_frequency_data, low_frequency_data; kwargs...)

Store the processed data in the MemoryOutput struct instead of writing to files.

# Arguments
- `output::MemoryOutput`: Output struct to store data in
- `high_frequency_data`: Processed high frequency data
- `low_frequency_data`: Processed low frequency data
- `kwargs...`: Additional keyword arguments (ignored)
"""
function write_data(output::MemoryOutput, high_frequency_data, low_frequency_data; kwargs...)
    output.high_frequency_data = high_frequency_data
    output.low_frequency_data = low_frequency_data
    return nothing
end

"""
    get_results(output::MemoryOutput)

Retrieve the stored results from a MemoryOutput.

# Returns
- Tuple of (high_frequency_data, low_frequency_data)
"""
function get_results(output::MemoryOutput)
    return output.high_frequency_data, output.low_frequency_data
end
