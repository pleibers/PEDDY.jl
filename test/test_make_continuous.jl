using Test
using PEDDY
using Dates

@testset "MakeContinuous" begin
    # Construct simple high-frequency DimArray with a gap
    step = Millisecond(50)
    t0 = DateTime(2025,1,1,0,0,0,0)
    times = [t0 + step*i for i in 0:9]  # 10 points
    # Remove some times to create a gap of 5 * step
    deleteat!(times, 6:8)  # create 3 missing interior points
    vars = [:Ux, :Uy]
    data = fill(1.0, length(times), length(vars))
    hf = DimArray(data, (Ti(times), Var(vars)))

    mc = MakeContinuous(step_size_ms=50, max_gap_minutes=1.0)
    new_hf = make_continuous!(mc, hf, nothing)

    @test length(dims(new_hf, Ti)) == 10  # restored original expected length
    # The inserted rows should be NaN
    inserted_times = sort([t0 + step*i for i in 0:9 if (t0 + step*i) ∉ times])
    for ts in inserted_times
        row = new_hf[Ti=At(ts)]
        @test all(isnan, row)
    end

    # Large gap not filled
    t_big = [t0, t0 + step, t0 + Minute(10)]
    data_big = fill(2.0, length(t_big), length(vars))
    hf_big = DimArray(data_big, (Ti(t_big), Var(vars)))
    new_big = make_continuous!(mc, hf_big, nothing)
    @test length(dims(new_big, Ti)) == length(t_big)  # unchanged
end
