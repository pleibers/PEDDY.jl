module PEDDY

using Reexport
@reexport using DimensionalData
using DimensionalData: @dim

abstract type PipelineStep end

abstract type AbstractInput <: PipelineStep end

"""
    read_data(p::AbstractInput; kwargs...)

Read data from a file. Or pass data to the pipeline directly.

# Returns 
    data::DimArray
"""
function read_data end

abstract type AbstractSensor end
function check_diagnostics! end

abstract type AbstractQC <: PipelineStep end
function quality_control! end

abstract type AbstractDespiking <: PipelineStep end
function despike! end

abstract type AbstractGapFilling <: PipelineStep end
function fill_gaps! end

abstract type AbstractGasAnalyzer <: PipelineStep end
function correct_gas_analyzer! end

abstract type AbstractDoubleRotation <: PipelineStep end
function rotate! end

abstract type AbstractMRD <: PipelineStep end
function decompose! end

abstract type AbstractOutput <: PipelineStep end
function write_data end

const OptionalPipelineStep = Union{Nothing,PipelineStep}

@dim Var "Variables"
export Var

include("Sensors/sensors.jl")

include("pipeline.jl")

include("IO/IO.jl")

include("QC/QC.jl")
include("h2o_correction.jl")
include("despiking.jl")
include("interpolation.jl")
include("double_rotation.jl")
include("MRD.jl")

export AbstractInput, AbstractSensor, AbstractQC, AbstractDespiking, AbstractGapFilling,
       AbstractGasAnalyzer, AbstractDoubleRotation, AbstractMRD, AbstractOutput
export read_data, write_data
export check_diagnostics!, quality_control!, despike!, fill_gaps!, correct_gas_analyzer!,
       rotate!, decompose!

end
