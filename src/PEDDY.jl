module PEDDY

abstract type PipelineStep end

abstract type AbstractInput <: PipelineStep end
function read_data end

abstract type AbstractLimitCheck <: PipelineStep end
function control_physical_limits! end

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

const OptionalPipelineStep = Union{Nothing, PipelineStep}

abstract type AbstractSensor end
struct CSAT3 <: AbstractSensor end
struct CSAT3B <: AbstractSensor end
struct IRGASON <: AbstractSensor end
struct LICOR <: AbstractSensor end

# include("errors.jl")
include("pipeline.jl")
include("IO/IO.jl")
include("bounds_check.jl")

end
