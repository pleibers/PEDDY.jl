# Troubleshooting & FAQ

## Common Issues

### Data Loading

#### Issue: "High frequency data must have a Var dimension"

**Cause:** Your data doesn't have the required `Var` dimension from DimensionalData.jl.

**Solution:** Ensure your data is a `DimArray` with proper dimensions:
```julia
using DimensionalData

# Correct format
hf = DimArray(
    data_matrix,
    (Var([:Ux, :Uy, :Uz, :Ts]), Ti(times))
)

# Wrong format (will fail)
hf = data_matrix  # Just a matrix
```

#### Issue: "Var dimension must have a Ux variable"

**Cause:** Missing required variables for the selected sensor.

**Solution:** Check what variables your sensor needs:
```julia
sensor = CSAT3()
required = PEDDY.needs_data_cols(sensor)
@show required  # Shows [:Ux, :Uy, :Uz, :Ts, :diag_sonic]
```

Ensure your data includes all required variables.

#### Issue: Time format parsing fails

**Cause:** Incorrect `time_format` specification in `FileOptions`.

**Solution:** Match the format exactly:
```julia
# For "2024-01-01 12:30:45.123"
FileOptions(time_format=dateformat"yyyy-mm-dd HH:MM:SS.s")

# For "2024-01-01 12:30:45"
FileOptions(time_format=dateformat"yyyy-mm-dd HH:MM:SS")

# For "01/01/2024 12:30"
FileOptions(time_format=dateformat"mm/dd/yyyy HH:MM")
```

### Pipeline Execution

#### Issue: "Variable X not found in high frequency data"

**Cause:** A pipeline step references a variable that doesn't exist in your data.

**Solution:** Check available variables:
```julia
vars = val(dims(high_frequency_data, Var))
@show vars

# Then configure steps only for variables you have
desp = SimpleSigmundDespiking(
    variable_groups=[
        VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=6.0)
    ]
)
```

#### Issue: Pipeline runs but produces all NaN results

**Cause:** Quality control or despiking is too aggressive, removing all data.

**Solution:** Relax thresholds or disable the step:
```julia
# Option 1: Relax QC bounds
qc = PhysicsBoundsCheck(
    Ux=Limit(-200, 200),  # Wider range
    Uy=Limit(-200, 200),
    Uz=Limit(-100, 100)
)

# Option 2: Disable QC
pipeline = EddyPipeline(
    sensor=sensor,
    quality_control=nothing,  # Skip QC
    despiking=desp,
    output=output
)

# Option 3: Relax despiking threshold
desp = SimpleSigmundDespiking(
    variable_groups=[
        VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=10.0)  # Higher = less aggressive
    ]
)
```

#### Issue: "Block size calculation failed" or "Not enough samples"

**Cause:** Data is too short for the requested processing.

**Solution:** Ensure sufficient data:
```julia
# For double rotation with 30-minute blocks, need at least 30 minutes of data
# For MRD with M=11, need at least 2^11 = 2048 samples

# Check your data length
n_samples = length(dims(high_frequency_data, Ti))
duration_minutes = n_samples * 50 / 1000 / 60  # Assuming 50 ms sampling

# Adjust parameters for short data
rot = WindDoubleRotation(block_duration_minutes=5.0)  # Shorter blocks
mrd = OrthogonalMRD(M=8)  # Smaller maximum scale
```

### Quality Control

#### Issue: Too many points marked as invalid

**Cause:** Physical bounds are too restrictive for your site conditions.

**Solution:** Inspect your data and adjust bounds:
```julia
# Check data ranges
ux = high_frequency_data[Var=At(:Ux)]
@show extrema(skipmissing(ux))

# Set bounds based on your data
qc = PhysicsBoundsCheck(
    Ux=Limit(-50, 50),  # Adjust to your site
    Uy=Limit(-50, 50),
    Uz=Limit(-30, 30),
    Ts=Limit(-30, 50)
)
```

#### Issue: Sensor diagnostics always fail

**Cause:** Diagnostic field has non-zero values (sensor issues).

