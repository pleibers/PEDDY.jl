# Peddy.jl — Practical tutorial

Peddy is a Julia package for eddy-covariance data processing. This page is a hands-on guide for scientists who are new to Julia and just want to run the workflow.

If references in docstrings do not render, they are still kept for completeness.

## Table of Contents

- [Quick start (no prior Julia knowledge required)](#quick-start-no-prior-julia-knowledge-required)
  - [Development environment](#development-environment)
  - [Usage environment](#usage-environment)
- [Quick example (synthetic data)](#quick-example-synthetic-data)
- [Data model in one minute](#data-model-in-one-minute)
- [Read data](#read-data)
- [Configure processing steps](#configure-processing-steps)
  - [1) Quality control](#1-quality-control)
  - [2) Gas analyzer H2O calibration](#2-gas-analyzer-h2o-calibration)
  - [3) Despiking (Sigmund et al. 2022, modified MAD)](#3-despiking-sigmund-et-al-2022-modified-mad)
  - [4) Gap filling (small gaps only)](#4-gap-filling-small-gaps-only)
  - [5) Wind double rotation](#5-wind-double-rotation)
  - [6) Multi-Resolution Decomposition (MRD)](#6-multi-resolution-decomposition-mrd)
  - [7) Output (choose one)](#7-output-choose-one)
- [Build and run a pipeline](#build-and-run-a-pipeline)
- [Run steps manually (optional)](#run-steps-manually-optional)
- [Tips and troubleshooting](#tips-and-troubleshooting)
- [API reference](#api-reference)

---

## Quick start (no prior Julia knowledge required)

### Development environment

If you want to develop Peddy, you need to follow these steps:

- __Install Julia 1.11__: Download from julialang.org. If 1.11 is not your default, prefix commands with `+1.11` (without parentheses). The `+1.11` selector is provided by juliaup.
- __Open a Julia REPL in the project__:

```julia
# From your shell inside the repository folder
julia +1.11 --project=.
```

- __Instantiate the environment__ (first time only to install all dependencies):

```julia
julia> using Pkg
julia> Pkg.instantiate()
```

### Usage environment

If you want to use Peddy, you need to have it installed in the environment you are using. with the following command:

```julia
julia> using Pkg
julia> Pkg.add("Peddy")
```

For the newest version do:

```julia
julia> using Pkg
julia> Pkg.add("Peddy", rev="master")
```

or (this also works if Peddy is not registered):

```julia
julia> using Pkg
julia> Pkg.add("Peddy", url="https://github.com/pleibers/Peddy.jl.git")
```

---

## Quick example (synthetic data)

You need to have Peddy installed in the environment you are using. If you are in the development environment, make sure it is activated.

This creates tiny high-frequency data in memory and runs a minimal pipeline.

```julia
using Peddy
using Dates

# 1) Create small HF dataset (5 seconds at 10 Hz)
t0 = DateTime(2024, 1, 1, 0, 0, 0)
times = t0:Millisecond(100):t0 + Millisecond(100)*(50-1)  # 50 samples
vars = [:Ux, :Uy, :Uz, :Ts, :diag_sonic]

# Simple signals with a couple of NaNs (to demonstrate gap filling)
Ux = sin.(range(0, 1, length=50))
Uy = cos.(range(0, 1, length=50))
Uz = 0.1 .* randn(50)
Ts = 20 .+ 0.01 .* randn(50)
diag_sonic = zeros(50)
Ux[10] = NaN; Uy[30] = NaN

data = hcat(Ux, Uy, Uz, Ts, diag_sonic)
hf = DimArray(data, (Ti(collect(times)), Var(vars)))

# No low-frequency data needed for this minimal example
lf = nothing

# 2) Configure steps: QC, despiking, small-gap interpolation, in-memory output
sensor = CSAT3()
qc = PhysicsBoundsCheck()
wind = VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=6.0)
temp = VariableGroup("Sonic T", [:Ts], spike_threshold=6.0)
desp = SimpleSigmundDespiking(variable_groups=[wind, temp])
gap = GeneralInterpolation()  # Linear, max_gap_size=10 by default
out = MemoryOutput()

# 3) Build pipeline (leave other steps as nothing)
pipe = EddyPipeline(
    sensor=sensor,
    quality_control=qc,
    gas_analyzer=nothing,
    despiking=desp,
    gap_filling=gap,
    double_rotation=nothing,
    mrd=nothing,
    output=out,
)

# 4) Run
process!(pipe, hf, lf)

# 5) Inspect results
hf_processed, lf_processed = Peddy.get_results(out)
Ux_processed = hf_processed[Var=At(:Ux)]
println("First 5 Ux values: ", Ux_processed[1:5])
```

---

## Data model in one minute

Peddy uses labeled arrays from DimensionalData.jl:

- High-frequency data (HF): a `DimArray` with dimensions `Ti` (time) and `Var` (variables like `:Ux, :Uy, :Uz, :Ts, :H2O, :P`).

- Low-frequency data (LF): optional `DimArray` with `Ti` and `Var` (e.g., `:TA, :RH`).

You typically get both via `read_data`.

---

## Read data

The simplest input is a directory with .dat/.csv files (see `src/IO/dat_directory.jl`).

```julia
using Peddy

# Choose or construct a sensor (examples below)
sensor = IRGASON()  # or LICOR(...), CSAT3(), etc.

# Configure input directory
input = DotDatDirectory(
    directory = "/path/to/data",
    high_frequency_file_glob = "*fast*",
    high_frequency_file_options = FileOptions(; timestamp_column=:TIMESTAMP, time_format=dateformat"yyyy-mm-dd HH:MM:SS.s"),
    # low_frequency_file_glob = "*slow*",
    # low_frequency_file_options = FileOptions(; timestamp_column=:TIMESTAMP, time_format=dateformat"yyyy-mm-dd HH:MM:SS"),
)

# Read both HF and LF arrays
hf, lf = read_data(input, sensor)
```

Notes:

- HF must include at least `:Ux, :Uy, :Uz, :Ts`. For H2O correction, include `:H2O` and pressure `:P`.

- LF is optional, but needed for H2O correction (`:TA` temperature, `:RH` relative humidity).

---

## Configure processing steps

You can run each step individually or combine them in an `EddyPipeline`.

### 1) Quality control

```julia
qc = PhysicsBoundsCheck()          # checks physical limits; marks invalid as NaN
# Optional: OnlyDiagnostics() if you only want sensor health checks
```

### 2) Gas analyzer H2O calibration

```julia
gas = H2OCalibration()             # pulls calibration coefficients from the sensor
# Requires a sensor that carries calibration coefficients (LICOR)
```

Example sensors with coefficients (see `src/Sensors/`):

```julia
# LICOR example (site-specific values)
sensor = LICOR(calibration_coefficients=H2OCalibrationCoefficients(
    A=4.82004e3,
    B=3.79290e6,
    C=-1.15477e8,
    H2O_Zero=0.7087,
    H20_Span=0.9885,
))
```

### 3) Despiking (Sigmund et al. 2022, modified MAD)

Group variables and set per-group thresholds.

```julia
wind = VariableGroup("Wind", [:Ux, :Uy, :Uz], spike_threshold=6.0)
temp = VariableGroup("Sonic T", [:Ts], spike_threshold=6.0)
gasg = VariableGroup("Gas", [:H2O], spike_threshold=6.0)

desp = SimpleSigmundDespiking(variable_groups=[wind, temp, gasg])
```

### 4) Gap filling (small gaps only)

```julia
gap = GeneralInterpolation()               # Linear() by default, max_gap_size=10
# Or choose a method and variables
# gap = GeneralInterpolation(method=Cubic(), variables=[:Ux,:Uy,:Uz,:Ts,:H2O])
```

### 5) Wind double rotation

```julia
rot = WindDoubleRotation(block_duration_minutes=30.0)
```

### 6) Multi-Resolution Decomposition (MRD)

```julia
mrd = OrthogonalMRD(M=11, a=:Uz, b=:Ts, regular_grid=false)
```

### 7) Output (choose one)

```julia
out = MemoryOutput()                # keep data/results in memory (for exploration)
# out = ICSVOutput("/path/to/outdir")
# out = NetCDFOutput("/path/to/outdir")
# out = OutputSplitter(ICSVOutput("..."), NetCDFOutput("..."))
```

---

## Build and run a pipeline

```julia
pipe = EddyPipeline(
    sensor=sensor,
    quality_control=qc,
    gas_analyzer=gas,
    despiking=desp,
    gap_filling=gap,
    double_rotation=rot,
    mrd=mrd,
    output=out,
)

# Validate data and run all configured steps (skips any set to nothing)
process!(pipe, hf, lf)
```

After running:

- HF is modified in-place by steps like despiking, gap filling, double rotation, H2O correction.

- MRD results are stored in the step:

```julia
res = get_mrd_results(mrd)   # may be nothing if MRD could not run
if res !== nothing
    @show res.scales
    @show size(res.mrd)
    @show res.times[1:min(end,3)]
end
```

---

## Run steps manually (optional)

You can apply steps without a pipeline if you prefer:

```julia
check_data(hf, lf, sensor)                         # validates required variables exist
quality_control!(qc, hf, lf, sensor)
correct_gas_analyzer!(gas, hf, lf, sensor)
despike!(desp, hf, lf)
fill_gaps!(gap, hf, lf)
rotate!(rot, hf, lf)
decompose!(mrd, hf, lf)
write_data(out, hf, lf)
```

---

## Tips and troubleshooting

- __Use Julia 1.11__: always start with `julia +1.11 --project=.`
- __Variables and dims__: HF/LF must have `Var` and `Ti` dimensions. Index variables with `high_frequency_data[Var=At(:Ux)]`.
- __Missing values__: Peddy uses `NaN` representation in arrays for absent/invalid numeric values and handles them internally.
- __Window/block sizes__: Steps compute sizes from the time axis; ensure time is regular.
- __H2O correction__: Needs LF `:TA` and `:RH`, HF `:H2O` and `:P`, plus sensor calibration coefficients.

---

## API reference

```@index
```
