# Sensor Configuration Guide

PEDDY.jl supports multiple eddy covariance sensors. Each sensor defines the variables it provides and any calibration coefficients needed for gas analyzer correction.

## Supported Sensors

### Campbell CSAT3

The Campbell CSAT3 is a sonic anemometer that measures three-dimensional wind components and sonic temperature.

```julia
sensor = CSAT3()
```

**Provides:**
- `Ux, Uy, Uz`: Wind components (m/s)
- `Ts`: Sonic temperature (°C)
- `diag_sonic`: Diagnostic flag (0 = good)

**Required in high-frequency data:**
- `Ux, Uy, Uz, Ts, diag_sonic`

**Notes:**
- Does not measure gas concentrations
- Diagnostic flag should be 0 for valid measurements
- Commonly used in eddy covariance systems

**Example:**
```julia
sensor = CSAT3()
qc = PhysicsBoundsCheck()

pipeline = EddyPipeline(
    sensor=sensor,
    quality_control=qc,
    output=MemoryOutput()
)

process!(pipeline, hf, lf)
```

### Campbell CSAT3B

The CSAT3B is an updated version of the CSAT3 with improved performance.

```julia
sensor = CSAT3B()
```

**Provides:**
- Same as CSAT3: `Ux, Uy, Uz, Ts, diag_sonic`

**Required in high-frequency data:**
- `Ux, Uy, Uz, Ts, diag_sonic`

**Notes:**
- Drop-in replacement for CSAT3
- Improved temperature measurement accuracy
- Better performance in wet conditions

**Example:**
```julia
sensor = CSAT3B()
```

### LI-COR IRGASON

The LI-COR IRGASON combines a sonic anemometer with an infrared gas analyzer for CO₂ and H₂O measurements.

```julia
sensor = IRGASON()
```

**Provides:**
- `Ux, Uy, Uz`: Wind components (m/s)
- `Ts`: Sonic temperature (°C)
- `CO2`: Carbon dioxide concentration
- `H2O`: Water vapor concentration
- `diag_sonic`: Sonic diagnostic flag
- `diag_irga`: IRGA diagnostic flag

**Required in high-frequency data:**
- `Ux, Uy, Uz, Ts, CO2, H2O, diag_sonic, diag_irga`

**Notes:**
- Integrated sonic + gas analyzer
- Requires regular calibration
- H₂O measurements often need correction

**Example:**
```julia
sensor = IRGASON()

# With H2O correction
gas = H2OCalibration()

pipeline = EddyPipeline(
    sensor=sensor,
    gas_analyzer=gas,
    output=MemoryOutput()
)

process!(pipeline, hf, lf)
```

### LI-COR with Calibration Coefficients

For LI-COR systems with H₂O calibration coefficients:

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

**Calibration Coefficients:**
- `A, B, C`: Polynomial coefficients for absorptance calculation
- `H2O_Zero`: Zero offset for H₂O measurement
- `H20_Span`: Span factor for H₂O measurement

**Obtaining Calibration Coefficients:**
1. Check the sensor's calibration certificate
2. Contact LI-COR for your specific sensor
3. Perform a calibration procedure at your site

**Example with coefficients:**
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

gas = H2OCalibration()

pipeline = EddyPipeline(
    sensor=sensor,
    gas_analyzer=gas,
    output=MemoryOutput()
)

process!(pipeline, hf, lf)
```

## Sensor Selection Guide

### Choosing a Sensor

**Use CSAT3/CSAT3B if:**
- You only need wind and temperature
- You have a separate gas analyzer
- Cost is a concern
- You need a proven, reliable sensor

**Use IRGASON if:**
- You need integrated wind + CO₂ + H₂O
- You want a compact system
- You have space constraints
- You're willing to maintain calibration

**Use LICOR if:**
- You have a LI-COR gas analyzer
- You need precise H₂O measurements
- You have calibration coefficients available

## Sensor Diagnostics

### Understanding Diagnostic Flags

Most sensors provide diagnostic flags indicating measurement quality:

```julia
# CSAT3 diagnostic
diag = hf[Var=At(:diag_sonic)]

# 0 = good measurement
# Non-zero = problem detected
n_bad = count(x -> x != 0, diag)
@show n_bad
```

### Checking Diagnostics

```julia
# Quality control checks diagnostics
qc = PhysicsBoundsCheck()
quality_control!(qc, hf, lf, sensor)

# Or use OnlyDiagnostics to check only diagnostics
qc_diag = OnlyDiagnostics()
quality_control!(qc_diag, hf, lf, sensor)
```

### Interpreting Diagnostic Values

**CSAT3 Diagnostic Bits:**
- Bit 0: Sonic signal lock loss
- Bit 1: Amplitude out of range
- Bit 2: Bad checksum
- Bit 3: Transducer open
- Bit 4: Transducer short
- Bit 5: Bad transducer
- Bit 6: Transducer not ready
- Bit 7: Transducer type mismatch

**IRGASON Diagnostic Bits:**
- Similar to CSAT3 for sonic part
- Additional bits for IRGA status

## Sensor Maintenance

### Regular Maintenance

1. **Cleaning**: Remove dust and debris from sensor heads
2. **Calibration**: Perform zero/span calibration as recommended
3. **Inspection**: Check for physical damage or corrosion
4. **Replacement**: Replace worn components per manufacturer specs

### Detecting Sensor Issues

```julia
# Check for sudden changes in diagnostics
diag = collect(dims(hf, Ti))
diag_flags = hf[Var=At(:diag_sonic)]

