# Data Format & Architecture

## Overview

PEDDY.jl uses [DimensionalData.jl](https://rafaqz.github.io/DimensionalData.jl/dev/) for all data representation. This provides labeled, dimension-aware arrays that make code more readable and less error-prone than plain matrices.

## DimensionalData Basics

### What is a DimArray?

A `DimArray` is a labeled array with named dimensions and coordinates:

```julia
using DimensionalData

# Create a simple DimArray
data = rand(3, 100)
vars = [:Ux, :Uy, :Uz]
times = DateTime(2024, 1, 1):Millisecond(100):DateTime(2024, 1, 1, 0, 0, 10)

arr = DimArray(data, (Var(vars), Ti(times)))

# Access by label (not index!)
ux = arr[Var=At(:Ux)]           # Get Ux variable
slice = arr[Ti=At(times[1])]    # Get first time slice
```

### Why DimensionalData?

1. **Type safety**: Dimensions are checked at compile time
2. **Readability**: `arr[Var=At(:Ux)]` is clearer than `arr[1, :]`
3. **Robustness**: Reordering dimensions doesn't break code
4. **Metadata**: Can attach units, descriptions, etc.

## PEDDY Data Format

### High-Frequency Data

High-frequency data represents fast measurements (typically 10-20 Hz):

```julia
using DimensionalData
using Dates

# Typical structure
times_hf = DateTime(2024, 1, 1, 0, 0, 0):Millisecond(50):DateTime(2024, 1, 1, 23, 59, 59)
vars_hf = [:Ux, :Uy, :Uz, :Ts, :H2O, :P, :CO2, :diag_sonic]

hf = DimArray(
    rand(length(vars_hf), length(times_hf)),
    (Var(vars_hf), Ti(times_hf))
)
```

**Dimensions:**
- `Var`: Variable names (symbols)
- `Ti`: Time axis (DateTime objects)

**Required Variables (sensor-dependent):**
- `Ux, Uy, Uz`: Wind components (m/s)
- `Ts`: Sonic temperature (°C)
- `diag_sonic`: Sonic anemometer diagnostics (0 = good)

**Optional Variables:**
- `H2O`: Water vapor concentration
- `CO2`: Carbon dioxide concentration
- `P`: Atmospheric pressure (Pa)
- `LI_H2Om`: LI-COR H2O measurement
- `LI_H2Om_corr`: Corrected H2O

### Low-Frequency Data

Low-frequency data represents slow measurements (typically 1 Hz or slower):

```julia
times_lf = DateTime(2024, 1, 1, 0, 0, 0):Second(1):DateTime(2024, 1, 1, 23, 59, 59)
vars_lf = [:TA, :RH, :P, :other_var]

lf = DimArray(
    rand(length(vars_lf), length(times_lf)),
    (Var(vars_lf), Ti(times_lf))
)
```

**Common Variables:**
- `TA`: Air temperature (°C)
- `RH`: Relative humidity (%)
- `P`: Atmospheric pressure (Pa)
- `PRECIP`: Precipitation (mm)
- `WS`: Wind speed (m/s)

**Low-frequency data is optional** and only needed for certain steps (e.g., H2O correction).

## Accessing Data

### By Variable

```julia
# Get all values for a variable
ux = hf[Var=At(:Ux)]           # Returns 1D array
uy = hf[Var=At(:Uy)]

# Get multiple variables
wind = hf[Var=In([:Ux, :Uy, :Uz])]  # Returns 3×N array
```

### By Time

```julia
# Get data at specific time
t0 = DateTime(2024, 1, 1, 12, 0, 0)
slice = hf[Ti=At(t0)]          # Returns all variables at t0

# Get time range
t_start = DateTime(2024, 1, 1, 0, 0, 0)
t_end = DateTime(2024, 1, 1, 1, 0, 0)
subset = hf[Ti=Between(t_start, t_end)]
```

### By Index

```julia
# Get by integer index (less preferred, but works)
first_row = hf[1, :]           # First variable, all times
first_col = hf[:, 1]           # All variables, first time
```

### Using Views

For in-place modification, use `@view`:

```julia
# Create a view (doesn't copy data)
ux_view = @view hf[Var=At(:Ux)]
ux_view[1] = 999.0             # Modifies original hf

# Without @view (creates a copy)
ux_copy = hf[Var=At(:Ux)]
ux_copy[1] = 999.0             # Doesn't modify hf
```

## Dimensions and Coordinates

### Var Dimension

The `Var` dimension holds variable names:

```julia
var_dim = dims(hf, Var)
var_names = val(var_dim)       # Get the actual symbols
@show var_names                # [:Ux, :Uy, :Uz, ...]

# Check if variable exists
:Ux in var_names               # true
:unknown in var_names          # false
```

### Ti Dimension

The `Ti` dimension holds time coordinates:

```julia
time_dim = dims(hf, Ti)
times = collect(time_dim)      # Convert to Vector
n_samples = length(time_dim)

# Get time range
t_first = times[1]
t_last = times[end]
duration = t_last - t_first

# Check time regularity
time_diffs = diff(times)
is_regular = all(x -> x == time_diffs[1], time_diffs)
```

## Working with Missing Data

PEDDY.jl uses `NaN` to represent missing values:

```julia
# Check for missing values
n_missing = count(isnan, hf)
n_valid = count(isfinite, hf)

# Get valid data only
valid_data = hf[isfinite.(hf)]

# Use skipmissing for statistics
using Statistics
mean_ux = mean(skipmissing(hf[Var=At(:Ux)]))
std_ux = std(skipmissing(hf[Var=At(:Ux)]))

# PEDDY's mean_skipnan function
mean_ux = PEDDY.mean_skipnan(hf[Var=At(:Ux)])
```

## Data Validation

### Check Required Variables

```julia
function validate_data(hf, lf, sensor)
    # Check dimensions
    if !(:Var in DimensionalData.name.(dims(hf)))
        error("High-frequency data must have Var dimension")
    end
    if !(:Ti in DimensionalData.name.(dims(hf)))
        error("High-frequency data must have Ti dimension")
    end
    
    # Check required variables
    required = PEDDY.needs_data_cols(sensor)
    available = val(dims(hf, Var))
    
    for var in required
        if var ∉ available
            error("Missing required variable: $var")
        end
    end
end
```

### Check Time Axis

```julia
function validate_time_axis(hf)
    times = collect(dims(hf, Ti))
    
    # Check monotonicity
    if !issorted(times)
        error("Time axis is not sorted")
    end
    
    # Check for duplicates
    if length(unique(times)) < length(times)
        error("Time axis has duplicate values")
    end
    
    # Check regularity (optional)
    time_diffs = diff(times)
    if !all(x -> x == time_diffs[1], time_diffs)
        @warn "Time axis is not regular"
    end
end
```

## Data Shapes and Sizes

### Understanding Array Shapes

```julia
hf = DimArray(
    rand(5, 1000),
    (Var([:Ux, :Uy, :Uz, :Ts, :H2O]), Ti(times))
)

# Shape information
size(hf)                       # (5, 1000)
size(hf, 1)                   # 5 (number of variables)
size(hf, 2)                   # 1000 (number of time points)

# Dimension sizes
length(dims(hf, Var))         # 5
length(dims(hf, Ti))          # 1000

# Parent array (underlying matrix)
parent_data = parent(hf)      # Returns the 5×1000 matrix
```

### Creating Arrays of Different Shapes

```julia
# Column-major (variables × time) - PEDDY standard
hf = DimArray(
    rand(5, 1000),
    (Var(vars), Ti(times))
)

# Row-major (time × variables) - requires transpose
data_row_major = rand(1000, 5)
hf = DimArray(
    data_row_major',           # Transpose to (vars, times)
    (Var(vars), Ti(times))
)
```

## Data Type Considerations

### Float Precision

```julia
# Float64 (default, recommended)
hf = DimArray(
    rand(Float64, 5, 1000),
    (Var(vars), Ti(times))
)

# Float32 (saves memory, less precision)
hf = DimArray(
    rand(Float32, 5, 1000),
    (Var(vars), Ti(times))
)

# Check element type
eltype(hf)                     # Float64 or Float32
```

### Integer Diagnostics

Diagnostic fields are often integers:

```julia
# Diagnostic with integer type
diag = zeros(Int32, 1000)
hf_with_diag = DimArray(
    hcat(wind_data, diag),
    (Var([:Ux, :Uy, :Uz, :diag]), Ti(times))
)
```

## Performance Considerations

### Memory Layout

```julia
# Efficient: contiguous in memory
hf = DimArray(
    rand(5, 1000),
    (Var(vars), Ti(times))
)

# Less efficient: non-contiguous
hf_transposed = permutedims(hf)
```

### In-Place Operations

```julia
# Efficient: modifies in-place
ux_view = @view hf[Var=At(:Ux)]
ux_view .= ux_view .* 2.0

# Less efficient: creates intermediate arrays
hf[Var=At(:Ux)] = hf[Var=At(:Ux)] .* 2.0
```

### Iteration

```julia
# Efficient: iterate over variables
for var in val(dims(hf, Var))
    data = @view hf[Var=At(var)]
    # Process data
end

# Less efficient: iterate over indices
for i in 1:size(hf, 1)
    data = @view hf[i, :]
    # Process data
end
```

## Modifying Data

### In-Place Modifications

```julia
# Modify a variable
hf[Var=At(:Ux)] .= 0.0

# Modify with condition
ux = @view hf[Var=At(:Ux)]
ux[ux .> 100] .= NaN

# Modify time slice
hf[:, 1] .= NaN
```

### Creating New Arrays

```julia
# Copy entire array
hf_copy = copy(hf)

# Copy specific variable
ux_copy = copy(hf[Var=At(:Ux)])

# Create new array with subset of variables
subset_vars = [:Ux, :Uy, :Uz]
hf_subset = hf[Var=In(subset_vars)]
```

### Adding Variables

```julia
# Add a new variable
new_var_data = rand(length(dims(hf, Ti)))
hf_new = DimArray(
    hcat(parent(hf), new_var_data),
    (Var(vcat(val(dims(hf, Var)), :new_var)), Ti(dims(hf, Ti)))
)
```

## Coordinate Systems

### Time Coordinates

```julia
# Regular time axis
times = DateTime(2024, 1, 1):Millisecond(50):DateTime(2024, 1, 1, 1, 0, 0)

# Irregular time axis (still valid)
times = [
    DateTime(2024, 1, 1, 0, 0, 0),
    DateTime(2024, 1, 1, 0, 0, 0.050),
    DateTime(2024, 1, 1, 0, 0, 0.150),  # Gap here
    DateTime(2024, 1, 1, 0, 0, 0.200),
]

hf = DimArray(data, (Var(vars), Ti(times)))
```

### Variable Coordinates

```julia
# Variables are just symbols
vars = [:Ux, :Uy, :Uz, :Ts]

# Can use any symbols
vars = [:u, :v, :w, :T]
vars = [:wind_x, :wind_y, :wind_z, :temperature]

hf = DimArray(data, (Var(vars), Ti(times)))
```

## Metadata and Attributes

### Adding Metadata

```julia
using DimensionalData

# Create DimArray with metadata
hf = DimArray(
    data,
    (Var(vars), Ti(times)),
    name="high_frequency_data",
    metadata=Dict(
        "site" => "Davos",
        "elevation" => 1639,
        "sampling_rate" => "20 Hz"
    )
)

# Access metadata
@show hf.metadata
```

### Variable Metadata

PEDDY.jl provides `VariableMetadata` for detailed variable information:

```julia
using PEDDY

# Get default metadata
meta = get_default_metadata(:Ux)
@show meta.long_name
@show meta.units
@show meta.standard_name

# Get metadata for specific variable
meta = metadata_for(:H2O)
```

## Data Transformation Examples

### Resampling

```julia
# Downsample to lower frequency
downsample_factor = 10
hf_downsampled = DimArray(
    hf[:, 1:downsample_factor:end],
    (Var(dims(hf, Var)), Ti(collect(dims(hf, Ti))[1:downsample_factor:end]))
)
```

### Unit Conversion

```julia
# Convert wind speed from m/s to km/h
hf_kmh = copy(hf)
hf_kmh[Var=At(:Ux)] .*= 3.6
hf_kmh[Var=At(:Uy)] .*= 3.6
hf_kmh[Var=At(:Uz)] .*= 3.6
```

### Coordinate Transformation

```julia
# Rotate wind components
using LinearAlgebra

angle = π / 4  # 45 degrees
ux = hf[Var=At(:Ux)]
uy = hf[Var=At(:Uy)]

ux_rot = ux .* cos(angle) - uy .* sin(angle)
uy_rot = ux .* sin(angle) + uy .* cos(angle)

hf[Var=At(:Ux)] .= ux_rot
hf[Var=At(:Uy)] .= uy_rot
```

## Common Patterns

### Processing All Variables

```julia
for var in val(dims(hf, Var))
    data = @view hf[Var=At(var)]
    # Process data
    data .= process_function(data)
end
```

### Processing Time Windows

```julia
window_size = 1000  # samples
for i in 1:window_size:size(hf, 2)
    window_end = min(i + window_size - 1, size(hf, 2))
    window = hf[:, i:window_end]
    # Process window
end
```

### Combining High and Low Frequency

```julia
# Interpolate low-frequency to high-frequency times
hf_times = collect(dims(hf, Ti))
lf_times = collect(dims(lf, Ti))

# Find corresponding LF indices for each HF time
for (i, hf_time) in enumerate(hf_times)
    # Find nearest LF time
    idx = searchsortednearest(lf_times, hf_time)
    # Use lf[idx] for this HF time
end
```

## See Also

- [API Reference](api.md) - Function documentation
- [Tutorial](index.md) - Practical examples
- [DimensionalData.jl Documentation](https://rafaqz.github.io/DimensionalData.jl/dev/)
