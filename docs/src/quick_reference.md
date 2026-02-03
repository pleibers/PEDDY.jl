# Quick Reference

## Installation

```julia
using Pkg
Pkg.add("Peddy")
```

Or for development:

```bash
julia +1.11 --project=.
julia> using Pkg; Pkg.instantiate()
```

## Minimal Example

```julia
using Peddy
using DimensionalData
using Dates

# Create data
times = DateTime(2024, 1, 1):Millisecond(50):DateTime(2024, 1, 1, 0, 1, 0)
vars = [:Ux, :Uy, :Uz, :Ts, :diag_sonic]
data = hcat(
    sin.(range(0, 1, length=length(times))),
    cos.(range(0, 1, length=length(times))),
    0.1 .* randn(length(times)),
    20 .+ 0.01 .* randn(length(times)),
    zeros(length(times))
)
hf = DimArray(data, (Var(vars), Ti(times)))

# Configure pipeline
sensor = CSAT3()
qc = PhysicsBoundsCheck()
desp = SimpleSigmundDespiking()
gap = GeneralInterpolation()
out = MemoryOutput()

pipeline = EddyPipeline(
    sensor=sensor,
    quality_control=qc,
    despiking=desp,
    gap_filling=gap,
    output=out
)

# Run
process!(pipeline, hf, nothing)

# Get results
hf_res, lf_res = Peddy.get_results(out)
```

## Common Configurations

### Minimal Processing (QC only)

```julia
pipeline = EddyPipeline(
    sensor=CSAT3(),
    quality_control=PhysicsBoundsCheck(),
    output=MemoryOutput()
)
```

### Standard Processing

```julia
pipeline = EddyPipeline(
    sensor=CSAT3(),
    quality_control=PhysicsBoundsCheck(),
    despiking=SimpleSigmundDespiking(),
    gap_filling=GeneralInterpolation(),
    output=ICSVOutput("/path/to/output")
)
```

### Full Processing with MRD

```julia
pipeline = EddyPipeline(
    sensor=IRGASON(),
    quality_control=PhysicsBoundsCheck(),
    gas_analyzer=H2OCalibration(),
    despiking=SimpleSigmundDespiking(),
    gap_filling=GeneralInterpolation(),
    double_rotation=WindDoubleRotation(),
    mrd=OrthogonalMRD(),
    output=NetCDFOutput("/path/to/output")
)
```

### With Logging

```julia
logger = ProcessingLogger()

pipeline = EddyPipeline(
    sensor=CSAT3(),
    quality_control=PhysicsBoundsCheck(),
    output=MemoryOutput(),
    logger=logger
)

process!(pipeline, hf, lf)
write_processing_log(logger, "/path/to/log.csv")
```

## Data Access Patterns

### Get Variable

```julia
ux = hf[Var=At(:Ux)]
```

### Get Time Slice

```julia
t0 = DateTime(2024, 1, 1, 12, 0, 0)
slice = hf[Ti=At(t0)]
```

### Get Time Range

```julia
t_start = DateTime(2024, 1, 1, 0, 0, 0)
t_end = DateTime(2024, 1, 1, 1, 0, 0)
subset = hf[Ti=Between(t_start, t_end)]
```

### Modify In-Place

```julia
ux = @view hf[Var=At(:Ux)]
ux[ux .> 100] .= NaN
```

### Get Statistics

```julia
ux = hf[Var=At(:Ux)]
mean_ux = Peddy.mean_skipnan(ux)
std_ux = std(skipmissing(ux))
```

## Pipeline Steps Cheat Sheet

