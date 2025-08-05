# If it is very confusing we can get rid of has_variables in favor of not using diag stuff
export CSAT3, CSAT3B, LICOR, IRGASON
export default_calibration_coefficients

include("CSAT3.jl")
include("CSAT3B.jl")
include("LICOR.jl")
include("IRGASON.jl")
