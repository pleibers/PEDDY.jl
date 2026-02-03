using Peddy
using DimensionalData

sensor = Peddy.CSAT3()
needed_cols = collect(Peddy.needs_data_cols(sensor))
n_dims = length(needed_cols)
hd = DimArray(rand(3, n_dims), (Ti(), Var(needed_cols)))
ld = copy(hd)
output = Peddy.ICSVOutput("test.csv")
pipeline = Peddy.EddyPipeline(sensor, nothing, nothing, nothing, nothing, nothing,
                              nothing, output)
Peddy.process!(pipeline, hd, ld)
