export ICSVOutput
export NetCDFOutput
export MemoryOutput
#Input
abstract type AbstractInput end
function read_data end
include("dat_directory.jl")
# Output
include("icsv.jl")
include("netcdf.jl")
include("memory_output.jl")
