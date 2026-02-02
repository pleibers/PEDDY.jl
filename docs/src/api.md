# API Reference

## Core Pipeline

### EddyPipeline

```@docs
EddyPipeline
process!
check_data
```

## Quality Control (QC)

### Abstract Types

```@docs
AbstractQC
quality_control!
```

### Implementations

#### PhysicsBoundsCheck

Validates that measurements fall within physically plausible ranges. This is a critical first step to remove obviously erroneous data.

```julia
qc = PhysicsBoundsCheck()
# Or with custom limits:
qc = PhysicsBoundsCheck(
    Ux = Limit(-50, 50),
    Uy = Limit(-50, 50),
    Uz = Limit(-30, 30),
    Ts = Limit(-40, 50)
)
```

**Default Physical Limits:**
- `Ux, Uy`: [-100, 100] m/s
- `Uz`: [-50, 50] m/s
- `Ts`: [-50, 50] °C
- `CO2`: [0, ∞] ppm
- `H2O`: [0, ∞] mmol/mol
- `T`: [-50, 50] °C
- `P`: [0, ∞] Pa

#### OnlyDiagnostics

Checks only sensor diagnostic flags without applying physical bounds. Useful when you trust your data range but want to verify sensor health.

```julia
qc = OnlyDiagnostics()
```

## Gas Analyzer Correction

### H2O Calibration

```@docs
H2OCalibration
correct_gas_analyzer!
get_calibration_coefficients
```

**How it works:**
1. Extracts calibration coefficients from the sensor
2. Resamples high-frequency H2O and pressure to low-frequency grid
3. Computes reference H2O concentration from temperature and relative humidity
4. Solves cubic polynomial to find absorptance
5. Applies correction back to high-frequency data

**Required variables:**
- High-frequency: `:H2O`, `:P` (pressure)
- Low-frequency: `:TA` (temperature), `:RH` (relative humidity)

## Despiking

### SimpleSigmundDespiking

```@docs
SimpleSigmundDespiking
VariableGroup
despike!
```

**Algorithm:** Modified Median Absolute Deviation (MAD) based on Sigmund et al. (2022)

The method:
1. Computes rolling median and MAD over a specified window
2. Identifies spikes as deviations exceeding threshold × 0.6745 × MAD
3. Sets detected spikes to NaN
4. Supports per-group thresholds for different variable types

**Example with multiple groups:**
```julia
wind = VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=6.0)
temp = VariableGroup("Sonic T", [:Ts], spike_threshold=6.0)
gas = VariableGroup("Gas", [:H2O], spike_threshold=5.0)

desp = SimpleSigmundDespiking(
    window_minutes=5.0,
    variable_groups=[wind, temp, gas]
)
```

## Make Continuous

### MakeContinuous

```@docs
MakeContinuous
make_continuous!
```

**Purpose:** Ensures a continuous time axis by inserting missing timestamps.

**Behavior:**
- Inserts timestamps for gaps up to `max_gap_minutes`
- Fills inserted rows with NaN for all variables
- Warns about gaps larger than `max_gap_minutes`
- Returns a new DimArray with expanded time dimension

**Example:**
```julia
mc = MakeContinuous(step_size_ms=50, max_gap_minutes=5.0)
hf_continuous = make_continuous!(mc, hf, lf)
```

## Gap Filling / Interpolation

### InterpolationMethod

```@docs
Linear
Quadratic
Cubic
```

### GeneralInterpolation

```@docs
GeneralInterpolation
fill_gaps!
```

**Features:**
- Interpolates only gaps ≤ `max_gap_size` consecutive missing values
- Supports multiple interpolation methods
- Applies to specified variables only
- Larger gaps are left as NaN

**Example:**
```julia
gap = GeneralInterpolation(
    max_gap_size=10,
    variables=[:Ux, :Uy, :Uz, :Ts, :H2O],
    method=Cubic()
)
```

## Double Rotation

### WindDoubleRotation

```@docs
WindDoubleRotation
rotate!
```

**Algorithm:** Aligns wind measurements with the mean streamline coordinate system

1. **First rotation (θ):** Rotates around z-axis to set mean(v) = 0
2. **Second rotation (φ):** Rotates around y-axis to set mean(w) = 0

**Block-based processing:**
- Divides data into blocks of specified duration
- Computes rotation angles per block
- Applies rotations to all wind components

**Example:**
```julia
rot = WindDoubleRotation(block_duration_minutes=30.0)
rotate!(rot, hf, lf)
```

## Multi-Resolution Decomposition (MRD)

### OrthogonalMRD

```@docs
OrthogonalMRD
decompose!
MRDResults
get_mrd_results
```

**Algorithm:** Orthogonal multiresolution covariance analysis (Vickers & Mahrt 2003; Howell & Mahrt 1997)

**Key concepts:**
- Decomposes covariance into multiple scales (2^1, 2^2, ..., 2^M samples)
- Computes mean of window-mean products per scale
- Handles gaps intelligently (skips blocks with large gaps)
- Optionally normalizes by centered moving average

