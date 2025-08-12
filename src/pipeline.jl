export EddyPipeline
export process!
export check_data

using ProgressMeter

@kwdef struct EddyPipeline{SI<:AbstractSensor,QC<:OptionalPipelineStep,
                           D<:OptionalPipelineStep,G<:OptionalPipelineStep,
                           GA<:OptionalPipelineStep,DR<:OptionalPipelineStep,
                           MRD<:OptionalPipelineStep,O<:AbstractOutput}
    sensor::SI
    quality_control::QC
    gas_analyzer::GA
    despiking::D
    gap_filling::G
    double_rotation::DR
    mrd::MRD
    output::O
end

# Default to no operation
function quality_control!(qc::Nothing, high_frequency_data, low_frequency_data, sensor;
                          kwargs...)
    return nothing
end
function correct_gas_analyzer!(gas_analyzer::Nothing, high_frequency_data,
                               low_frequency_data, sensor::AbstractSensor; kwargs...)
    return nothing
end
function despike!(despiking::Nothing, high_frequency_data, low_frequency_data; kwargs...)
    return nothing
end
function fill_gaps!(gap_filling::Nothing, high_frequency_data, low_frequency_data;
                    kwargs...)
    return nothing
end
function rotate!(double_rotation::Nothing, high_frequency_data, low_frequency_data;
                 kwargs...)
    return nothing
end
decompose!(mrd::Nothing, high_frequency_data, low_frequency_data; kwargs...) = nothing

# Data should be in the correct format
function process!(pipeline::EddyPipeline, high_frequency_data::DimArray, low_frequency_data::DimArray; kwargs...)
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

function check_data(high_frequency_data::DimArray, low_frequency_data::DimArray, sensor::AbstractSensor)
    # FAQ: Should we check the low frequency data?

    needed_cols = needs_data_cols(sensor)
    if !(:Var in name.(dims(high_frequency_data)))
        throw(ArgumentError("High frequency data must have a Var dimension"))
    end
    if !(:Ti in name.(dims(high_frequency_data)))
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