| Step | Type | Purpose | Example |
|------|------|---------|---------|
| Quality Control | `AbstractQC` | Remove physically impossible values | `PhysicsBoundsCheck()` |
| Gas Analyzer | `AbstractGasAnalyzer` | Correct H₂O measurements | `H2OCalibration()` |
| Despiking | `AbstractDespiking` | Remove spikes | `SimpleSigmundDespiking()` |
| Make Continuous | `AbstractMakeContinuous` | Insert missing timestamps | `MakeContinuous()` |
| Gap Filling | `AbstractGapFilling` | Interpolate small gaps | `GeneralInterpolation()` |
| Double Rotation | `AbstractDoubleRotation` | Align with mean wind | `WindDoubleRotation()` |
| MRD | `AbstractMRD` | Multiresolution decomposition | `OrthogonalMRD()` |
| Output | `AbstractOutput` | Write results | `ICSVOutput()`, `NetCDFOutput()` |

## Quality Control

### Default Bounds

```julia
qc = PhysicsBoundsCheck()
# Ux, Uy: [-100, 100] m/s
# Uz: [-50, 50] m/s
# Ts: [-50, 50] °C
# CO2: [0, ∞] ppm
# H2O: [0, ∞] mmol/mol
# T: [-50, 50] °C
# P: [0, ∞] Pa
```

### Custom Bounds

```julia
qc = PhysicsBoundsCheck(
    Ux=Limit(-50, 50),
    Uy=Limit(-50, 50),
    Uz=Limit(-30, 30),
    Ts=Limit(-40, 50)
)
```

## Despiking

### Default Configuration

```julia
desp = SimpleSigmundDespiking()
# window_minutes=5.0
# spike_threshold=6.0 for all variables
```

### Custom Groups

```julia
wind = VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=6.0)
temp = VariableGroup("Sonic T", [:Ts], spike_threshold=6.0)
gas = VariableGroup("Gas", [:H2O], spike_threshold=5.0)

desp = SimpleSigmundDespiking(
    window_minutes=5.0,
    variable_groups=[wind, temp, gas]
)
```

## Gap Filling

### Linear Interpolation (default)

```julia
gap = GeneralInterpolation()
# max_gap_size=10
# method=Linear()
```

### Cubic Spline

```julia
gap = GeneralInterpolation(
    max_gap_size=10,
    method=Cubic()
)
```

### Custom Variables

```julia
gap = GeneralInterpolation(
    variables=[:Ux, :Uy, :Uz, :Ts],
    max_gap_size=20
)
```

## Double Rotation

### Default (30-minute blocks)

```julia
rot = WindDoubleRotation()
```

### Custom Block Size

```julia
rot = WindDoubleRotation(block_duration_minutes=15.0)
```

## MRD

### Default Configuration

```julia
mrd = OrthogonalMRD()
# M=11 (2^11 = 2048 samples per block)
# shift=256 (samples between blocks)
# a=:Uz, b=:Ts
```

### Custom Configuration

```julia
mrd = OrthogonalMRD(
    M=10,
    shift=128,
    a=:Uz,
    b=:Ts,
    gap_threshold_seconds=10.0,
    normalize=false,
    regular_grid=false
)

decompose!(mrd, hf, lf)
results = get_mrd_results(mrd)

if results !== nothing
    @show results.scales
    @show size(results.mrd)
    plot(results)
end
```

## Input/Output

### Read from .dat Files

```julia
input = DotDatDirectory(
    directory="/path/to/data",
    high_frequency_file_glob="*fast*",
    high_frequency_file_options=FileOptions(
        timestamp_column=:TIMESTAMP,
        time_format=dateformat"yyyy-mm-dd HH:MM:SS.s"
    )
)

hf, lf = read_data(input, CSAT3())
```

### Write to Memory

```julia
out = MemoryOutput()
process!(pipeline, hf, lf)
hf_res, lf_res = Peddy.get_results(out)
```

### Write to CSV

```julia
out = ICSVOutput("/path/to/output")
```

### Write to NetCDF

```julia
out = NetCDFOutput("/path/to/output")
```

### Write to Multiple Formats

```julia
out = OutputSplitter(
    ICSVOutput("/path/csv"),
    NetCDFOutput("/path/nc")
)
```

## Sensors

### CSAT3

