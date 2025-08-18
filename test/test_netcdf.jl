using Test
using Dates
using DimensionalData
using NCDatasets
using PEDDY

@testset "NetCDFOutput basic writing" begin
    # --- Test 1: Write only HF file ---
    n = 12
    vars = [:Ux, :Uy, :Uz, :Ts]
    start = DateTime(2024, 1, 1, 0, 0, 0)
    times = [start + Dates.Second(i-1) for i in 1:n]
    data = rand(n, length(vars))
    # create union-typed backing array to allow missing
    backing = Matrix{Union{Missing, Float64}}(undef, size(data, 1), size(data, 2))
    for j in axes(data, 2)
        for i in axes(data, 1)
            backing[i, j] = data[i, j]
        end
    end
    arr = DimArray(backing, (Ti(times), Var(vars)))
    # introduce a missing value
    arr[Ti=At(times[5]), Var=At(:Ux)] = missing

    tmp = mktempdir()
    base = joinpath(tmp, "netcdf_test")
    out = NetCDFOutput(base_filename = base,
                       location = LocationMetadata(latitude=47.0, longitude=8.0, elevation=1000.0))

    write_data(out, arr, nothing)

    path_hf = base * "_hf.nc"
    @test isfile(path_hf)

    ds = NCDatasets.NCDataset(path_hf, "r")
    try
        # Global attrs
        @test haskey(ds.attrib, "Conventions")
        @test ds.attrib["Conventions"] == "CF-1.6"
        @test haskey(ds.attrib, "title")

        # Dimensions and coordinates
        @test haskey(ds.dim, "time")
        @test ds.dim["time"] == n
        @test haskey(ds, "time")
        @test haskey(ds, "latitude")
        @test haskey(ds, "longitude")

        # Time units attribute present
        @test haskey(ds["time"].attrib, "units")
        @test occursin("since", String(ds["time"].attrib["units"]))

        # A sample data var
        @test all(v -> haskey(ds, String(v)), vars)
        ux = ds["Ux"]
        # Attributes from metadata
        @test haskey(ux.attrib, "standard_name")
        @test haskey(ux.attrib, "units")
        @test haskey(ux.attrib, "_FillValue")
        fv = ux.attrib["_FillValue"]
        vals = ux[:]
        # accept either missing mapping or explicit fill value
        @test any(x -> (ismissing(x) || x == fv), vals)
    finally
        close(ds)
    end

    # --- Test 2: Also write LF file and custom metadata ---
    n2 = 5
    vars2 = [:A, :B]
    times2 = [Date(2024, 1, i) for i in 1:n2]
    data2 = rand(n2, length(vars2))
    arr2 = DimArray(data2, (Ti(times2), Var(vars2)))

    custom_fields = Dict{Symbol, VariableMetadata}(
        :A => VariableMetadata(standard_name = "var_A", long_name = "Variable A", unit = "m s-1", description = "desc A"),
        :B => VariableMetadata(standard_name = "var_B", long_name = "Variable B", unit = "K", description = "desc B"),
    )

    base2 = joinpath(tmp, "netcdf_custom")
    out2 = NetCDFOutput(base_filename = base2,
                        location = LocationMetadata(latitude=46.5, longitude=7.5, elevation=500.0),
                        fields = custom_fields,
                        fill_value = -7777.0)

    write_data(out2, arr2, arr2)  # write both HF and LF

    path_hf2 = base2 * "_hf.nc"
    path_lf2 = base2 * "_lf.nc"
    @test isfile(path_hf2)
    @test isfile(path_lf2)

    ds2 = NCDatasets.NCDataset(path_lf2, "r")
    try
        # Check variable attributes match custom metadata
        @test haskey(ds2, "A")
        @test haskey(ds2, "B")
        @test ds2["A"].attrib["standard_name"] == "var_A"
        @test ds2["A"].attrib["units"] == "m s-1"
        @test ds2["B"].attrib["standard_name"] == "var_B"
        @test ds2["B"].attrib["units"] == "K"
        # Fill value propagated
        @test ds2["A"].attrib["_FillValue"] == -7777.0
    finally
        close(ds2)
    end
end
