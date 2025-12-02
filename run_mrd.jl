"""
runmrd.jl

Standalone script to:
1. Read already processed sonic data (single *_processed.dat file) from `input_path`.
2. Run Orthogonal MRD on that dataset.
3. Write a concise statistics file  (median / q25 / q75 per scale) -> `<output_base>_mrd.dat`.
4. Save a summary MRD plot            -> `<output_base>_mrd_summary.pdf`.

Adjust the three path/base variables below as needed.
"""

using PEDDY, Dates, Statistics, CSV
using DimensionalData
using Plots
using LaTeXStrings
using PEDDY.MRDPlotting
using Glob

# Data setup

# SLF PC
# input_path = raw"H:\_SILVEX II 2025\Data\EC data\Silvia 2 (oben)\PEDDY\input\\"
# output_path = raw"H:\_SILVEX II 2025\Data\EC data\Silvia 2 (oben)\PEDDY\output\mrd\\"

# MacBook (HDD)
input_path = raw"/Volumes/Expansion/Data/SILVEX II/Silvia 2 (oben)/PEDDY/output"
output_path = raw"/Volumes/Expansion/Data/SILVEX II/Silvia 2 (oben)/PEDDY/output/mrd"

# Output base filename
output_base = "SILVEXII_Silvia2_1m"

# Ensure output directory exists
mkpath(output_path)

fo = PEDDY.FileOptions(
    header = 1,
    delimiter = ",",
    comment = "#",
    timestamp_column = :timestamp,
    time_format = DateFormat("yyyy-mm-ddTHH:MM:SS.s")
)

# ---------------------------------------------------------------------------
# Lightweight reader for a single processed .dat file -> DimArray
# (Mirrors internal logic of PEDDY.read_data for one HF file.)
# ---------------------------------------------------------------------------

function read_processed_dimarray(path::AbstractString, opts::PEDDY.FileOptions; N::Type{T}=Float64) where {T<:Real}
    tscol = opts.timestamp_column
    types_map = Dict(tscol => DateTime)
    f = CSV.File(path; header=opts.header, delim=opts.delimiter, comment=opts.comment,
                 types=types_map, dateformat=opts.time_format)
    timestamps = f[tscol]
    # All remaining columns except timestamp are variables
    vars = Symbol[x for x in f.names if x != tscol]
    data = Matrix{T}(undef, length(timestamps), length(vars))
    for (j, v) in pairs(vars)
        data[:, j] .= f[v]
    end
    DimArray(data, (PEDDY.Ti(timestamps), PEDDY.Var(vars)))
end

processed_files = Glob.glob("*_SILVEXII_Silvia2_1m.dat", input_path)

if isempty(processed_files)
    error("No processed sonic files found in $(input_path). Patterns tried: $processed_files and fallback.")
end

@info "Found processed sonic files" count=length(processed_files)

# Read all files into DimArrays
arrays = DimArray[]
for file in processed_files
    @info "Reading processed sonic data" file
    push!(arrays, read_processed_dimarray(file, fo))
end

if length(arrays) == 1
    processed_sonic = arrays[1]
else
    # Sort arrays chronologically by first timestamp
    function first_timestamp(A)
        dd = PEDDY.dims(A)
        ti = collect(dd[findfirst(x -> x isa PEDDY.Ti, dd)])
        return ti[1]
    end
    sort!(arrays; by=first_timestamp)
    # Optional overlap check & warning
    for i in 2:length(arrays)
        prev_last = collect(PEDDY.dims(arrays[i-1])[findfirst(x-> x isa PEDDY.Ti, PEDDY.dims(arrays[i-1]))]) |> last
        this_first = first_timestamp(arrays[i])
        if this_first <= prev_last
            @warn "Timestamp overlap or disorder between file $(i-1) and $i" prev_last this_first
        end
    end
    # Concatenate along time (assumes identical variable sets)
    processed_sonic = vcat(arrays...)
end

@info "Combined processed sonic data" nfiles=length(arrays) ntimes=length(collect(PEDDY.dims(processed_sonic)[findfirst(x-> x isa PEDDY.Ti, PEDDY.dims(processed_sonic))]))

# ---------------------------------------------------------------------------
# MRD computation
# ---------------------------------------------------------------------------
mrd = PEDDY.OrthogonalMRD(M=14, normalize=true)
PEDDY.decompose!(mrd, processed_sonic, nothing)  # low-frequency data is not used here
res = PEDDY.get_mrd_results(mrd)

# ---------------------------------------------------------------------------
# Export MRD stats (.dat)
# ---------------------------------------------------------------------------
function write_mrd_dat(res, filepath; delim = ",")
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
            println(io, string(scales[i], delim,
                               isnan(med[i]) ? "NaN" : string(med[i]), delim,
                               isnan(q25[i]) ? "NaN" : string(q25[i]), delim,
                               isnan(q75[i]) ? "NaN" : string(q75[i])))
        end
    end
end

mrd_dat_path = joinpath(output_path, output_base * "_mrd.dat")
write_mrd_dat(res, mrd_dat_path)
@info "Wrote MRD statistics" mrd_dat_path

# ---------------------------------------------------------------------------
# Plot (summary)
# ---------------------------------------------------------------------------
function fmt_title(t) t isa Dates.AbstractDateTime ? Dates.format(t, dateformat"yyyy-mm-dd HH:MM") : string(t) end
summary_pdf = joinpath(output_path, output_base * "_mrd.pdf")
try
    ddims = PEDDY.dims(processed_sonic)
    ti = collect(ddims[findfirst(x -> x isa PEDDY.Ti, ddims)])
    title_str = "MRD " * fmt_title(ti[1]) * " - " * fmt_title(ti[end])
    finite_scales = filter(x -> isfinite(x) && x > 0, res.scales)
    if !isempty(finite_scales)
        lo = floor(Int, log10(minimum(finite_scales)))
        hi = ceil(Int, log10(maximum(finite_scales)))
        decade_positions = [10.0^k for k in lo:hi]
        decade_labels = [LaTeXString("10^{$k}") for k in lo:hi]
        plt = plot(mrd; kind=:summary, metric=:mrd, logscale=true,
                   title=title_str, xticks=(decade_positions, decade_labels),
                   xminorgrid=true, minorgrid=true,
                   xlabel=L"\tau [\mathrm{s}]",
                   ylabel=L"C_{T_s w} [10^{-3} \mathrm{K m s}^{-1}]")
        savefig(plt, summary_pdf)
    else
        plt = plot(mrd; kind=:summary, metric=:mrd, logscale=true,
                   title=title_str, xminorgrid=true, minorgrid=true,
                   xlabel=L"\tau [\mathrm{s}]",
                   ylabel=L"C_{w T_s} [10^{-3} \mathrm{K m s}^{-1}]")
        savefig(plt, summary_pdf)
    end
    @info "Saved MRD summary plot" summary_pdf
catch e
    @warn "MRD plotting skipped" error=e
end

# Agent mode is working!