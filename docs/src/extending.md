# Extending Peddy.jl

Peddy.jl is designed to be modular and extensible. Each pipeline step is defined by an abstract type and interface, allowing you to implement custom processing steps tailored to your needs.

## Overview of the Extension Architecture

The pipeline is built on abstract types and dispatch:

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

Each step defines a corresponding function that you implement for your custom type.

## Creating a Custom Quality Control Step

### Step 1: Define Your Type

```julia
using Peddy
using DimensionalData

struct CustomQC <: AbstractQC
    threshold::Float64
    variables::Vector{Symbol}
end

function CustomQC(; threshold=3.0, variables=[:Ux, :Uy, :Uz])
    return CustomQC(threshold, variables)
end
```

### Step 2: Implement the Interface Function

```julia
function Peddy.quality_control!(qc::CustomQC, high_frequency_data, low_frequency_data, sensor; kwargs...)
    logger = get(kwargs, :logger, nothing)
    
    for var in qc.variables
        if var in dims(high_frequency_data, Var)
            data_slice = @view high_frequency_data[Var=At(var)]
            
            # Your custom logic here
            mean_val = Peddy.mean_skipnan(data_slice)
            std_val = std(skipmissing(data_slice))
            
            n_removed = 0
            for i in eachindex(data_slice)
                if isfinite(data_slice[i]) && abs(data_slice[i] - mean_val) > qc.threshold * std_val
                    data_slice[i] = NaN
                    n_removed += 1
                end
            end
            
            if n_removed > 0
                @debug "CustomQC: Removed $n_removed outliers from $var"
            end
        end
    end
    
    return nothing
end
```

### Step 3: Use in Pipeline

```julia
custom_qc = CustomQC(threshold=2.5, variables=[:Ux, :Uy, :Uz, :Ts])

pipeline = EddyPipeline(
    sensor=CSAT3(),
    quality_control=custom_qc,
    output=MemoryOutput()
)

process!(pipeline, hf, lf)
```

## Creating a Custom Despiking Step

### Example: Threshold-Based Despiking

```julia
struct ThresholdDespiking <: AbstractDespiking
    threshold::Float64
    variables::Vector{Symbol}
end

function Peddy.despike!(desp::ThresholdDespiking, high_frequency_data, low_frequency_data; kwargs...)
    logger = get(kwargs, :logger, nothing)
    
    for var in desp.variables
        if var in dims(high_frequency_data, Var)
            data_slice = @view high_frequency_data[Var=At(var)]
            
            # Simple threshold-based spike detection
            mean_val = Peddy.mean_skipnan(data_slice)
            std_val = std(skipmissing(data_slice))
            
            n_spikes = 0
            for i in eachindex(data_slice)
                if isfinite(data_slice[i]) && abs(data_slice[i] - mean_val) > desp.threshold * std_val
                    data_slice[i] = NaN
                    n_spikes += 1
                end
            end
            
            if n_spikes > 0 && logger !== nothing
                @debug "ThresholdDespiking: Removed $n_spikes spikes from $var"
            end
        end
    end
    
    return nothing
end
```

## Creating a Custom Gap Filling Step

### Example: Forward-Fill Interpolation

```julia
struct ForwardFillGapFilling <: AbstractGapFilling
    max_gap_size::Int
    variables::Vector{Symbol}
end

function Peddy.fill_gaps!(gf::ForwardFillGapFilling, high_frequency_data, low_frequency_data; kwargs...)
    for var in gf.variables
        if var in dims(high_frequency_data, Var)
            data_slice = @view high_frequency_data[Var=At(var)]
            
            i = 1
            while i <= length(data_slice)
                if isnan(data_slice[i])
                    # Find gap extent
                    gap_start = i
                    while i <= length(data_slice) && isnan(data_slice[i])
                        i += 1
                    end
                    gap_size = i - gap_start
                    
                    # Fill if within threshold
                    if gap_size <= gf.max_gap_size && gap_start > 1
                        last_value = data_slice[gap_start - 1]
                        for j in gap_start:(i-1)
                            data_slice[j] = last_value
                        end
                    end
                else
                    i += 1
                end
            end
        end
    end
    
    return nothing
end
```

