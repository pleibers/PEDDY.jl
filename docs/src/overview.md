# PEDDY.jl Documentation Overview

Welcome to PEDDY.jl – a comprehensive Julia package for processing eddy covariance data with a modular, high-performance pipeline architecture.

## What is PEDDY.jl?

PEDDY.jl provides a complete framework for eddy covariance data processing, from raw measurements to publication-ready results. It features:

- **Modular Pipeline Architecture**: Each processing step is pluggable and can be customized or extended
- **High-Performance Implementation**: Optimized Julia code for fast processing of large datasets
- **Multiple Sensor Support**: Built-in support for Campbell CSAT3/CSAT3B, LI-COR IRGASON, and custom sensors
- **Comprehensive Processing Steps**: Quality control, despiking, gap filling, coordinate transformation, and multiresolution decomposition
- **Flexible Output**: Write results to CSV, NetCDF, or memory for further analysis

## Documentation Structure

This documentation is organized by use case and technical depth:

### For New Users

Start here if you're new to PEDDY.jl or eddy covariance processing:

1. **[Quick Reference](quick_reference.md)** – Copy-paste examples for common tasks
   - Minimal working example
   - Common configurations
   - Data access patterns
   - Cheat sheets for each step

2. **[Tutorial](index.md)** – Hands-on guide with detailed explanations
   - Installation and setup
   - Working with synthetic data
   - Configuring processing steps
   - Running the pipeline
   - Accessing results

3. **[Data Format & Architecture](data_format.md)** – Understanding PEDDY's data model
   - DimensionalData.jl basics
   - High-frequency and low-frequency data structure
   - Accessing and modifying data
   - Working with missing values

### For Active Users

Use these guides while working with PEDDY.jl:

4. **[Sensor Configuration](sensors.md)** – Choosing and configuring sensors
   - Supported sensors (CSAT3, CSAT3B, IRGASON, LICOR)
   - Sensor-specific workflows
   - Diagnostic interpretation
   - Creating custom sensors

5. **[API Reference](api.md)** – Complete function and type documentation
   - All pipeline steps with parameters
   - Input/output interfaces
   - Logging system
   - Utility functions

6. **[Troubleshooting & FAQ](troubleshooting.md)** – Solving common problems
   - Common errors and solutions
   - Performance optimization
   - Data quality issues
   - Debugging techniques

### For Advanced Users

Extend and customize PEDDY.jl for your needs:

7. **[Extending PEDDY.jl](extending.md)** – Creating custom pipeline steps
   - Custom quality control
   - Custom despiking algorithms
   - Custom gap filling methods
   - Custom output formats
   - Custom sensors
   - Best practices and patterns

8. **[Best Practice](best_practice.md)** – Julia development guidelines
   - Project organization
   - Dependency management
   - Development workflow
   - Publishing and reproducibility

## Quick Navigation

### By Task

**I want to...**

- **Process data quickly**: Start with [Quick Reference](quick_reference.md) → [Tutorial](index.md)
- **Understand the data format**: Read [Data Format & Architecture](data_format.md)
- **Choose a sensor**: See [Sensor Configuration](sensors.md)
- **Configure a specific step**: Check [API Reference](api.md)
- **Fix an error**: Look in [Troubleshooting & FAQ](troubleshooting.md)
- **Create a custom step**: Follow [Extending PEDDY.jl](extending.md)
- **Organize my project**: Read [Best Practice](best_practice.md)

### By Experience Level

**Beginner (new to Julia or eddy covariance):**
1. [Quick Reference](quick_reference.md) - minimal example
2. [Tutorial](index.md) - detailed walkthrough
3. [Data Format & Architecture](data_format.md) - understand the data

**Intermediate (familiar with Julia and eddy covariance):**
1. [Quick Reference](quick_reference.md) - quick lookup
2. [API Reference](api.md) - function details
3. [Sensor Configuration](sensors.md) - sensor setup
4. [Troubleshooting & FAQ](troubleshooting.md) - problem solving

**Advanced (want to extend PEDDY.jl):**
1. [API Reference](api.md) - understand interfaces
2. [Extending PEDDY.jl](extending.md) - create custom steps
3. [Data Format & Architecture](data_format.md) - understand data flow
4. [Best Practice](best_practice.md) - project organization

## Pipeline Overview

PEDDY.jl processes data through a configurable pipeline with these steps (in order):

