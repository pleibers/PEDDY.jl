using Test
using Peddy
using Dates

# Mock logger for testing
struct MockLogger <: AbstractProcessingLogger
    events::Vector{Any}
    MockLogger() = new([])
end

import Peddy: log_event!
function log_event!(l::MockLogger, stage::Symbol, category::Symbol; kwargs...)
    push!(l.events, (stage=stage, category=category, kwargs=Dict(kwargs)))
end

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

    # --- Constructor tests ---
    @testset "Constructor" begin
        @test_throws ArgumentError MakeContinuous(step_size_ms=0)
        @test_throws ArgumentError MakeContinuous(step_size_ms=-1)
        @test_throws ArgumentError MakeContinuous(max_gap_minutes=0.0)
        @test_throws ArgumentError MakeContinuous(max_gap_minutes=-1.0)
        
        mc100 = MakeContinuous(step_size_ms=100, max_gap_minutes=10.0)
        @test mc100.step_size_ms == 100
        @test mc100.max_gap_minutes == 10.0
    end

    # --- Edge cases and logic tests ---
    @testset "Edge Cases" begin
        # Empty DimArray
        empty_hf = DimArray(Matrix{Float64}(undef, 0, 2), (Ti(DateTime[]), Var(vars)))
        @test make_continuous!(mc, empty_hf, nothing) === empty_hf

        # Single row
        single_hf = DimArray(fill(1.0, 1, 2), (Ti([t0]), Var(vars)))
        @test make_continuous!(mc, single_hf, nothing) === single_hf

        # No gaps
        no_gap_times = [t0 + Millisecond(50)*i for i in 0:4]
        no_gap_hf = DimArray(fill(1.0, 5, 2), (Ti(no_gap_times), Var(vars)))
        res_no_gap = make_continuous!(mc, no_gap_hf, nothing)
        @test length(dims(res_no_gap, Ti)) == 5
        @test res_no_gap == no_gap_hf

        # Gap of exactly 2 * step (should insert 1 point)
        gap2_times = [t0, t0 + Millisecond(100)]
        gap2_hf = DimArray(fill(1.0, 2, 2), (Ti(gap2_times), Var(vars)))
        res_gap2 = make_continuous!(mc, gap2_hf, nothing)
        @test length(dims(res_gap2, Ti)) == 3
        @test dims(res_gap2, Ti)[2] == t0 + Millisecond(50)
        @test all(isnan, res_gap2[Ti=At(t0 + Millisecond(50))])

        # Multiple gaps
        multi_gap_times = [t0, t0 + Millisecond(50), t0 + Millisecond(150), t0 + Millisecond(300)]
        # Gaps: 
        # 1. t0 + 50 to t0 + 150 (100ms gap -> 1 insertion at t0+100)
        # 2. t0 + 150 to t0 + 300 (150ms gap -> 2 insertions at t0+200, t0+250)
        multi_gap_hf = DimArray(fill(2.0, 4, 2), (Ti(multi_gap_times), Var(vars)))
        res_multi = make_continuous!(mc, multi_gap_hf, nothing)
        @test length(dims(res_multi, Ti)) == 7
        @test all(isnan, res_multi[Ti=At(t0 + Millisecond(100))])
        @test all(isnan, res_multi[Ti=At(t0 + Millisecond(200))])
        @test all(isnan, res_multi[Ti=At(t0 + Millisecond(250))])
        @test res_multi[Ti=At(t0)][1] == 2.0
    end

    # --- Logging tests ---
    @testset "Logging" begin
        logger = MockLogger()
        gap_times = [t0, t0 + Millisecond(150)] # 2 insertions
        gap_hf = DimArray(fill(1.0, 2, 2), (Ti(gap_times), Var(vars)))
        
        make_continuous!(mc, gap_hf, nothing; logger=logger)
        @test length(logger.events) == 1
        ev = logger.events[1]
        @test ev.stage == :make_continuous
        @test ev.category == :time_gap
        @test ev.kwargs[:filled] == true
        @test ev.kwargs[:inserted_points] == 2

        # Large gap logging
        logger_large = MockLogger()
        large_gap_times = [t0, t0 + Minute(10)]
        large_gap_hf = DimArray(fill(1.0, 2, 2), (Ti(large_gap_times), Var(vars)))
        make_continuous!(mc, large_gap_hf, nothing; logger=logger_large)
        @test length(logger_large.events) == 1
        @test logger_large.events[1].kwargs[:filled] == false
    end
end
