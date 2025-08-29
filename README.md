# PEDDY.jl

<p align="center">
  <img src="docs/assets/logo_scaled.png" alt="PEDDY.jl Logo" width="200"/>
</p>

[![CI](https://github.com/pleibers/PEDDY.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/pleibers/PEDDY.jl/actions/workflows/ci.yml)
[![Coverage](https://raw.githubusercontent.com/pleibers/PEDDY.jl/badges/coverage-badge.svg)](https://github.com/pleibers/PEDDY.jl/actions/workflows/ci.yml)

A Julia package for processing eddy covariance data with a modular, high-performance pipeline architecture.

## Overview

PEDDY.jl provides a comprehensive framework for eddy covariance data processing, featuring:

- **Modular Pipeline Architecture**: Configurable processing steps for maximum flexibility
- **High-Performance Processing**: Optimized Julia implementation for fast data processing
- **Sensor Support**: Support for different kind of sensors

Documentation and tutorial:

- Tutorial: see `docs/src/index.md` for a practical, example-driven guide.
- Best Practice: see `docs/src/best_practice.md` for an opinion on how to use julia in science.
- API docs: build locally via `docs/make.jl`.

Quick build hint:

```bash
# Julia 1.11 is required. If 1.11 is not your default, prefix commands with +1.11
# (the "+1.11" is not part of Julia syntax, it is a version selector used by juliaup).
julia +1.11 --project=docs -e 'using Pkg; Pkg.instantiate(); include("docs/make.jl")'
```

## Roadmap

- [ ] Instead of using NaNs for missing values, actually use missing.
- [ ] Implement further MRD algorithms

## Pipeline Steps

The pipeline always runs in the following order:

1. **Quality Control**: Physics-based bounds checking and diagnostic validation (optional)
2. **Gas Analyzer Correction**: H₂O bias correction using polynomial calibration (optional)
3. **Despiking**: Median Absolute Deviation (MAD) based spike detection and removal (optional)
4. **Gap Filling**: Linear, quadratic, and cubic spline interpolation for small gaps (optional)
5. **Double Rotation**: Wind coordinate transformation (optional)
6. **Multi-Resolution Decomposition (MRD)**: Statistical preprocessing (optional)
7. **Data Output**: Flexible writing with multiple format support

Each pipeline step introduces an abstract type so can be extended for your needs.

## MRD

The MRD step will not modify the data, but instead provide the results inside the MRD struct, and can be plotted with plot(mrd::OrthogonalMRD;kwargs...)

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
output = MemoryOutput() # Don't write to disk, just store in memory
pipeline = EddyPipeline(
    sensor = sensor,
    quality_control = PhysicsBoundsCheck(),
    gap_filling = GeneralInterpolation(),
    gas_analyzer = H2OCalibration(),
    output = output
)

# Process your data
process!(pipeline, high_frequency_data, low_frequency_data)
```

## Data Format

PEDDY.jl uses [DimensionalData.jl](https://rafaqz.github.io/DimensionalData.jl/dev/basics) for efficient, labeled array operations:

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

This package builds upon established eddy covariance processing methods and incorporates algorithms from the scientific community.
