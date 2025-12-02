using PEDDY, Glob, Dates, Statistics
using DimensionalData
using Plots
using LaTeXStrings
using PEDDY.MRDPlotting

# Sensor setup
sensor = PEDDY.IRGASON()
needed_cols = collect(PEDDY.needs_data_cols(sensor))

# Set up pipeline components
output = PEDDY.MemoryOutput()
gap_filling = PEDDY.GeneralInterpolation(; max_gap_size = 40, 
                                        variables = needed_cols,
                                        method = PEDDY.Linear())

pipeline = PEDDY.EddyPipeline(; sensor = sensor,
                            quality_control = PEDDY.PhysicsBoundsCheck(),
                            despiking = PEDDY.SimpleSigmundDespiking(window_minutes = 5.0),
                            gap_filling = gap_filling,
                            gas_analyzer = nothing,
                            double_rotation = PEDDY.WindDoubleRotation(block_duration_minutes = 1.0),
                            #mrd = PEDDY.OrthogonalMRD(M=14),
                            output = output
)

# Data setup

# SLF PC
#datapath = raw"H:\_SILVEX II 2025\Data\EC data\Silvia 2 (oben)\PEDDY\input\\"
#outputpath = raw"H:\_SILVEX II 2025\Data\EC data\Silvia 2 (oben)\PEDDY\output\\"

# Mac
datapath = raw"/Volumes/Expansion/Data/SILVEX II/Silvia 2 (oben)/PEDDY/input"
outputpath = raw"/Volumes/Expansion/Data/SILVEX II/Silvia 2 (oben)/PEDDY/output"

fo = PEDDY.FileOptions(
    header = 1,
    delimiter = ",",
    comment = "#",
    timestamp_column = :TIMESTAMP,
    time_format = DateFormat("yyyy-mm-ddTHH:MM:SS.s")
)

input = PEDDY.DotDatDirectory(
    directory = datapath,
    high_frequency_file_glob = "SILVEXII_Silvia2_sonics_002_1m.dat",
    high_frequency_file_options = fo,
    low_frequency_file_glob = nothing,
    low_frequency_file_options = nothing
)

# Read data
hf, lf = PEDDY.read_data(input, sensor)
# Keep an immutable copy of input HF for QA comparisons
hf_raw = deepcopy(hf)

# Run pipeline
PEDDY.process!(pipeline, hf, lf)

# Get results
processed_sonicdata, _ = PEDDY.get_results(output)
processed_sonicdata

mrd = PEDDY.OrthogonalMRD(M=14, normalize=true)
PEDDY.decompose!(mrd, hf, lf)
res = PEDDY.get_mrd_results(mrd)
res

# ---- Helpers: QA checks and .dat exports ----

format_ts(t) = t isa Dates.AbstractDateTime ? Dates.format(t, dateformat"yyyy-mm-ddTHH:MM:SS.s") : string(t)

# Title-friendly timestamp (no 'T', no seconds/milliseconds)
format_ts_title(t) = t isa Dates.AbstractDateTime ? Dates.format(t, dateformat"yyyy-mm-dd HH:MM") : string(t)

function count_nans_by_var(data)
    vars = collect(PEDDY.dims(data, PEDDY.Var))
    counts = Dict{Symbol, Int}()
    for v in vars
        col = parent(data[Var=At(v)])
        if v === :diag_sonic || v === :diag_gas
            counts[v] = count(x -> (x > 0) && !(x isa AbstractFloat && isnan(x)), col)
        else
            counts[v] = count(isnan, col)
        end
    end
    return counts
end

function write_dimarray_dat(data, filepath; delim = ",")
    ddims = PEDDY.dims(data)
    ti = collect(ddims[findfirst(x -> x isa PEDDY.Ti, ddims)])
    vars = collect(ddims[findfirst(x -> x isa PEDDY.Var, ddims)])
    A = data.data  # parent matrix with rows=time, cols=vars
    open(filepath, "w") do io
        # header
        println(io, join(vcat(["timestamp"], String.(vars)), delim))
        # rows
        for i in eachindex(ti)
            row = Vector{String}(undef, length(vars) + 1)
            row[1] = format_ts(ti[i])
            @inbounds for j in 1:length(vars)
                val = A[i, j]
                row[j + 1] = isnan(val) ? "NaN" : string(val)
            end
            println(io, join(row, delim))
        end
    end
end

