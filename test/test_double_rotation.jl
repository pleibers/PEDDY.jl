using Test
using PEDDY
using DimensionalData
using Dates
using Statistics

# Helper: mean ignoring NaNs
mean_skipnan(v) = begin
    s = 0.0
    c = 0
    @inbounds for x in v
        if !isnan(x)
            s += x
            c += 1
        end
    end
    c == 0 ? NaN : s / c
end

@testset "Double Rotation" begin
    @testset "Basic rotation zeroes v and w means" begin
        n = 2000
        # 10 Hz sampling => 100 ms between samples
        t = Ti(Dates.Millisecond.(0:100:(n - 1) * 100))
        vars = Var([:Ux, :Uy, :Uz])

        # Create wind with non-zero mean v and w
        u = 2 .+ 0.1 .* randn(n)
        v = 1 .+ 0.1 .* randn(n)
        w = 0.5 .+ 0.1 .* randn(n)
        data = hcat(u, v, w)
        hd = DimArray(data, (t, vars))
        ld = DimArray(zeros(10, 1), (Ti(1:10), Var([:dummy])))

        dr = PEDDY.WindDoubleRotation(block_duration_minutes=0.5) # 30s blocks
        PEDDY.rotate!(dr, hd, ld)

        v_rot = hd[Var=At(:Uy)]
        w_rot = hd[Var=At(:Uz)]

        @test isapprox(mean_skipnan(v_rot), 0.0; atol=1e-6)
        @test isapprox(mean_skipnan(w_rot), 0.0; atol=1e-6)
    end

    @testset "Handles NaNs gracefully" begin
        n = 1500
        t = Ti(Dates.Millisecond.(0:100:(n - 1) * 100))
        vars = Var([:Ux, :Uy, :Uz])

        u = 3 .+ 0.2 .* randn(n)
        v = 0.8 .+ 0.2 .* randn(n)
        w = 0.3 .+ 0.2 .* randn(n)

        # Inject NaNs
        for idx in 1:50:n
            u[idx] = NaN
            v[idx] = NaN
            w[idx] = NaN
        end

        hd = DimArray(hcat(u, v, w), (t, vars))
        ld = DimArray(zeros(5, 1), (Ti(1:5), Var([:dummy])))

        dr = PEDDY.WindDoubleRotation(block_duration_minutes=1.0)
        PEDDY.rotate!(dr, hd, ld)

        # Means of rotated v,w (ignoring NaNs) should be ~0
        v_rot = hd[Var=At(:Uy)]
        w_rot = hd[Var=At(:Uz)]
        @test isapprox(mean_skipnan(v_rot), 0.0; atol=1e-6)
        @test isapprox(mean_skipnan(w_rot), 0.0; atol=1e-6)

        # NaN positions preserved
        for idx in 1:50:n
            @test isnan(hd[Ti=idx, Var=At(:Ux)])
            @test isnan(hd[Ti=idx, Var=At(:Uy)])
            @test isnan(hd[Ti=idx, Var=At(:Uz)])
        end
    end
end
