using Test
using Peddy
using Dates

@testset "Logging" begin
    @testset "log_event! basics" begin
        logger = Peddy.ProcessingLogger()
        t0 = DateTime(2020, 1, 1, 0, 0, 0)
        t1 = t0 + Millisecond(1500)

        Peddy.log_event!(logger, :qc, :bounds; variable=:Ux, start_time=t0, end_time=t1, foo=1)

        @test length(logger.entries) == 1
        entry = logger.entries[1]
        @test entry.stage == :qc
        @test entry.category == :bounds
        @test entry.variable == :Ux
        @test entry.start_time == t0
        @test entry.end_time == t1
        @test entry.details[:foo] == 1
        @test entry.details[:duration_seconds] == 1.5
    end

    @testset "record_stage_time! accumulates" begin
        logger = Peddy.ProcessingLogger()
        Peddy.record_stage_time!(logger, :qc, 1)
        Peddy.record_stage_time!(logger, :qc, 2.5)
        Peddy.record_stage_time!(logger, :despike, 3)

        @test logger.stage_durations[:qc] == 3.5
        @test logger.stage_durations[:despike] == 3.0
    end

    @testset "log_index_runs! creates run entries" begin
        logger = Peddy.ProcessingLogger()
        t0 = DateTime(2020, 1, 1, 0, 0, 0)
        timestamps = [t0 + Second(i - 1) for i in 1:10]

        indices = [2, 3, 4, 7, 9, 10]
        Peddy.log_index_runs!(logger, :qc, :flagged, :Ux, timestamps, indices)

        @test length(logger.entries) == 3
        @test logger.entries[1].start_time == timestamps[2]
        @test logger.entries[1].end_time == timestamps[4]
        @test logger.entries[2].start_time == timestamps[7]
        @test logger.entries[2].end_time == timestamps[7]
        @test logger.entries[3].start_time == timestamps[9]
        @test logger.entries[3].end_time == timestamps[10]
    end

    @testset "log_index_runs! include_run_length" begin
        logger = Peddy.ProcessingLogger()
        t0 = DateTime(2020, 1, 1, 0, 0, 0)
        timestamps = [t0 + Second(i - 1) for i in 1:6]

        indices = [1, 2, 4, 5, 6]
        Peddy.log_index_runs!(logger, :despike, :spikes, :Uz, timestamps, indices; include_run_length=true)

        @test length(logger.entries) == 2
        @test logger.entries[1].details[:samples_in_run] == 2
        @test logger.entries[2].details[:samples_in_run] == 3
    end

    @testset "log_mask_runs! creates run entries" begin
        logger = Peddy.ProcessingLogger()
        t0 = DateTime(2020, 1, 1, 0, 0, 0)
        timestamps = [t0 + Second(i - 1) for i in 1:8]

        mask = Bool[false, true, true, false, true, false, true, true]
        Peddy.log_mask_runs!(logger, :qc, :mask, :Ts, timestamps, mask)

        @test length(logger.entries) == 3
        @test logger.entries[1].start_time == timestamps[2]
        @test logger.entries[1].end_time == timestamps[3]
        @test logger.entries[2].start_time == timestamps[5]
        @test logger.entries[2].end_time == timestamps[5]
        @test logger.entries[3].start_time == timestamps[7]
        @test logger.entries[3].end_time == timestamps[8]
    end

    @testset "write_processing_log writes header and entries" begin
        logger = Peddy.ProcessingLogger()
        t0 = DateTime(2020, 1, 1, 0, 0, 0)
        t1 = t0 + Second(2)

        Peddy.log_event!(logger, :qc, :bounds; variable=:Ux, start_time=t0, end_time=t1, foo=1)
        Peddy.record_stage_time!(logger, :qc, 3.0)

        path, io = mktemp()
        close(io)
        try
            Peddy.write_processing_log(logger, path)
            lines = readlines(path)

            @test lines[1] == "stage,category,variable,start_timestamp,end_timestamp,duration_seconds,details"
            @test length(lines) == 3
            @test occursin("qc,bounds,Ux,", lines[2])
            @test occursin(",foo=1", lines[2])
            @test occursin("qc,runtime,", lines[3])
            @test occursin(",3.0,", lines[3])
        finally
            rm(path; force=true)
        end
    end

    @testset "NoOpLogger no-ops" begin
        noop = Peddy.NoOpLogger()
        Peddy.log_event!(noop, :qc, :bounds; variable=:Ux)
        Peddy.record_stage_time!(noop, :qc, 1)
        Peddy.write_processing_log(noop, "does_not_matter.csv")

        t0 = DateTime(2020, 1, 1, 0, 0, 0)
        timestamps = [t0 + Second(i - 1) for i in 1:5]
        Peddy.log_index_runs!(noop, :qc, :flagged, :Ux, timestamps, [1, 2, 3])
        Peddy.log_mask_runs!(noop, :qc, :flagged, :Ux, timestamps, trues(5))

        @test true
    end

    @testset "Type hierarchy" begin
        @test Peddy.ProcessingLogger <: Peddy.AbstractProcessingLogger
        @test Peddy.NoOpLogger <: Peddy.AbstractProcessingLogger
        @test Peddy.ProcessingLogger() isa Peddy.AbstractProcessingLogger
        @test Peddy.NoOpLogger() isa Peddy.AbstractProcessingLogger
    end
end