**Solution:** Either fix the sensor or disable diagnostic checks:
```julia
# Option 1: Only check physical bounds, not diagnostics
qc = OnlyDiagnostics()  # This only checks diagnostics
# Actually, use PhysicsBoundsCheck instead:
qc = PhysicsBoundsCheck()

# Option 2: Manually clean diagnostic field
high_frequency_data[Var=At(:diag_sonic)] .= 0.0
```

### Despiking

#### Issue: Despiking removes too much data

**Cause:** Threshold is too low (more aggressive).

**Solution:** Increase the threshold:
```julia
# Lower threshold = more aggressive (removes more spikes)
# Higher threshold = less aggressive (keeps more data)

desp = SimpleSigmundDespiking(
    window_minutes=5.0,
    variable_groups=[
        VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=8.0)  # Higher = less aggressive
    ]
)
```

#### Issue: Despiking doesn't remove obvious spikes

**Cause:** Threshold is too high or window size is wrong.

**Solution:** Lower the threshold or adjust window:
```julia
desp = SimpleSigmundDespiking(
    window_minutes=2.0,  # Shorter window for faster response
    variable_groups=[
        VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=4.0)  # Lower = more aggressive
    ]
)
```

### Gap Filling

#### Issue: Gaps remain after gap filling

**Cause:** Gaps are larger than `max_gap_size`.

**Solution:** Increase the maximum gap size:
```julia
gap = GeneralInterpolation(
    max_gap_size=50,  # Fill gaps up to 50 consecutive missing values
    method=Cubic()
)
```

#### Issue: Interpolation creates unrealistic values

**Cause:** Using linear interpolation for nonlinear data, or gaps are too large.

**Solution:** Use higher-order interpolation or reduce max gap size:
```julia
# Option 1: Use cubic spline
gap = GeneralInterpolation(
    max_gap_size=10,
    method=Cubic()
)

# Option 2: Reduce max gap size
gap = GeneralInterpolation(
    max_gap_size=5,  # Only fill very small gaps
    method=Linear()
)
```

### H2O Correction

#### Issue: "Variable H2O not found" or "Variable P not found"

**Cause:** High-frequency data missing required variables.

**Solution:** Ensure your data has H2O and pressure:
```julia
# Check available variables
vars = val(dims(high_frequency_data, Var))
@show vars

# H2O correction requires:
# - High-frequency: :H2O, :P
# - Low-frequency: :TA, :RH

# If missing, disable H2O correction
pipeline = EddyPipeline(
    gas_analyzer=nothing,  # Skip H2O correction
    # ... other steps
)
```

#### Issue: "Variable TA not found" or "Variable RH not found"

**Cause:** Low-frequency data missing temperature or relative humidity.

**Solution:** Provide low-frequency data with required variables:
```julia
# Low-frequency data must have :TA and :RH
lf = DimArray(
    lf_data_matrix,
    (Var([:TA, :RH, :other_vars]), Ti(lf_times))
)

# Or disable H2O correction if LF data unavailable
pipeline = EddyPipeline(
    gas_analyzer=nothing,
    # ... other steps
)
```

#### Issue: H2O correction produces NaN values

**Cause:** Missing calibration coefficients or invalid input data.

**Solution:** Provide calibration coefficients:
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

# Or check for NaN in input data
@show count(isnan, high_frequency_data[Var=At(:H2O)])
@show count(isnan, low_frequency_data[Var=At(:TA)])
```

### Double Rotation

#### Issue: "Variable Ux not found" (or Uy, Uz)

**Cause:** Wind components missing from data.

**Solution:** Ensure wind components exist:
```julia
required_wind = [:Ux, :Uy, :Uz]
vars = val(dims(high_frequency_data, Var))

if all(w -> w in vars, required_wind)
    rot = WindDoubleRotation()
else
    @warn "Wind components missing, skipping double rotation"
    rot = nothing
end
```

#### Issue: Rotation angles are all zero

**Cause:** Wind is perfectly aligned with coordinate system (rare) or data quality issue.

**Solution:** Check your data:
```julia
ux = high_frequency_data[Var=At(:Ux)]
uy = high_frequency_data[Var=At(:Uy)]