**Parameters:**
- `M`: Maximum scale exponent (block length = 2^M samples)
- `shift`: Step size between blocks (samples)
- `a`, `b`: Variables to correlate (e.g., `:Uz` and `:Ts`)
- `gap_threshold_seconds`: Maximum allowed gap within a block
- `normalize`: Apply normalization
- `regular_grid`: Backfill invalid blocks with NaN to maintain regular grid

**Example:**
```julia
mrd = OrthogonalMRD(
    M=11,
    shift=256,
    a=:Uz,
    b=:Ts,
    gap_threshold_seconds=10.0,
    regular_grid=false
)

decompose!(mrd, hf, lf)
results = get_mrd_results(mrd)

if results !== nothing
    @show results.scales       # Time scales in seconds
    @show size(results.mrd)    # (M, nblocks)
    @show results.times        # Block midpoint times
end
```

**Plotting MRD results:**
```julia
using Plots
plot(results)  # Heatmap of MRD values across scales and time
```

## Input/Output

### Input

```@docs
AbstractInput
read_data
DotDatDirectory
FileOptions
```

**Reading from .dat files:**
```julia
sensor = CSAT3()

input = DotDatDirectory(
    directory="/path/to/data",
    high_frequency_file_glob="*fast*",
    high_frequency_file_options=FileOptions(
        timestamp_column=:TIMESTAMP,
        time_format=dateformat"yyyy-mm-dd HH:MM:SS.s"
    ),
    low_frequency_file_glob="*slow*",
    low_frequency_file_options=FileOptions(
        timestamp_column=:TIMESTAMP,
        time_format=dateformat"yyyy-mm-dd HH:MM:SS"
    )
)

hf, lf = read_data(input, sensor)
```

### Output

```@docs
AbstractOutput
write_data
MemoryOutput
ICSVOutput
NetCDFOutput
OutputSplitter
```

**Output options:**

**MemoryOutput:** Keep results in memory (for exploration)
```julia
out = MemoryOutput()
process!(pipeline, hf, lf)
hf_res, lf_res = PEDDY.get_results(out)
```

**ICSVOutput:** Write to CSV files
```julia
out = ICSVOutput("/path/to/output")
```

**NetCDFOutput:** Write to NetCDF format
```julia
out = NetCDFOutput("/path/to/output")
```

**OutputSplitter:** Write to multiple formats simultaneously
```julia
out = OutputSplitter(
    ICSVOutput("/path/csv"),
    NetCDFOutput("/path/nc")
)
```

### Metadata

```@docs
LocationMetadata
VariableMetadata
get_default_metadata
metadata_for
```

## Sensors

### Supported Sensors

```@docs
CSAT3
CSAT3B
IRGASON
LICOR
```

**Sensor selection:**
```julia
# Campbell CSAT3 sonic anemometer
sensor = CSAT3()

# Campbell CSAT3B (updated version)
sensor = CSAT3B()

# LI-COR IRGASON (sonic + CO2/H2O)
sensor = IRGASON()

# LI-COR with H2O calibration coefficients
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

### AbstractProcessingLogger

```@docs
AbstractProcessingLogger
ProcessingLogger
NoOpLogger
log_event!
record_stage_time!
write_processing_log
log_index_runs!
log_mask_runs!
is_logging_enabled
```

**Usage:**
```julia
# Active logging
logger = ProcessingLogger()

pipeline = EddyPipeline(
    sensor=sensor,
    output=output,
    logger=logger
)

process!(pipeline, hf, lf)

# Write log to file
write_processing_log(logger, "/path/to/log.csv")

# Or use no-op logger (zero overhead)
logger = NoOpLogger()
```

## Utility Functions

### mean_skipnan

Compute mean while ignoring NaN values. Returns NaN if all values are NaN.

```julia
result = PEDDY.mean_skipnan(arr)
```

## Data Format

All data is represented using `DimArray` from [DimensionalData.jl](https://rafaqz.github.io/DimensionalData.jl/dev/):

```julia
using DimensionalData

# High-frequency data with Var and Ti dimensions
hf = DimArray(
    data_matrix,
    (Var([:Ux, :Uy, :Uz, :Ts, :H2O]), Ti(times))
)

# Access variables
ux = hf[Var=At(:Ux)]
ts = hf[Var=At(:Ts)]

# Access time slice
slice = hf[Ti=At(DateTime(2024, 1, 1, 12, 0, 0))]
```

## Abstract Types for Extension

All pipeline steps inherit from `PipelineStep` and implement specific abstract interfaces:

```julia
abstract type PipelineStep end

abstract type AbstractQC <: PipelineStep end
abstract type AbstractDespiking <: PipelineStep end
abstract type AbstractGapFilling <: PipelineStep end
abstract type AbstractMakeContinuous <: PipelineStep end
abstract type AbstractGasAnalyzer <: PipelineStep end
abstract type AbstractDoubleRotation <: PipelineStep end
abstract type AbstractMRD <: PipelineStep end
abstract type AbstractOutput <: PipelineStep end
```

See the [Extension Guide](extending.md) for implementing custom steps.
