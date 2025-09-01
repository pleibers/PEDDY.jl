export EddyPipeline
export process!
export check_data

using ProgressMeter

"""
    EddyPipeline(; sensor, quality_control, gas_analyzer, despiking, gap_filling,
                  double_rotation, mrd, output)

High-level orchestrator for the PEDDY.jl processing pipeline.

Each step is a pluggable component that implements its respective abstract
interface. Any step can be set to `nothing` to skip it. The typical order is:

1. Quality control (`quality_control!`)
2. Gas analyzer correction (`correct_gas_analyzer!`)
3. Despiking (`despike!`)
4. Gap filling (`fill_gaps!`)
5. Double rotation (`rotate!`)
6. MRD decomposition (`decompose!`)
7. Output writing (`write_data`)

Fields
- `sensor::AbstractSensor`: Sensor providing metadata (and coefficients)
- `quality_control::OptionalPipelineStep`
- `gas_analyzer::OptionalPipelineStep`
- `despiking::OptionalPipelineStep`
- `gap_filling::OptionalPipelineStep`
- `double_rotation::OptionalPipelineStep`
- `mrd::OptionalPipelineStep`
- `output::AbstractOutput`: Writer implementation
"""
@kwdef struct EddyPipeline{SI<:AbstractSensor,QC<:OptionalPipelineStep,
                           D<:OptionalPipelineStep,G<:OptionalPipelineStep,
                           GA<:OptionalPipelineStep,DR<:OptionalPipelineStep,
                           MRD<:OptionalPipelineStep,O<:AbstractOutput}
    sensor::SI
    quality_control::QC = nothing
    gas_analyzer::GA = nothing
    despiking::D = nothing
    gap_filling::G = nothing
    double_rotation::DR = nothing
    mrd::MRD = nothing
    output::O
end

# Default to no operation
"""No-op quality control when `quality_control` is `nothing`."""
function quality_control!(qc::Nothing, high_frequency_data, low_frequency_data, sensor;
                          kwargs...)
    return nothing
end
"""No-op gas analyzer correction when `gas_analyzer` is `nothing`."""
function correct_gas_analyzer!(gas_analyzer::Nothing, high_frequency_data,
                               low_frequency_data, sensor::AbstractSensor; kwargs...)
    return nothing
end
"""No-op despiking when `despiking` is `nothing`."""
function despike!(despiking::Nothing, high_frequency_data, low_frequency_data; kwargs...)
    return nothing
end
"""No-op gap filling when `gap_filling` is `nothing`."""
function fill_gaps!(gap_filling::Nothing, high_frequency_data, low_frequency_data;
                    kwargs...)
    return nothing
end
"""No-op double rotation when `double_rotation` is `nothing`."""
function rotate!(double_rotation::Nothing, high_frequency_data, low_frequency_data;
                 kwargs...)
    return nothing
end
decompose!(mrd::Nothing, high_frequency_data, low_frequency_data; kwargs...) = nothing

# Data should be in the correct format
"""
    process!(pipeline::EddyPipeline, high_frequency_data::DimArray,
             low_frequency_data::Union{Nothing,DimArray}; kwargs...) -> Nothing

Run the configured pipeline over the provided data. Steps that are `nothing`
are skipped. Progress is shown via a spinner with status messages.

Arguments
- `pipeline`: An `EddyPipeline` instance
- `high_frequency_data`: DimArray with fast measurements (must have `Var` and `Ti` dims)
- `low_frequency_data`: DimArray with slow data or `nothing`
- `kwargs...`: Forwarded to step implementations
"""
function process!(pipeline::EddyPipeline, high_frequency_data::DimArray, low_frequency_data::Union{Nothing, DimArray}; kwargs...)
    prog = ProgressUnknown(;desc="PEDDY is cleaning your data...", spinner=true)

    check_data(high_frequency_data, low_frequency_data, pipeline.sensor)

    next!(prog; showvalues=[("Status", "Performing Quality Control...")], spinner="🔬")
    quality_control!(pipeline.quality_control, high_frequency_data, low_frequency_data,
                     pipeline.sensor; kwargs...)

    next!(prog; showvalues=[("Status", "Correcting Gas Analyzer...")], spinner="🧹")
    correct_gas_analyzer!(pipeline.gas_analyzer, high_frequency_data, low_frequency_data,
                          pipeline.sensor; kwargs...)

    next!(prog; showvalues=[("Status", "Removing Spikes...")], spinner="🦔")
    despike!(pipeline.despiking, high_frequency_data, low_frequency_data; kwargs...)

    next!(prog; showvalues=[("Status", "Filling Gaps...")], spinner="🧩")
    fill_gaps!(pipeline.gap_filling, high_frequency_data, low_frequency_data; kwargs...)

    next!(prog; showvalues=[("Status", "Applying Double Rotation...")], spinner="🌀")
    rotate!(pipeline.double_rotation, high_frequency_data, low_frequency_data; kwargs...) # should these two be in place?

    next!(prog; showvalues=[("Status", "Decomposing MRD...")], spinner="〰️")
    decompose!(pipeline.mrd, high_frequency_data, low_frequency_data; kwargs...) # should these two be in place?

    next!(prog; showvalues=[("Status", "Writing Data...")], spinner="💾")
    write_data(pipeline.output, high_frequency_data, low_frequency_data; kwargs...)

    return finish!(prog; desc="PEDDY is done cleaning your data!", spinner="🎉")
end

"""
    check_data(high_frequency_data::DimArray, low_frequency_data::Union{Nothing,DimArray},
               sensor::AbstractSensor) -> Nothing

Validate that the high-frequency data has the required dimensions and variables
for the specified `sensor`. Throws an `ArgumentError` if a requirement is not met.
Currently only the high-frequency data is validated.
"""
function check_data(high_frequency_data::DimArray, low_frequency_data::Union{Nothing,DimArray}, sensor::AbstractSensor)
    # FAQ: Should we check the low frequency data?

    needed_cols = needs_data_cols(sensor)
    if !(:Var in DimensionalData.name.(dims(high_frequency_data)))
        throw(ArgumentError("High frequency data must have a Var dimension"))
    end
    if !(:Ti in DimensionalData.name.(dims(high_frequency_data)))
        throw(ArgumentError("High frequency data must have a Time dimension"))
    end
    var_names = val(dims(high_frequency_data, :Var))
    for col in needed_cols
        if !(col in var_names)
            throw(ArgumentError("Var dimension must have a $col variable"))
        end
    end
    @debug "High frequency data checked, no checks performed on low frequency data"
end
