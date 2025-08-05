"""
    PassData(data::AbstractArray)

Pass data through the pipeline without any changes.

When to use:
    If you implement your own data reading and want to pass data to the pipeline directly.
"""
struct PassData{D<:AbstractArray} <: AbstractInput
    high_frequency_data::D
    low_frequency_data::D
end

function read_data(p::PassData; kwargs...)
    return p.high_frequency_data, p.low_frequency_data
end
