using Test
using PEDDY
using DimensionalData
using Dates

# Helper to build a minimal HF/LD dataset with :Uz and :Ts
function build_hf_ld(n; dt_ms=100)
    # Time axis at 10 Hz by default
    t = Ti(Dates.Millisecond.(0:dt_ms:(n - 1) * dt_ms))
    vars = Var([:Uz, :Ts])

    # Simple synthetic signals
    # :Uz ~ sine, :Ts ~ cosine with small trend
    x = collect(0:n-1)
    uz = @. 0.5 * sin(2pi * x / 200) + 0.05 * sin(2pi * x / 50)
    ts = @. 0.8 * cos(2pi * x / 180) + 0.001 * x

    hd = DimArray(hcat(uz, ts), (t, vars))
    # Low-frequency placeholder (unused by MRD but required by API)
    ld = DimArray(zeros(10, 1), (Ti(1:10), Var([:dummy])))
    return hd, ld
end

@testset "OrthogonalMRD" begin
    @testset "Basic decomposition produces shapes and metadata" begin
        n = 4096  # enough for multiple blocks with default M=11 (2^11=2048)
        hd, ld = build_hf_ld(n)

        mrd = PEDDY.OrthogonalMRD()
        PEDDY.decompose!(mrd, hd, ld)
        res = PEDDY.get_mrd_results(mrd)

        @test res !== nothing
        @test size(res.mrd, 1) == mrd.M
        @test length(res.scales) == mrd.M
        @test length(res.times) == size(res.mrd, 2)

        # Check scales follow 2^i * dt
        dt = (Dates.value(dims(hd, Ti)[2] - dims(hd, Ti)[1])) / 1000.0
        @test all(isapprox.(res.scales, [2.0^i * dt for i in 1:mrd.M]; atol=1e-12))
    end

    @testset "Blocks with large internal gaps are skipped" begin
        # Configure for two non-overlapping blocks to make counting easy
        # M=11 -> block_len=2048, shift=2048 -> 2 blocks for n=4096
        n = 4096
        dt_ms = 100
        hd, ld = build_hf_ld(n; dt_ms=dt_ms)

        # Inject one large time gap inside the first block: > 10 s
        ti = collect(dims(hd, Ti))
        gap_index = 1000
        ti[(gap_index + 1):end] .= ti[(gap_index + 1):end] .+ Millisecond(15_000) # 15 s gap
        # Rebuild DimArray with modified time axis
        hd = DimArray(parent(hd), (Ti(ti), dims(hd, Var)))

        mrd = PEDDY.OrthogonalMRD(M=11, shift=2048, gap_threshold_seconds=10.0)
        PEDDY.decompose!(mrd, hd, ld)
        res = PEDDY.get_mrd_results(mrd)

        # Only the second block should remain (first contains the gap)
        @test res !== nothing
        @test size(res.mrd, 2) == 1
        @test length(res.times) == 1
    end

    @testset "Normalization runs and returns finite values" begin
        n = 4096
        hd, ld = build_hf_ld(n)

        mrd_plain = PEDDY.OrthogonalMRD(normalize=false)
        PEDDY.decompose!(mrd_plain, hd, ld)
        res_plain = PEDDY.get_mrd_results(mrd_plain)

        mrd_norm = PEDDY.OrthogonalMRD(normalize=true)
        PEDDY.decompose!(mrd_norm, hd, ld)
        res_norm = PEDDY.get_mrd_results(mrd_norm)

        @test res_plain !== nothing
        @test res_norm !== nothing
        @test size(res_plain.mrd) == size(res_norm.mrd)
        @test all(isfinite, vec(res_norm.mrd))
    end
end