```
Raw Data
   ↓
1. Quality Control (optional)
   ↓
2. Gas Analyzer Correction (optional)
   ↓
3. Despiking (optional)
   ↓
4. Make Continuous (optional)
   ↓
5. Gap Filling (optional)
   ↓
6. Double Rotation (optional)
   ↓
7. Multi-Resolution Decomposition (optional)
   ↓
8. Output
   ↓
Processed Data
```

Each step:
- Is **optional** (set to `nothing` to skip)
- **Modifies data in-place** (except MRD which stores results separately)
- Can be **customized** or **replaced** with your own implementation

## Key Concepts

### DimensionalData.jl

PEDDY.jl uses labeled arrays (`DimArray`) for all data:

```julia
hf = DimArray(
    data_matrix,
    (Var([:Ux, :Uy, :Uz, :Ts]), Ti(times))
)

# Access by label, not index
ux = hf[Var=At(:Ux)]
```

Benefits:
- Type-safe dimension access
- Self-documenting code
- Less error-prone than plain matrices

### Missing Data Handling

PEDDY.jl uses `NaN` to represent missing values:

```julia
# Check for missing
n_missing = count(isnan, hf)

# Get statistics ignoring NaN
mean_val = PEDDY.mean_skipnan(hf[Var=At(:Ux)])
```

### Modular Steps

Each pipeline step is a type implementing an abstract interface:

```julia
struct MyCustomStep <: AbstractDespiking
    # fields
end

function PEDDY.despike!(step::MyCustomStep, hf, lf; kwargs...)
    # implementation
end
```

This allows easy extension and customization.

## Common Workflows

### Minimal Processing

```julia
pipeline = EddyPipeline(
    sensor=CSAT3(),
    quality_control=PhysicsBoundsCheck(),
    output=MemoryOutput()
)
process!(pipeline, hf, lf)
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
process!(pipeline, hf, lf)
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
process!(pipeline, hf, lf)
```

## Data Format Summary

### High-Frequency Data

Fast measurements (typically 10-20 Hz):

```julia
hf = DimArray(
    data_matrix,
    (Var([:Ux, :Uy, :Uz, :Ts, :H2O, :P, :CO2]), Ti(times))
)
```

**Required variables** depend on sensor:
- All sensors: `Ux, Uy, Uz, Ts`
- IRGASON/LICOR: also `CO2, H2O, P`

### Low-Frequency Data

Slow measurements (typically 1 Hz or slower), optional:

```julia
lf = DimArray(
    data_matrix,
    (Var([:TA, :RH, :P]), Ti(times))
)
```

**Used for:**
- H₂O correction (needs `:TA`, `:RH`)
- Reference measurements
- Meteorological context

## Processing Steps at a Glance

| Step | Purpose | When to Use | Example |
|------|---------|-------------|---------|
| Quality Control | Remove physically impossible values | Always | `PhysicsBoundsCheck()` |
| Gas Analyzer | Correct H₂O measurements | If using LICOR/IRGASON | `H2OCalibration()` |
| Despiking | Remove measurement spikes | Usually | `SimpleSigmundDespiking()` |
| Make Continuous | Insert missing timestamps | If data has gaps | `MakeContinuous()` |
| Gap Filling | Interpolate small gaps | Usually | `GeneralInterpolation()` |
| Double Rotation | Align with mean wind | For flux calculations | `WindDoubleRotation()` |
| MRD | Multiresolution analysis | For spectral analysis | `OrthogonalMRD()` |
| Output | Write results | Always | `ICSVOutput()` |

## Installation

```bash
# Julia 1.11 required
julia +1.11 --project=.
julia> using Pkg; Pkg.instantiate()
```

Or add to your environment:

```julia
using Pkg
Pkg.add("PEDDY")
```

## Getting Help

1. **Check the documentation**: Use the navigation above
2. **Search for your error**: [Troubleshooting & FAQ](troubleshooting.md)
3. **Look for examples**: [Quick Reference](quick_reference.md) and [Tutorial](index.md)
4. **Read the API docs**: [API Reference](api.md)
5. **Create a custom step**: [Extending PEDDY.jl](extending.md)

## Key Files and Directories

