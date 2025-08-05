# PEDDY.jl

[![Build Status](https://gitlabext.wsl.ch/patrick.leibersperger/peddy.jl/badges/main/pipeline.svg)](https://gitlabext.wsl.ch/patrick.leibersperger/peddy.jl/pipelines)
[![Coverage](https://gitlabext.wsl.ch/patrick.leibersperger/peddy.jl/badges/main/coverage.svg)](https://gitlabext.wsl.ch/patrick.leibersperger/peddy.jl/commits/main)

A Julia package for processing eddy covariance data with a modular, high-performance pipeline architecture.

## Overview

PEDDY.jl provides a comprehensive framework for eddy covariance data processing, featuring:

- **Modular Pipeline Architecture**: Configurable processing steps for maximum flexibility
- **High-Performance Processing**: Optimized Julia implementation for fast data processing
- **Sensor Support**: Support for different kind of sensors

A more exhaustive documentation is available at [PEDDY.jl](MISSING) or build the documentation with `docs/make.jl`.

## Pipeline Steps

The pipeline always runs in the following order:

1. **Data Input**: Reading data from a specific file format or passing it as a DimArray
2. **Quality Control**: Physics-based bounds checking and diagnostic validation (optional)
3. **Gas Analyzer Correction**: H₂O bias correction using polynomial calibration (optional)
4. **Despiking**: Median Absolute Deviation (MAD) based spike detection and removal (optional)
5. **Gap Filling**: Linear, quadratic, and cubic spline interpolation for small gaps (optional)
6. **Double Rotation**: Wind coordinate transformation (optional)
7. **Mean Removal and Detrending (MRD)**: Statistical preprocessing (optional)
8. **Data Output**: Flexible writing with multiple format support

Each pipeline step introduces an abstract type so can be extended for your needs.

## Quick Start

### Installation

```julia
using Pkg
Pkg.add("PEDDY")
```

### Example

```julia
using PEDDY

# Create a basic pipeline
sensor = CSAT3()
high_frequency_data = rand(3,30) # Your data
low_frequency_data = rand(3,10) # Your data
input = PassData(high_frequency_data, low_frequency_data)
output = MemoryOutput() # Don't write to disk, just store in memory
pipeline = EddyPipeline(
    sensor = sensor,
    input = input,
    limit_check = PhysicsBoundsCheck(),
    gap_filling = GeneralInterpolation(),
    gas_analyzer = H2OCalibration(),
    output = output
)

# Process your data
process(pipeline)
```

## Data Format

PEDDY.jl uses `DimensionalData.jl` for efficient, labeled array operations:

```julia
# High-frequency data (typically 10-20 Hz)
high_freq_data::DimArray  # Wind components, sonic temperature, gas concentrations

# Low-frequency data (typically 1 Hz or slower)  
low_freq_data::DimArray   # Meteorological variables, reference measurements
```

## Supported Variables

- **Wind Components**: `Ux`, `Uy`, `Uz` (m/s)
- **Sonic Temperature**: `Ts` (°C)
- **Gas Concentrations**: `CO2`, `H2O` (various units)
- **Meteorological**: Temperature, relative humidity, pressure

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

Please follow Julia guidelines and use the `yas` style if possible

## Authors

- Patrick Leibersperger <patrick.leibersperger@slf.ch>
- Patricia Asemann <patricia.asemann@slf.ch>
- Rainette Engbers <rainette.engbers@slf.ch>

## License

See `LICENSE` file for details.

## Acknowledgments

This package builds upon established eddy covariance processing methods and incorporates algorithms from the scientific community. The H₂O calibration implementation is based on established gas analyzer correction techniques.
