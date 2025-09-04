using PEDDY, Glob, Dates, Statistics
using DimensionalData
using Plots
using LaTeXStrings
using PEDDY.MRDPlotting

function main()
    # Paths
    outputpath = raw"H:\_SILVEX II 2025\Data\EC data\Silvia 2 (oben)\PEDDY\output\\"

    # File discovery: choose the latest processed file written by runprocessing.jl
    # Pattern: yyyy-mm-dd_HHMM_SILVEXII_Silvia2_1m.dat
    processed_files = Glob.glob(joinpath(outputpath, "*_SILVEXII_Silvia2_1m.dat"))
    isempty(processed_files) && error("No processed files found in output path: " * outputpath)
    processed_files = sort(processed_files; by=f->stat(f).mtime)
    processed_path = processed_files[end]

    # Read processed HF back into a DimArray
    fo_proc = PEDDY.FileOptions(
        header = 1,
        delimiter = ",",
        comment = "#",
        timestamp_column = :timestamp,
        time_format = DateFormat("yyyy-mm-ddTHH:MM:SS.s"),
    )
    input_proc = PEDDY.DotDatDirectory(
        directory = dirname(processed_path),
        high_frequency_file_glob = basename(processed_path),
        high_frequency_file_options = fo_proc,
        low_frequency_file_glob = nothing,
        low_frequency_file_options = nothing,
    )
    hf, lf = PEDDY.read_data(input_proc, PEDDY.IRGASON())

    # Run MRD
    mrd = PEDDY.OrthogonalMRD(M=14, normalize=true)
    PEDDY.decompose!(mrd, hf, lf)
    res = PEDDY.get_mrd_results(mrd)

    # Helper: title-friendly timestamp (no 'T', no seconds/milliseconds)
    format_ts_title(t) = t isa Dates.AbstractDateTime ? Dates.format(t, dateformat"yyyy-mm-dd HH:MM") : string(t)

    # Export MRD .dat with input-based name
    hf_matches = Glob.glob(joinpath(outputpath, "SILVEXII_Silvia2_sonics_002_1m.dat"))
    default_basefile = isempty(hf_matches) ? replace(basename(processed_path), "_processed.dat" => ".dat") : basename(hf_matches[1])
    open(joinpath(outputpath, replace(default_basefile, ".dat" => "_mrd.dat")), "w") do io
        scales = res.scales
        A = res.mrd
        M, _ = size(A)
        println(io, join(["scale_s", "median", "q25", "q75"], ","))
        for i in 1:M
            row = @view A[i, :]
            vals = filter(!isnan, collect(row))
            if isempty(vals)
                println(io, string(scales[i], ",NaN,NaN,NaN"))
            else
                m = Statistics.median(vals)
                l = Statistics.quantile(vals, 0.25)
                u = Statistics.quantile(vals, 0.75)
                println(io, string(scales[i], ",", m, ",", l, ",", u))
            end
        end
    end

    # ---- MRD plot (summary only) ----
    summary_path = joinpath(outputpath, replace(default_basefile, ".dat" => "_mrd_summary.pdf"))
    try
        ddims_hf2 = PEDDY.dims(hf)
        ti_hf2 = collect(ddims_hf2[findfirst(x -> x isa PEDDY.Ti, ddims_hf2)])
        plot_title = "MRD " * format_ts_title(ti_hf2[1]) * " - " * format_ts_title(ti_hf2[end])

        finite_scales = filter(x -> isfinite(x) && x > 0, res.scales)
        if !isempty(finite_scales)
            lo = floor(Int, log10(minimum(finite_scales)))
            hi = ceil(Int, log10(maximum(finite_scales)))
            decade_positions = [10.0^k for k in lo:hi]
            decade_labels = [LaTeXStrings.L"10^{${k}}" for k in lo:hi]
            plt = plot(mrd; kind = :summary, metric = :mrd, logscale = true,
               title = plot_title, xticks = (decade_positions, decade_labels),
               xminorgrid = true, minorgrid = true,
               xlabel = L"\tau [s]",
               ylabel = L"C_{w T_s} [10^{-3} K m s^{-1}]")
        else
            plt = plot(mrd; kind = :summary, metric = :mrd, logscale = true,
               title = plot_title, xminorgrid = true, minorgrid = true,
               xlabel = L"\tau [s]",
               ylabel = L"C_{w T_s} [10^{-3} K m s^{-1}]")
        end
        savefig(plt, summary_path)
        println("Saved ", summary_path)
    catch e
        println("MRD plotting skipped: ", e)
    end
end

main()