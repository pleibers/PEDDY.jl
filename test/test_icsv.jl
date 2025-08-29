using Test
using Dates
using DimensionalData
using PEDDY

# Helper: read the generated file and extract sections/lines
function _read_icsv_lines(path::AbstractString)
    @assert isfile(path) "Expected iCSV file at $(path)"
    return readlines(path)
end

function _find_line(lines::Vector{String}, pat::AbstractString)
    for (i, l) in pairs(lines)
        if occursin(pat, l)
            return i
        end
    end
    return nothing
end

@testset "ICSVOutput basic writing" begin
    # --- Test 1: Default variable metadata, DateTime time index ---
    n = 10
    vars = [:Ux, :Uy, :Uz, :Ts]
    start = DateTime(2024, 1, 1, 0, 0, 0)
    times = [start + Dates.Second(i-1) for i in 1:n]
    data = rand(n, length(vars))
    arr = DimArray(data, (Ti(times), Var(vars)))

    tmp = mktempdir()
    base = joinpath(tmp, "icsv_test")
    out = ICSVOutput(base_filename = base,
                     location = PEDDY.InteroperableCSV.Loc(47.0, 8.0, 1000.0))

    # Should write only HF file
    write_data(out, arr, nothing)

    path_hf = base * "_hf.icsv"
    @test isfile(path_hf)

    lines = _read_icsv_lines(path_hf)

    # First line must be iCSV header with version and UTF-8
    @test !isempty(lines)
    @test occursin(r"^# iCSV \S+ UTF-8$", lines[1])

    # Required section headers must exist (order not strictly enforced here)
    idx_meta = _find_line(lines, "# [METADATA]")
    idx_fields = _find_line(lines, "# [FIELDS]")
    idx_data = _find_line(lines, "# [DATA]")
    @test idx_meta !== nothing
    @test idx_fields !== nothing
    @test idx_data !== nothing

    # Metadata: field_delimiter should be present and match ',' by default
    has_fd = any(l -> occursin(r"^#\s*field_delimiter\s*=\s*,", l), lines)
    @test has_fd

    # Fields: ensure 'fields' lists timestamp first, then our variables separated by delimiter
    fields_line_idx = findfirst(l -> occursin(r"^#\s*fields\s*=", l), lines)
    @test fields_line_idx !== nothing
    fields_line = lines[fields_line_idx]
    # Extract after '=' and parse values (allow optional spaces)
    fields_rhs = split(strip(split(fields_line, "=", limit = 2)[2]), ",")
    fields_vals = strip.(fields_rhs)
    @test fields_vals[1] == "timestamp"
    @test sort(fields_vals[2:end]) == sort(string.(vars))

    # Data: there must be exactly n data rows after the [DATA] header (skip comments/blank)
    data_rows = [l for l in lines[(idx_data+1):end] if !startswith(l, "#") && !isempty(strip(l))]
    @test length(data_rows) == n
    # Column count in each row equals 1 + length(vars)
    for row in data_rows
        cols = split(row, ",")
        @test length(cols) == 1 + length(vars)
    end

    # --- Test 2: Custom metadata, non-Date/DateTime time index emits warning and still writes ---
    n2 = 7
    vars2 = [:A, :B]
    times2 = collect(1:n2)  # Int time index
    data2 = rand(n2, length(vars2))
    arr2 = DimArray(data2, (Ti(times2), Var(vars2)))

    custom_fields = Dict{Symbol, VariableMetadata}(
        :timestamp => VariableMetadata(standard_name = "timestamp", long_name = "Timestamp", unit = "", description = "Int ticks"),
        :A => VariableMetadata(standard_name = "A_std", long_name = "A var", unit = "m", description = "desc A"),
        :B => VariableMetadata(standard_name = "B_std", long_name = "B var", unit = "s", description = "desc B"),
    )

    base2 = joinpath(tmp, "icsv_custom")
    out2 = ICSVOutput(base_filename = base2,
                      location = PEDDY.InteroperableCSV.Loc(46.5, 7.5, 500.0),
                      fields = custom_fields,
                      field_delimiter = ";")

    # Expect a warning about non-Date/DateTime time dimension
    @test_logs (:warn, r"ICSVOutput: time dimension is not of type Date or DateTime") begin
        write_data(out2, arr2, nothing)
    end

    path_hf2 = base2 * "_hf.icsv"
    @test isfile(path_hf2)
    lines2 = _read_icsv_lines(path_hf2)

    # Check field_delimiter metadata reflects ';'
    has_fd2 = any(l -> occursin(r"^#\s*field_delimiter\s*=\s*;", l), lines2)
    @test has_fd2

    # Fields mapping with custom variables
    fields_line_idx2 = findfirst(l -> occursin(r"^#\s*fields\s*=", l), lines2)
    @test fields_line_idx2 !== nothing
    fields_line2 = lines2[fields_line_idx2]
    fields_rhs2 = split(strip(split(fields_line2, "=", limit = 2)[2]), ";")
    fields_vals2 = strip.(fields_rhs2)
    @test fields_vals2[1] == "timestamp"
    @test sort(fields_vals2[2:end]) == sort(string.(vars2))

    # Units line should reflect our custom units and use same delimiter
    units_line_idx2 = findfirst(l -> occursin(r"^#\s*units\s*=", l), lines2)
    @test units_line_idx2 !== nothing
    units_line2 = lines2[units_line_idx2]
    units_rhs2 = split(strip(split(units_line2, "=", limit = 2)[2]), ";")
    units_vals2 = strip.(units_rhs2)
    @test units_vals2[1] == ""  # timestamp has empty unit first
    @test sort(units_vals2[2:end]) == sort(["m","s"])  

    # Data: correct number of rows and columns with ';' delimiter
    idx_data2 = _find_line(lines2, "# [DATA]")
    @test idx_data2 !== nothing
    data_rows2 = [l for l in lines2[(idx_data2+1):end] if !startswith(l, "#") && !isempty(strip(l))]
    @test length(data_rows2) == n2
    for row in data_rows2
        cols = split(row, ";")
        @test length(cols) == 1 + length(vars2)
    end
end
