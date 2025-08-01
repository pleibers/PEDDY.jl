using ProgressMeter

@kwdef struct EddyPipeline{SI <: AbstractSensor, I <: AbstractInput, L <: OptionalPipelineStep, D <: OptionalPipelineStep, G <: OptionalPipelineStep, GA <: OptionalPipelineStep, DR <: OptionalPipelineStep, MRD <: OptionalPipelineStep, O <: AbstractOutput}
    sensor::SI
    input::I
    limit_check::L
	despiking::D
	gap_filling::G
	gas_analyzer::GA
	double_rotation::DR
	mrd::MRD
	output::O
end

# Default to no operation
quality_control!(qc::Nothing, high_frequency_data, low_frequency_data, sensor; kwargs...) = nothing
despike!(despiking::Nothing, high_frequency_data, low_frequency_data; kwargs...) = nothing
fill_gaps!(gap_filling::Nothing, high_frequency_data, low_frequency_data; kwargs...) = nothing
correct_gas_analyzer!(gas_analyzer::Nothing, high_frequency_data, low_frequency_data; kwargs...) = nothing
rotate!(double_rotation::Nothing, high_frequency_data, low_frequency_data; kwargs...) = nothing
decompose!(mrd::Nothing, high_frequency_data, low_frequency_data; kwargs...) = nothing

# Data should be in the correct format
function process(pipeline::EddyPipeline; kwargs...)
    prog = ProgressUnknown("PEDDY is cleaning your data...",spinner=true)

    next!(prog; showvalues = [("Status", "Reading Data...")])
    high_frequency_data, low_frequency_data = read_data(pipeline.input; kwargs...)
    check_data(high_frequency_data, pipeline.sensor)
    # FAQ: Should we check the low frequency data?

    next!(prog; showvalues = [("Status", "Performing Quality Control...")])
    quality_control!(pipeline.limit_check, high_frequency_data, low_frequency_data, pipeline.sensor; kwargs...)
    
    next!(prog; showvalues = [("Status", "Removing Spikes...")])
    despike!(pipeline.despiking, high_frequency_data, low_frequency_data; kwargs...)
    
    next!(prog; showvalues = [("Status", "Filling Gaps...")])
    fill_gaps!(pipeline.gap_filling, high_frequency_data, low_frequency_data; kwargs...)
    
    next!(prog; showvalues = [("Status", "Correcting Gas Analyzer...")])
    correct_gas_analyzer!(pipeline.gas_analyzer, high_frequency_data, low_frequency_data; kwargs...)
    
    next!(prog; showvalues = [("Status", "Applying Double Rotation...")])
    rotate!(pipeline.double_rotation, high_frequency_data, low_frequency_data; kwargs...) # should these two be in place?
    
    next!(prog; showvalues = [("Status", "Decomposing MRD...")])
    decompose!(pipeline.mrd, high_frequency_data, low_frequency_data; kwargs...) # should these two be in place?
    
    next!(prog; showvalues = [("Status", "Writing Data...")])
    write_data(pipeline.output, high_frequency_data, low_frequency_data; kwargs...)
    
    finish!(prog; desc="PEDDY is done cleaning your data!")
end

function check_data(data::DimArray, sensor::AbstractSensor)
    needed_cols = needs_cols(sensor)
    if !(:Var in name.(dims(data)))
        throw(ArgumentError("Data must have a Var dimension"))
    end
    if !(:Ti in name.(dims(data)))
        throw(ArgumentError("Data must have a Time dimension"))
    end
    var_names = val(dims(data, :Var))
    for col in needed_cols
        if !(col in var_names)
            throw(ArgumentError("Var dimension must have a $col variable"))
        end
    end
end