@show mean(skipmissing(ux))  # Should be non-zero
@show mean(skipmissing(uy))  # Should be non-zero
```

### MRD

#### Issue: "Variable Uz not found" or "Variable Ts not found"

**Cause:** Specified variables don't exist in data.

**Solution:** Check available variables and adjust MRD configuration:
```julia
vars = val(dims(high_frequency_data, Var))
@show vars

# Use variables that exist
mrd = OrthogonalMRD(
    a=:Uz,      # Change if not available
    b=:Ts       # Change if not available
)
```

#### Issue: MRD results are all NaN

**Cause:** Data has too many gaps or insufficient samples.

**Solution:** Check data quality and adjust parameters:
```julia
# Check for gaps
times = collect(dims(high_frequency_data, Ti))
time_diffs = diff(times)
large_gaps = count(x -> x > Millisecond(1000), time_diffs)
@show large_gaps

# Adjust gap threshold
mrd = OrthogonalMRD(
    gap_threshold_seconds=20.0,  # Allow larger gaps
    regular_grid=true            # Backfill invalid blocks
)
```

#### Issue: MRD computation is very slow

**Cause:** Large M value or small shift parameter.

**Solution:** Reduce computational load:
```julia
# Option 1: Reduce maximum scale
mrd = OrthogonalMRD(M=10)  # Instead of 11

# Option 2: Increase shift (fewer blocks)
mrd = OrthogonalMRD(shift=512)  # Instead of 256

# Option 3: Use regular_grid=false to skip invalid blocks
mrd = OrthogonalMRD(regular_grid=false)
```

### Output

#### Issue: "Cannot write to output directory"

**Cause:** Directory doesn't exist or permission denied.

**Solution:** Create directory first:
```julia
using Base.Filesystem

output_dir = "/path/to/output"
mkpath(output_dir)  # Create if doesn't exist

out = ICSVOutput(output_dir)
```

#### Issue: Output files are empty

**Cause:** Data is all NaN or write_data wasn't called.

**Solution:** Check data before writing:
```julia
# Verify data has valid values
@show count(isfinite, high_frequency_data)
@show size(high_frequency_data)

# Ensure output step is in pipeline
pipeline = EddyPipeline(
    # ... other steps
    output=ICSVOutput("/path/to/output")  # Must be included
)
```

## Performance Issues

### Issue: Pipeline runs very slowly

**Cause:** Large dataset or expensive operations.

**Solution:** Profile and optimize:
```julia
using BenchmarkTools

# Time individual steps
@time quality_control!(qc, hf, lf, sensor)
@time despike!(desp, hf, lf)
@time fill_gaps!(gap, hf, lf)

# Disable expensive steps if not needed
pipeline = EddyPipeline(
    quality_control=nothing,  # Skip if not needed
    mrd=nothing,              # MRD is expensive
    output=output
)
```

### Issue: Memory usage is very high

**Cause:** Large dataset or inefficient operations.

**Solution:** Process in chunks or reduce data:
```julia
# Option 1: Process shorter time periods
# Instead of 1 year, process 1 month at a time

# Option 2: Reduce sampling rate before processing
# Downsample if high-frequency data is not needed

# Option 3: Use MemoryOutput only for testing
# Use ICSVOutput or NetCDFOutput for production
```

## Data Quality

### Issue: Results don't match expected values

**Cause:** Data preprocessing differences or parameter mismatches.

**Solution:** Verify pipeline configuration:
```julia
# 1. Check what steps are enabled
@show pipeline.quality_control
@show pipeline.despiking
@show pipeline.gap_filling

# 2. Verify parameters match expectations
@show pipeline.despiking.window_minutes
@show pipeline.gap_filling.max_gap_size

# 3. Compare with reference implementation
# Run with minimal pipeline first
minimal_pipeline = EddyPipeline(
    sensor=sensor,
    output=MemoryOutput()
)
```

### Issue: NaN values increase through pipeline

**Cause:** Each step may introduce NaN values (expected behavior).

**Solution:** Monitor NaN count:
```julia
function count_nans(data)
    return count(isnan, data)
end

n_nan_initial = count_nans(hf)
@show n_nan_initial

process!(pipeline, hf, lf)