```julia
sensor = CSAT3()
# Requires: Ux, Uy, Uz, Ts, diag_sonic
```

### CSAT3B

```julia
sensor = CSAT3B()
# Requires: Ux, Uy, Uz, Ts, diag_sonic
```

### IRGASON

```julia
sensor = IRGASON()
# Requires: Ux, Uy, Uz, Ts, CO2, H2O, diag_sonic, diag_irga
```

### LICOR with Calibration

```julia
sensor = LICOR(
    calibration_coefficients=H2OCalibrationCoefficients(
        A=4.82004e3,
        B=3.79290e6,
        C=-1.15477e8,
        H2O_Zero=0.7087,
        H20_Span=0.9885
    )
)
```

## Logging

### Enable Logging

```julia
logger = ProcessingLogger()

pipeline = EddyPipeline(
    sensor=sensor,
    output=output,
    logger=logger
)

process!(pipeline, hf, lf)
write_processing_log(logger, "/path/to/log.csv")
```

### Disable Logging (zero overhead)

```julia
logger = NoOpLogger()

pipeline = EddyPipeline(
    sensor=sensor,
    output=output,
    logger=logger
)
```

## Debugging

### Check Data Validity

```julia
check_data(hf, lf, sensor)
```

### Run Steps Manually

```julia
quality_control!(qc, hf, lf, sensor)
despike!(desp, hf, lf)
fill_gaps!(gap, hf, lf)
rotate!(rot, hf, lf)
decompose!(mrd, hf, lf)
write_data(out, hf, lf)
```

### Enable Debug Logging

```julia
using Logging

logger = ConsoleLogger(stderr, Logging.Debug)
with_logger(logger) do
    process!(pipeline, hf, lf)
end
```

### Inspect Intermediate Results

```julia
n_nan_before = count(isnan, hf)
quality_control!(qc, hf, lf, sensor)
n_nan_after = count(isnan, hf)
@show n_nan_after - n_nan_before
```

## Common Errors & Solutions

| Error | Solution |
|-------|----------|
| "High frequency data must have a Var dimension" | Use `DimArray` with `Var` and `Ti` dimensions |
| "Var dimension must have a Ux variable" | Check sensor requirements with `needs_data_cols(sensor)` |
| "Variable X not found" | Ensure variable exists in data before using it |
| "Not enough samples" | Provide more data or reduce block sizes |
| "Block size calculation failed" | Data too short for requested processing |

## Performance Tips

1. **Use views for in-place modification**: `@view hf[Var=At(:Ux)]`
2. **Disable expensive steps if not needed**: Set to `nothing`
3. **Use `NoOpLogger` for production**: Zero overhead
4. **Process in chunks for large datasets**: Split by time period
5. **Use appropriate interpolation method**: `Linear()` is fastest, `Cubic()` is most accurate

## File Formats

### CSV Output Structure

```
timestamp, Ux, Uy, Uz, Ts, ...
2024-01-01T00:00:00, 1.23, 0.45, -0.12, 20.5, ...
2024-01-01T00:00:00.050, 1.25, 0.43, -0.11, 20.6, ...
```

### NetCDF Output Structure

```
Dimensions:
  time: 1000000
  variables: 8

Variables:
  time (time): datetime64
  Ux (variables, time): float64
  Uy (variables, time): float64
  ...
```

## Useful Functions

```julia
# Mean ignoring NaN
Peddy.mean_skipnan(arr)

# Get results from MemoryOutput
hf_res, lf_res = Peddy.get_results(output)

# Get MRD results
results = get_mrd_results(mrd)

# Check if logging enabled
is_logging_enabled(logger)

# Get variable metadata
meta = metadata_for(:Ux)
```

## Resources

- [Full API Reference](api.md)
- [Tutorial](index.md)
- [Extension Guide](extending.md)
- [Troubleshooting](troubleshooting.md)
- [Data Format Guide](data_format.md)
- [Sensor Guide](sensors.md)