# Count bad diagnostics per time window
window_size = 1000
for i in 1:window_size:length(diag_flags)
    window_end = min(i + window_size - 1, length(diag_flags))
    n_bad = count(x -> x != 0, diag_flags[i:window_end])
    if n_bad > window_size * 0.1  # More than 10% bad
        @warn "High diagnostic failure rate at $(diag[i])"
    end
end
```

## Sensor-Specific Workflows

### CSAT3 with Separate Gas Analyzer

```julia
# High-frequency: sonic only
hf = DimArray(
    data_hf,
    (Var([:Ux, :Uy, :Uz, :Ts, :diag_sonic]), Ti(times_hf))
)

# Low-frequency: meteorological variables
lf = DimArray(
    data_lf,
    (Var([:TA, :RH, :P]), Ti(times_lf))
)

sensor = CSAT3()
qc = PhysicsBoundsCheck()
desp = SimpleSigmundDespiking()
gap = GeneralInterpolation()

pipeline = EddyPipeline(
    sensor=sensor,
    quality_control=qc,
    despiking=desp,
    gap_filling=gap,
    output=ICSVOutput("/path/to/output")
)

process!(pipeline, hf, lf)
```

### IRGASON with H₂O Correction

```julia
# High-frequency: sonic + gas analyzer
hf = DimArray(
    data_hf,
    (Var([:Ux, :Uy, :Uz, :Ts, :CO2, :H2O, :P, :diag_sonic, :diag_irga]), Ti(times_hf))
)

# Low-frequency: for H2O correction
lf = DimArray(
    data_lf,
    (Var([:TA, :RH, :P]), Ti(times_lf))
)

sensor = IRGASON()
qc = PhysicsBoundsCheck()
gas = H2OCalibration()
desp = SimpleSigmundDespiking()
gap = GeneralInterpolation()

pipeline = EddyPipeline(
    sensor=sensor,
    quality_control=qc,
    gas_analyzer=gas,
    despiking=desp,
    gap_filling=gap,
    output=NetCDFOutput("/path/to/output")
)

process!(pipeline, hf, lf)
```

### LICOR with Calibration

```julia
# Define calibration coefficients (from calibration certificate)
calib = H2OCalibrationCoefficients(
    A=4.82004e3,
    B=3.79290e6,
    C=-1.15477e8,
    H2O_Zero=0.7087,
    H20_Span=0.9885
)

sensor = LICOR(calibration_coefficients=calib)

# Rest of pipeline
gas = H2OCalibration(h2o_variable=:H2O, pressure_var=:P)

pipeline = EddyPipeline(
    sensor=sensor,
    gas_analyzer=gas,
    output=MemoryOutput()
)

process!(pipeline, hf, lf)
```

## Creating a Custom Sensor

If your sensor is not supported, create a custom type:

```julia
using PEDDY

struct MySensor <: AbstractSensor
    name::String
    required_variables::Vector{Symbol}
end

function MySensor()
    return MySensor(
        "MySensor",
        [:Ux, :Uy, :Uz, :Ts, :diag]
    )
end

# Implement required interface
function PEDDY.needs_data_cols(sensor::MySensor)
    return sensor.required_variables
end

function PEDDY.check_diagnostics!(sensor::MySensor, hf; kwargs...)
    if :diag in dims(hf, Var)
        diag = hf[Var=At(:diag)]
        n_bad = count(x -> !isfinite(x) || x > 0, diag)
        if n_bad > 0
            @warn "MySensor: $n_bad records with bad diagnostics"
        end
    end
end

# Use in pipeline
sensor = MySensor()
pipeline = EddyPipeline(
    sensor=sensor,
    output=MemoryOutput()
)
```

## Sensor Comparison

| Feature | CSAT3 | CSAT3B | IRGASON | LICOR |
|---------|-------|--------|---------|-------|
| Wind (3D) | ✓ | ✓ | ✓ | ✓ |
| Temperature | ✓ | ✓ | ✓ | ✓ |
| CO₂ | ✗ | ✗ | ✓ | ✓ |
| H₂O | ✗ | ✗ | ✓ | ✓ |
| Integrated | ✗ | ✗ | ✓ | ✗ |
| Cost | Low | Low | Medium | Medium |
| Maintenance | Low | Low | Medium | Medium |
| Calibration | None | None | Periodic | Periodic |

## Troubleshooting Sensor Issues

### Issue: Constant Diagnostic Failures

```julia
# Check if diagnostic field exists
vars = val(dims(hf, Var))
if :diag_sonic in vars
    diag = hf[Var=At(:diag_sonic)]
    @show unique(diag)
else
    @warn "No diagnostic field found"
end

# If diagnostics are always non-zero, sensor may have issues
# Contact manufacturer or replace sensor
```

### Issue: Unrealistic Wind Values

```julia
# Check wind statistics
ux = hf[Var=At(:Ux)]
uy = hf[Var=At(:Uy)]
uz = hf[Var=At(:Uz)]

@show extrema(skipmissing(ux))
@show extrema(skipmissing(uy))
@show extrema(skipmissing(uz))

# If values are unrealistic, check:
# 1. Sensor orientation
# 2. Data scaling/units
# 3. Sensor calibration
```

### Issue: Temperature Spikes

```julia
# Check temperature statistics
ts = hf[Var=At(:Ts)]
ts_clean = ts[isfinite.(ts)]

# Look for outliers
mean_ts = mean(ts_clean)
std_ts = std(ts_clean)
outliers = ts[abs.(ts .- mean_ts) .> 5 * std_ts]

@show length(outliers)
# If many outliers, may indicate sensor heating or interference
```

## See Also

- [API Reference](api.md) - Sensor types and functions
- [Tutorial](index.md) - Practical examples
- [Extending PEDDY.jl](extending.md) - Creating custom sensors
- [Troubleshooting](troubleshooting.md) - Common issues