## Creating a Custom Output Step

### Example: HDF5 Output

```julia
using HDF5

struct HDF5Output <: AbstractOutput
    filepath::String
end

function Peddy.write_data(output::HDF5Output, high_frequency_data, low_frequency_data; kwargs...)
    h5open(output.filepath, "w") do file
        # Write high-frequency data
        hf_group = create_group(file, "high_frequency")
        hf_group["data"] = parent(high_frequency_data)
        hf_group["variables"] = String.(val(dims(high_frequency_data, Var)))
        hf_group["times"] = collect(dims(high_frequency_data, Ti))
        
        # Write low-frequency data if available
        if low_frequency_data !== nothing
            lf_group = create_group(file, "low_frequency")
            lf_group["data"] = parent(low_frequency_data)
            lf_group["variables"] = String.(val(dims(low_frequency_data, Var)))
            lf_group["times"] = collect(dims(low_frequency_data, Ti))
        end
    end
    
    @info "Data written to $(output.filepath)"
    return nothing
end
```

## Creating a Custom Sensor

### Example: Custom Sonic Anemometer

```julia
struct CustomSonic <: AbstractSensor
    name::String
    required_variables::Vector{Symbol}
end

function CustomSonic()
    return CustomSonic(
        "CustomSonic",
        [:Ux, :Uy, :Uz, :Ts, :diag]
    )
end

function Peddy.needs_data_cols(sensor::CustomSonic)
    return sensor.required_variables
end

function Peddy.check_diagnostics!(sensor::CustomSonic, high_frequency_data; kwargs...)
    # Custom diagnostic checks
    if :diag in dims(high_frequency_data, Var)
        diag = high_frequency_data[Var=At(:diag)]
        n_bad = count(x -> !isfinite(x) || x > 0, diag)
        if n_bad > 0
            @warn "CustomSonic: $n_bad records with bad diagnostics"
        end
    end
    return nothing
end
```

## Best Practices for Custom Steps

### 1. Modify Data In-Place When Possible

Most steps modify `high_frequency_data` in-place for efficiency:

```julia
# Good: modifies in-place
data_slice = @view high_frequency_data[Var=At(var)]
data_slice[i] = new_value

# Avoid: creates copies
new_data = copy(high_frequency_data)
```

### 2. Use the Logger Interface

Integrate with Peddy's logging system for debugging:

```julia
function my_step!(step, hf, lf; kwargs...)
    logger = get(kwargs, :logger, nothing)
    
    if logger !== nothing
        log_event!(logger, :my_step, :event_type; detail="value")
    end
end
```

### 3. Handle Missing Data Gracefully

Use `Peddy.mean_skipnan` and `skipmissing` to handle NaN values:

```julia
# Good: skips NaN
mean_val = Peddy.mean_skipnan(data)
std_val = std(skipmissing(data))

# Avoid: fails on NaN
mean_val = mean(data)  # Returns NaN
```

### 4. Validate Input Data

Check that required variables exist before processing:

```julia
for var in required_vars
    if var ∉ dims(high_frequency_data, Var)
        @warn "Variable $var not found, skipping step"
        return nothing
    end
end
```

### 5. Document Your Step

Include docstrings with examples:

```julia
"""
    MyCustomStep(; param1=default1, param2=default2)

Brief description of what the step does.

# Parameters
- `param1`: Description of param1
- `param2`: Description of param2

# Examples
```julia
step = MyCustomStep(param1=value1)
my_function!(step, hf, lf)
```

# References
If applicable, cite papers or methods used.
"""
struct MyCustomStep <: AbstractPipelineType
    # fields
end
```

