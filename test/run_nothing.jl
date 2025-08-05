using PEDDY
using DimensionalData

sensor = PEDDY.CSAT3()
needed_cols = collect(PEDDY.needs_cols(sensor))
n_dims = length(needed_cols)
hd = DimArray(rand(3, n_dims), (Ti(), Var(needed_cols)))
ld = copy(hd)
input = PEDDY.PassData(hd, ld)
output = PEDDY.ICSVOutput("test.csv")
pipeline = PEDDY.EddyPipeline(sensor, input, nothing, nothing, nothing, nothing, nothing,
                              nothing, output)
PEDDY.process(pipeline)
