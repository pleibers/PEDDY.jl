using Test
using Peddy
using Dates
using DimensionalData

# A dummy sensor matching the columns available in examples/data.dat
struct DummyHFReadSensor <: Peddy.AbstractSensor end
Peddy.needs_data_cols(::DummyHFReadSensor) = (
    :diag_csat, :diag_gas, :Ux, :Uy, :Uz, :Ts, :H2O, :P
)
Peddy.has_variables(::DummyHFReadSensor) = (:Ux, :Uy, :Uz, :Ts, :H2O, :P)

@testset "IO: DotDatDirectory reads HF example" begin
    # Create a temporary directory and write a small subset of the example file
    mktempdir() do tmpdir
        src = joinpath(@__DIR__, "..", "examples", "data.dat")
        dst = joinpath(tmpdir, "data.dat")

        # Copy only the header + first 50 lines for a small test file
        open(src, "r") do fin
            open(dst, "w") do fout
                count = 0
                for ln in eachline(fin)
                    write(fout, ln * "\n")
                    count += 1
                    if count >= 51  # header + 50 rows
                        break
                    end
                end
            end
        end

        # FileOptions matching the example file (tab-delimited, DateTime with milliseconds)
        fo = Peddy.FileOptions(
            header=1,
            delimiter="\t",
            comment="#",
            timestamp_column=:TIMESTAMP,
            time_format=DateFormat("yyyy-mm-dd HH:MM:SS.s"),
        )

        input = Peddy.DotDatDirectory(
            directory=tmpdir,
            high_frequency_file_glob="data",  # extension .dat is appended automatically
            high_frequency_file_options=fo,
            low_frequency_file_glob=nothing,
            low_frequency_file_options=nothing,
        )

        sensor = DummyHFReadSensor()
        needed = collect(Peddy.needs_data_cols(sensor))

        hf, lf = Peddy.read_data(input, sensor)
        @test lf === nothing
        @test hf isa DimArray

        # Basic shape and column checks
        @test size(hf, 2) == length(needed)
        # Ensure we can index by each required variable name
        for v in needed
            # Will throw if the variable is missing
            @test size(hf[Var=At(v)])[1] == size(hf, 1)
        end

        # Ensure the number of rows equals the number of data lines we wrote (50)
        @test size(hf, 1) == 50
    end
end