```
PEDDY.jl/
├── src/                          # Source code
│   ├── PEDDY.jl                 # Main module
│   ├── pipeline.jl              # EddyPipeline and process!
│   ├── despiking.jl             # Despiking implementation
│   ├── interpolation.jl         # Gap filling
│   ├── h2o_correction.jl        # H2O calibration
│   ├── double_rotation.jl       # Wind rotation
│   ├── logging.jl               # Logging system
│   ├── make_continuous.jl       # Time axis continuity
│   ├── IO/                      # Input/output
│   ├── QC/                      # Quality control
│   ├── Sensors/                 # Sensor definitions
│   └── MRD/                     # Multiresolution decomposition
├── docs/
│   ├── src/
│   │   ├── index.md            # Tutorial
│   │   ├── api.md              # API reference
│   │   ├── extending.md        # Extension guide
│   │   ├── data_format.md      # Data format guide
│   │   ├── sensors.md          # Sensor guide
│   │   ├── troubleshooting.md  # Troubleshooting
│   │   ├── quick_reference.md  # Quick reference
│   │   ├── best_practice.md    # Best practices
│   │   └── overview.md         # This file
│   └── make.jl                 # Documentation builder
├── test/                        # Tests
├── examples/                    # Example scripts
├── Project.toml                # Dependencies
└── README.md                   # Project README
```

## Core Concepts

### Abstract Types and Dispatch

PEDDY.jl uses Julia's type system for extensibility:

```julia
abstract type PipelineStep end
abstract type AbstractQC <: PipelineStep end
abstract type AbstractDespiking <: PipelineStep end
# ... etc
```

Each step type implements its corresponding function:

```julia
quality_control!(qc::AbstractQC, hf, lf, sensor; kwargs...)
despike!(desp::AbstractDespiking, hf, lf; kwargs...)
# ... etc
```

This allows you to create custom steps by defining new types and implementing the interface.

### In-Place Modifications

Most steps modify data in-place for efficiency:

```julia
# Data is modified in-place
quality_control!(qc, hf, lf, sensor)
despike!(desp, hf, lf)

# hf now contains modified data
```

Exception: MRD stores results separately:

```julia
decompose!(mrd, hf, lf)
results = get_mrd_results(mrd)  # Get results from mrd object
```

### Optional Steps

All steps are optional – set to `nothing` to skip:

```julia
pipeline = EddyPipeline(
    sensor=sensor,
    quality_control=nothing,      # Skip QC
    despiking=SimpleSigmundDespiking(),
    gap_filling=nothing,          # Skip gap filling
    output=output
)
```

## Performance Considerations

### Memory Usage

- **In-place operations**: Use `@view` to avoid copies
- **Large datasets**: Process in time chunks
- **Output format**: NetCDF is more efficient than CSV for large files

### Speed

- **Disable expensive steps**: Set to `nothing` if not needed
- **Reduce MRD parameters**: Smaller `M` or larger `shift`
- **Use appropriate interpolation**: `Linear()` is fastest, `Cubic()` is most accurate
- **Disable logging**: Use `NoOpLogger()` for production

## Reproducibility

PEDDY.jl supports reproducible processing:

```julia
# 1. Use Project.toml for dependency management
# 2. Enable logging to track what was done
logger = ProcessingLogger()
pipeline = EddyPipeline(..., logger=logger)
process!(pipeline, hf, lf)
write_processing_log(logger, "processing_log.csv")

# 3. Save configuration
# 4. Document sensor setup and calibration
```

## Citation

If you use PEDDY.jl in your research, please cite:

```bibtex
@software{leibersperger2024peddy,
  title={PEDDY.jl: A Julia package for eddy covariance data processing},
  author={Leibersperger, Patrick and Asemann, Patricia and Engbers, Rainette},
  year={2024},
  url={https://github.com/pleibers/PEDDY.jl}
}
```

## Contributing

Contributions are welcome! See [Best Practice](best_practice.md) for development guidelines.

## License

PEDDY.jl is licensed under the MIT License. See LICENSE file for details.

## Next Steps

1. **New to PEDDY.jl?** → Start with [Quick Reference](quick_reference.md)
2. **Want to learn more?** → Read the [Tutorial](index.md)
3. **Need specific help?** → Check [Troubleshooting & FAQ](troubleshooting.md)
4. **Want to extend?** → See [Extending PEDDY.jl](extending.md)
5. **Looking for details?** → Consult [API Reference](api.md)

---

**Happy processing!** 🎉