## Testing Your Custom Step

```julia
using Test

@testset "MyCustomStep" begin
    # Create test data
    times = DateTime(2024, 1, 1):Millisecond(100):DateTime(2024, 1, 1, 0, 1, 0)
    vars = [:Ux, :Uy, :Uz]
    data = rand(length(vars), length(times))
    hf = DimArray(data, (Var(vars), Ti(times)))
    
    # Test the step
    step = MyCustomStep()
    my_function!(step, hf, nothing)
    
    # Verify results
    @test all(isfinite.(hf) .| isnan.(hf))  # No Inf values
    @test size(hf) == (3, length(times))    # Size unchanged
end
```

## Registering Custom Steps in a Package

If you want to distribute your custom steps as a separate package:

1. Create a new Julia package that depends on Peddy.jl
2. Implement your custom types and functions
3. Export them from your package's module
4. Users can then use your steps like any built-in step

Example package structure:
```
MyPeddyExtension.jl/
├── src/
│   ├── MyPeddyExtension.jl
│   ├── custom_qc.jl
│   ├── custom_despiking.jl
│   └── custom_output.jl
├── test/
│   └── runtests.jl
└── Project.toml
```

## Common Patterns

### Pattern 1: Variable-Specific Processing

```julia
function process_variable!(step, hf, var::Symbol; kwargs...)
    if var in dims(hf, Var)
        data = @view hf[Var=At(var)]
        # Process data
    end
end

function my_step!(step, hf, lf; kwargs...)
    for var in step.variables
        process_variable!(step, hf, var; kwargs...)
    end
end
```

### Pattern 2: Block-Based Processing

```julia
function my_step!(step, hf, lf; kwargs...)
    times = collect(dims(hf, Ti))
    block_size = _calculate_block_size(hf, step.block_duration_minutes)
    
    for block_start in 1:block_size:length(times)
        block_end = min(block_start + block_size - 1, length(times))
        block_indices = block_start:block_end
        
        # Process block
        process_block!(step, hf, block_indices)
    end
end
```

### Pattern 3: Conditional Processing

```julia
function my_step!(step, hf, lf; kwargs...)
    # Only process if required variables exist
    required = [:Ux, :Uy, :Uz]
    if !all(var -> var in dims(hf, Var), required)
        @warn "Required variables not found, skipping step"
        return nothing
    end
    
    # Process data
end
```

## Troubleshooting Custom Steps

### Issue: Data Not Modified

**Problem:** Changes to data don't persist after the function returns.

**Solution:** Use `@view` to create a view instead of a copy:
```julia
# Wrong: creates a copy
data_slice = high_frequency_data[Var=At(var)]
data_slice[i] = NaN  # Modifies copy, not original

# Correct: creates a view
data_slice = @view high_frequency_data[Var=At(var)]
data_slice[i] = NaN  # Modifies original
```

### Issue: Type Instability

**Problem:** Function performance degrades with certain input types.

**Solution:** Use type parameters and dispatch:
```julia
# Good: type-stable
function my_step!(step::MyStep{T}, hf::DimArray, lf; kwargs...) where T
    # Implementation
end

# Avoid: type-unstable
function my_step!(step, hf, lf; kwargs...)
    # Implementation
end
```

### Issue: Memory Usage

**Problem:** Large data causes memory issues.

**Solution:** Process in chunks:
```julia
function my_step!(step, hf, lf; kwargs...)
    chunk_size = 10000  # Process 10k samples at a time
    for i in 1:chunk_size:length(dims(hf, Ti))
        chunk_end = min(i + chunk_size - 1, length(dims(hf, Ti)))
        chunk_indices = i:chunk_end
        process_chunk!(step, hf, chunk_indices)
    end
end
```

## See Also

- [API Reference](api.md) - Complete API documentation
- [Tutorial](index.md) - Practical examples
- [Best Practices](best_practice.md) - Julia development guidelines