n_nan_final = count_nans(hf)
@show n_nan_final
@show n_nan_final - n_nan_initial  # Additional NaNs introduced
```

## Debugging

### Enable Debug Logging

```julia
using Logging

# Enable debug messages
logger = ConsoleLogger(stderr, Logging.Debug)
with_logger(logger) do
    process!(pipeline, hf, lf)
end
```

### Inspect Data at Each Step

```julia
# Manually run steps to inspect intermediate results
check_data(hf, lf, sensor)

quality_control!(pipeline.quality_control, hf, lf, sensor)
@show count(isnan, hf)

despike!(pipeline.despiking, hf, lf)
@show count(isnan, hf)

fill_gaps!(pipeline.gap_filling, hf, lf)
@show count(isnan, hf)
```

### Use Processing Logger

```julia
logger = ProcessingLogger()

pipeline = EddyPipeline(
    sensor=sensor,
    output=output,
    logger=logger
)

process!(pipeline, hf, lf)

# Write log to file
write_processing_log(logger, "/path/to/log.csv")

# Inspect events
@show logger.events
@show logger.stage_times
```

## FAQ

### Q: What Julia version should I use?

**A:** Julia 1.11 or later. The project specifies `julia = "1.11"` in `Project.toml`.

```bash
julia +1.11 --project=.
```

### Q: Can I use PEDDY.jl with my custom sensor?

**A:** Yes! Create a custom sensor type inheriting from `AbstractSensor`. See [Extending PEDDY.jl](extending.md).

### Q: How do I handle missing data?

**A:** PEDDY.jl uses NaN to represent missing values. The pipeline handles NaN gracefully:
- Quality control marks invalid data as NaN
- Gap filling interpolates small gaps
- Most functions use `mean_skipnan` to ignore NaN

### Q: Can I run multiple pipeline configurations on the same data?

**A:** Yes, but remember that in-place modifications persist:
```julia
# Create a copy for each pipeline
hf1 = copy(high_frequency_data)
hf2 = copy(high_frequency_data)

process!(pipeline1, hf1, lf)
process!(pipeline2, hf2, lf)
```

### Q: How do I combine multiple output formats?

**A:** Use `OutputSplitter`:
```julia
out = OutputSplitter(
    ICSVOutput("/path/csv"),
    NetCDFOutput("/path/nc"),
    MemoryOutput()
)
```

### Q: What's the difference between `max_gap_size` and `gap_threshold_seconds`?

**A:** 
- `max_gap_size` (gap filling): Maximum number of consecutive missing values to interpolate
- `gap_threshold_seconds` (MRD): Maximum time gap allowed within an MRD block

### Q: How do I visualize MRD results?

**A:** Use the built-in plotting:
```julia
using Plots

mrd = OrthogonalMRD(a=:Uz, b=:Ts)
decompose!(mrd, hf, lf)
results = get_mrd_results(mrd)

if results !== nothing
    plot(results)  # Heatmap of MRD values
end
```

### Q: Can I process data in real-time or streaming mode?

**A:** Not currently. PEDDY.jl is designed for batch processing of complete datasets.

### Q: How do I contribute improvements or report bugs?

**A:** 
1. Check [GitHub Issues](https://github.com/pleibers/PEDDY.jl/issues)
2. Create a minimal reproducible example
3. Submit an issue or pull request

### Q: Where can I find example datasets?

**A:** See the [tutorial](index.md) for synthetic data examples. For real data, contact the package maintainers.

### Q: How do I cite PEDDY.jl?

**A:** See the [README](../README.md) for citation information and DOI.

## Getting Help

1. **Check the documentation**: [Tutorial](index.md), [API Reference](api.md), [Extension Guide](extending.md)
2. **Enable debug logging**: See "Debugging" section above
3. **Inspect intermediate results**: Run steps manually to identify where issues occur
4. **Create a minimal example**: Reproduce the issue with synthetic data
5. **Open an issue**: Provide code, data sample, and error message

## See Also

- [API Reference](api.md) - Complete function documentation
- [Tutorial](index.md) - Practical examples
- [Extension Guide](extending.md) - Creating custom steps
- [Best Practices](best_practice.md) - Julia development guidelines