function write_mrd_dat(res, filepath; delim = ",")
    # Export the same stats shown in the summary plot: scale_s, median, q25, q75
    scales = res.scales
    A = res.mrd  # M x nblocks
    M, _ = size(A)
    med = Vector{Float64}(undef, M)
    q25 = Vector{Float64}(undef, M)
    q75 = Vector{Float64}(undef, M)
    for i in 1:M
        row = @view A[i, :]
        vals = filter(!isnan, collect(row))
        if isempty(vals)
            med[i] = NaN; q25[i] = NaN; q75[i] = NaN
        else
            med[i] = Statistics.median(vals)
            q25[i] = Statistics.quantile(vals, 0.25)
            q75[i] = Statistics.quantile(vals, 0.75)
        end
    end
    open(filepath, "w") do io
        println(io, join(["scale_s", "median", "q25", "q75"], delim))
        for i in 1:M
            s = scales[i]
            m = med[i]
            l = q25[i]
            u = q75[i]
            println(io, string(s, delim,
                               isnan(m) ? "NaN" : string(m), delim,
                               isnan(l) ? "NaN" : string(l), delim,
                               isnan(u) ? "NaN" : string(u)))
        end
    end
end

# ---- Run QA and exports ----

println("QA counts (unprocessed hf): NaNs per var; diag_* counts = values > 0")
for (k, v) in count_nans_by_var(hf_raw)
    println(rpad(String(k), 6), ": ", v)
end

println("QA counts (processed_sonicdata): NaNs per var; diag_* counts = values > 0")
for (k, v) in count_nans_by_var(processed_sonicdata)
    println(rpad(String(k), 6), ": ", v)
end

# Build two basenames:
# - processed_basefile_ts: from first timestamp (yyyy-mm-dd_HHMM_SILVEXII_Silvia2_1m.dat) for processed sonic data
# - default_basefile: from input filename for MRD outputs
ddims_hf = PEDDY.dims(hf)
ti_hf = collect(ddims_hf[findfirst(x -> x isa PEDDY.Ti, ddims_hf)])
first_ts = ti_hf[1]
ts_prefix = Dates.format(first_ts, dateformat"yyyy-mm-dd_HHMM")
processed_basefile_ts = string(ts_prefix, "_SILVEXII_Silvia2_1m.dat")

hf_matches = Glob.glob(input.high_frequency_file_glob, input.directory)
default_basefile = isempty(hf_matches) ? "SILVEXII_Silvia2_1m.dat" : basename(hf_matches[1])

mkpath(outputpath)

# Exports (.dat): MRD uses input-based name; processed sonic uses timestamp-based name
write_mrd_dat(res, joinpath(outputpath, replace(default_basefile, ".dat" => "_mrd.dat")); delim = ",")
write_dimarray_dat(processed_sonicdata, joinpath(outputpath, replace(processed_basefile_ts, ".dat" => "_processed.dat")); delim = ",")
println("Wrote ", joinpath(outputpath, replace(default_basefile, ".dat" => "_mrd.dat")), " and ", joinpath(outputpath, replace(processed_basefile_ts, ".dat" => "_processed.dat")))

# ---- MRD plot (summary only) ----
summary_path = joinpath(outputpath, replace(default_basefile, ".dat" => "_mrd_summary.pdf"))
try
    # Non-empty title and decade ticks (10^x) on log-scale x-axis
    ddims_hf2 = PEDDY.dims(hf)
    ti_hf2 = collect(ddims_hf2[findfirst(x -> x isa PEDDY.Ti, ddims_hf2)])
    plot_title = "MRD " * format_ts_title(ti_hf2[1]) * " - " * format_ts_title(ti_hf2[end])
    # Use decade ticks with LaTeX-like labels (10^x) and enable minor grid
    finite_scales = filter(x -> isfinite(x) && x > 0, res.scales)
    if !isempty(finite_scales)
        lo = floor(Int, log10(minimum(finite_scales)))
        hi = ceil(Int, log10(maximum(finite_scales)))
        decade_positions = [10.0^k for k in lo:hi]
        decade_labels = [LaTeXStrings.LaTeXString("10^{$(k)}") for k in lo:hi]
        plt = plot(mrd; kind = :summary, metric = :mrd, logscale = true,
           title = plot_title, xticks = (decade_positions, decade_labels),
           xminorgrid = true, minorgrid = true,
           xlabel = L"\tau [\mathrm{s}]",
           ylabel = L"C_{T_s w} [10^{-3} \mathrm{K m s}^{-1}]")
    else
        plt = plot(mrd; kind = :summary, metric = :mrd, logscale = true,
           title = plot_title, xminorgrid = true, minorgrid = true,
           xlabel = LaTeXStrings.L"\tau [\mathrm{s}]",
           ylabel = LaTeXStrings.L"C_{w T_s} [10^{-3} \mathrm{K m s}^{-1}]")
    end
    savefig(plt, summary_path)
    println("Saved ", summary_path)
catch e
    println("MRD plotting skipped: ", e)
end