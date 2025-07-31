
@kwdef struct EddyPipeline{I <: AbstractInput, L <: OptionalPipelineStep, D <: OptionalPipelineStep, G <: OptionalPipelineStep, GA <: OptionalPipelineStep, DR <: OptionalPipelineStep, MRD <: OptionalPipelineStep, O <: AbstractOutput}
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
control_physical_limits!(bounds_check::Nothing, data; kwargs...) = nothing
despike!(despiking::Nothing, data; kwargs...) = nothing
fill_gaps!(gap_filling::Nothing, data; kwargs...) = nothing
correct_gas_analyzer!(gas_analyzer::Nothing, data; kwargs...) = nothing
rotate!(double_rotation::Nothing, data; kwargs...) = nothing
decompose!(mrd::Nothing, data; kwargs...) = nothing

# Data should be in the correct format
function process(pipeline::EddyPipeline; kwargs...)
    data = read_data(pipeline.input; kwargs...)
    control_physical_limits!(pipeline.limit_check, data; kwargs...)
    despike!(pipeline.despiking, data; kwargs...)
    fill_gaps!(pipeline.gap_filling, data; kwargs...)
    correct_gas_analyzer!(pipeline.gas_analyzer, data; kwargs...)
    rotate!(pipeline.double_rotation, data; kwargs...) # should these two be in place?
    decompose!(pipeline.mrd, data; kwargs...) # should these two be in place?
    write_data(pipeline.output, data; kwargs...)
end
