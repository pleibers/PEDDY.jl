using Test
using Dates
using DimensionalData
using PEDDY

# Helper to collect data rows from an iCSV file
function _icsv_data_rows(path::AbstractString)
    @assert isfile(path) "Expected iCSV file at $(path)"
    lines = readlines(path)
    idx_data = findfirst(l -> startswith(l, "# [DATA]"), lines)
    @assert idx_data !== nothing "[DATA] section not found in $(path)"
    return [l for l in lines[(idx_data+1):end] if !startswith(l, "#") && !isempty(strip(l))]
end

@testset "OutputSplitter with ICSV (1h blocks)" begin
    if !Base.isdefined(PEDDY, :ICSVOutput)
        @info "ICSVOutput not available (PYiCSV failed to load); skipping OutputSplitter ICSV tests"
        return
    end

    # Build HF dataset: 2h10m at 10-minute resolution -> 3 blocks
    vars = [:Ux, :Uy]
    start = DateTime(2024, 1, 1, 0, 0, 0)
    hf_times = [start + Minute(10)*(i-1) for i in 1:14] # 0:00 .. 2:10
    hf = DimArray(rand(length(hf_times), length(vars)), (Ti(hf_times), Var(vars)))

    # Build LF dataset: measurements every 30 minutes covering each block
    lf_times = [start + Minute(30)*(i-1) + Minute(15) for i in 1:5]  # 00:15, 00:45, 01:15, 01:45, 02:15
    lf_vars = [:Ta, :Pa]
    lf = DimArray(rand(length(lf_times), length(lf_vars)), (Ti(lf_times), Var(lf_vars)))

    tmp = mktempdir()
    base = joinpath(tmp, "split")

    # Inner ICSV output and splitter with 1h blocks
    inner = ICSVOutput(base_filename=base, location=LocationMetadata(latitude=47.0, longitude=8.0))
    splitter = OutputSplitter(output=inner, block_duration=Hour(1))

    # Execute
    write_data(splitter, hf, lf)

    # Expected block starts
    starts = [start, start + Hour(1), start + Hour(2)]

    # Verify HF files exist with correct row counts: 6, 6, 2
    expected_rows_hf = [6, 6, 2]
    for (i, t0) in enumerate(starts)
        fname = joinpath(tmp, string("split_", Dates.format(t0, dateformat"yyyymmddTHHMMSS"), "_1h_hf.icsv"))
        @test isfile(fname)
        rows = _icsv_data_rows(fname)
        @test length(rows) == expected_rows_hf[i]
    end

    # Verify LF files exist with correct row counts: 2, 2, 1 (00:15,00:45) (01:15,01:45) (02:15)
    expected_rows_lf = [2, 2, 1]
    for (i, t0) in enumerate(starts)
        fname = joinpath(tmp, string("split_", Dates.format(t0, dateformat"yyyymmddTHHMMSS"), "_1h_lf.icsv"))
        @test isfile(fname)
        rows = _icsv_data_rows(fname)
        @test length(rows) == expected_rows_lf[i]
    end
end
