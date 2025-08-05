export SimpleSigmundDespiking, VariableGroup

using Statistics
using Dates

"""
    VariableGroup(name::String, variables::Vector{Symbol}; spike_threshold::Real=6.0)

Defines a group of variables that are combined for spike detection.

# Parameters
- `name`: Descriptive name for the variable group
- `variables`: Vector of variable symbols to include in this group
- `spike_threshold`: Spike detection threshold for this group (default: 6.0, normalized by 0.6745)

# Examples
```julia
# Wind components group
wind_group = VariableGroup("Wind Components", [:Ux, :Uy, :Uz], spike_threshold=6.0)

# Gas analyzer group with different threshold
gas_group = VariableGroup("Gas Analyzer", [:CO2, :H2O], spike_threshold=6.0)
```
"""
struct VariableGroup{N<:Real}
    name::String
    variables::Vector{Symbol}
    spike_threshold::N
    
    function VariableGroup(name::String, variables::Vector{Symbol}; spike_threshold=6.0)
        new{typeof(spike_threshold)}(name, variables, spike_threshold)
    end
end

"""
    SimpleSigmundDespiking(; window_minutes=5.0, variable_groups=VariableGroup[])

Implements the modified MAD (Median Absolute Deviation) filter for spike detection
based on Sigmund et al. (2022). This despiking method:

1. Calculates rolling median and MAD over a specified window
2. Computes deviation patterns using neighboring points
3. Identifies spikes based on variable group thresholds (each group can have its own threshold)
4. Sets detected spikes to NaN

# Parameters
- `window_minutes`: Window size in minutes for rolling statistics (default: 5.0)
- `variable_groups`: Vector of VariableGroup structs, each with its own threshold

# Examples
```julia
# Default: wind components and temperature combined
SimpleSigmundDespiking()

# Custom groups with different thresholds
SimpleSigmundDespiking(
    variable_groups=[
        VariableGroup("Wind Components", [:Ux, :Uy, :Uz], spike_threshold=6.0),
        VariableGroup("Sonic Temperature", [:Ts], spike_threshold=7.0),
        VariableGroup("Gas Analyzer", [:CO2, :H2O], spike_threshold=6.0)
    ]
)

# Single variables with individual thresholds
SimpleSigmundDespiking(
    variable_groups=[
        VariableGroup("Wind U", [:Ux], spike_threshold=6.0),
        VariableGroup("Wind V", [:Uy], spike_threshold=6.0),
        VariableGroup("Wind W", [:Uz], spike_threshold=7.0)
    ]
)
```
"""
struct SimpleSigmundDespiking{N<:Real} <: AbstractDespiking
    window_minutes::N
    variable_groups::Vector{VariableGroup}
    
    function SimpleSigmundDespiking(; window_minutes=5.0, number_type::DataType=Float64, variable_groups=VariableGroup{number_type}[])
        # Default group if none provided
        if isempty(variable_groups)
            default_group = VariableGroup("Default Sonic", [:Ux, :Uy, :Uz, :Ts], spike_threshold=6.0)
            variable_groups = [default_group]
        end
        new{number_type}(window_minutes, variable_groups)
    end
end

"""
    despike!(despiking::SimpleSigmundDespiking, high_frequency_data::DimArray, low_frequency_data; kwargs...)

Apply the Sigmund et al. (2022) modified MAD filter for spike detection.

The algorithm:
1. Calculates rolling median over specified window
2. Computes absolute deviations from rolling median
3. Calculates MAD (Median Absolute Deviation) over the same window
4. Applies pattern detection using neighboring points
5. Identifies spikes when combined normalized deviations exceed threshold
6. Sets detected spikes to NaN in-place
"""
function despike!(despiking::SimpleSigmundDespiking, high_frequency_data::DimArray, low_frequency_data; kwargs...)
    # Calculate window size from time dimension
    window_size_points = _calculate_window_size(high_frequency_data, despiking.window_minutes)
    
    println("Processing spike detection with window size: $window_size_points points")
    println("Processing $(length(despiking.variable_groups)) variable groups")
    
    # Process each variable group independently
    for (group_idx, var_group) in enumerate(despiking.variable_groups)
        println("  Processing group $group_idx: '$(var_group.name)' with threshold $(var_group.spike_threshold)")
        println("    Variables: $(var_group.variables)")
        
        # Pre-allocate combined deviation array for this group
        num_time_points = length(dims(high_frequency_data, Ti))
        group_combined_deviations = zeros(eltype(high_frequency_data), num_time_points)
        num_variables_in_group = 0
        
        # Process each variable in this group
        for variable_name in var_group.variables
            if variable_name ∉ dims(high_frequency_data, Var)
                continue  # Skip if variable doesn't exist in data
            end
            
            # Extract time series for this variable
            variable_data = @view high_frequency_data[Var=At(variable_name)]
            
            if length(variable_data) < window_size_points
                @warn "Data length ($(length(variable_data))) smaller than window size ($window_size_points) for variable $variable_name"
                continue
            end
            
            # Calculate normalized deviations using MAD filter
            normalized_deviations = _calculate_mad_normalized_deviations(variable_data, window_size_points)
            
            # Accumulate deviations within this group
            num_variables_in_group += 1
            group_combined_deviations .+= normalized_deviations
        end
        
        # Apply spike detection for this group if any variables were processed
        if num_variables_in_group > 0
            _apply_spike_threshold_and_remove_for_group!(var_group, high_frequency_data, 
                                                        group_combined_deviations, group_idx)
        else
            @warn "No variables were processed in group $group_idx: '$(var_group.name)'"
        end
    end
end

"""
    calculate_rolling_median(data::AbstractVector, window_size::Int) -> Vector

Calculate rolling median with center alignment, handling NaN values.
Optimized version that pre-allocates buffers and minimizes allocations.
"""
function calculate_rolling_median(data::AbstractVector, window_size::Int)
    n = length(data)
    result = similar(data)
    half_window = window_size ÷ 2
    
    # Pre-allocate buffer for valid data to avoid repeated allocations
    max_window_size = min(window_size, n)
    valid_buffer = Vector{eltype(data)}(undef, max_window_size)
    
    @inbounds for i in 1:n
        # Define window bounds with center alignment
        start_idx = max(1, i - half_window)
        end_idx = min(n, i + half_window)
        
        # Extract valid (non-NaN) data directly into pre-allocated buffer
        valid_count = 0
        for j in start_idx:end_idx
            if !isnan(data[j])
                valid_count += 1
                valid_buffer[valid_count] = data[j]
            end
        end
        
        if valid_count > 0
            # Use view to avoid allocation and sort only the valid portion
            valid_view = @view valid_buffer[1:valid_count]
            result[i] = median(valid_view)
        else
            result[i] = NaN
        end
    end
    
    return result
end

"""
    calculate_pattern_deviation(absolute_deviations::AbstractVector) -> Vector

Calculate pattern-adjusted deviations using neighboring points:
pattern_deviation = |deviation| - 0.5 * (|neighbor_left| + |neighbor_right|)
Optimized version with vectorized operations and efficient boundary handling.
"""
function calculate_pattern_deviation(absolute_deviations::AbstractVector)
    n = length(absolute_deviations)
    if n < 3
        # For very small arrays, use simple approach
        return abs.(absolute_deviations) .- 0.5 .* abs.(absolute_deviations)
    end
    
    # Pre-compute absolute values once
    abs_deviations = abs.(absolute_deviations)
    pattern_adjusted_deviations = similar(absolute_deviations)
    
    # Handle boundaries explicitly (faster than conditional in loop)
    @inbounds begin
        # First element: only right neighbor
        pattern_adjusted_deviations[1] = abs_deviations[1] - 0.25 * abs_deviations[2]
        
        # Last element: only left neighbor  
        pattern_adjusted_deviations[n] = abs_deviations[n] - 0.25 * abs_deviations[n-1]
        
        # Interior points: vectorized computation
        for i in 2:(n-1)
            neighbor_average = 0.5 * (abs_deviations[i-1] + abs_deviations[i+1])
            pattern_adjusted_deviations[i] = abs_deviations[i] - 0.5 * neighbor_average
        end
    end
    
    return pattern_adjusted_deviations
end

# Helper functions for improved readability

"""
    _calculate_window_size(high_frequency_data::DimArray, window_minutes::Real) -> Int

Calculate window size in data points from time dimension and desired window duration.
"""
function _calculate_window_size(high_frequency_data::DimArray, window_minutes)
    time_dimension = dims(high_frequency_data, Ti)
    
    if length(time_dimension) < 2
        @warn "Insufficient data points for despiking"
        return 3  # Minimum window size
    end
    
    # Calculate sampling frequency (assuming regular intervals)
    time_step = time_dimension[2] - time_dimension[1]
    # FIXME: Preliminary since time dimension format is not yet finalized
    time_step_seconds = Dates.value(time_step) / 1000.0  # Convert milliseconds to seconds
    sampling_frequency_hz = 1.0 / time_step_seconds
    
    # Calculate window size in data points
    window_size_points = round(Int, window_minutes * 60 * sampling_frequency_hz)
    window_size_points = max(window_size_points, 3)  # Ensure minimum window size
    
    # Adjust window size if data is too small (use at most 1/3 of data length)
    total_data_points = length(time_dimension)
    if window_size_points > total_data_points ÷ 3
        window_size_points = max(total_data_points ÷ 3, 3)
        @warn "Adjusted window size to $window_size_points points due to limited data ($total_data_points points)"
    end
    
    return window_size_points
end

"""
    _calculate_mad_normalized_deviations(variable_data::AbstractVector, window_size_points::Int) -> Vector

Calculate MAD-normalized deviations for a single variable using the Sigmund et al. algorithm.
Optimized version that minimizes allocations and reuses intermediate arrays.
"""
function _calculate_mad_normalized_deviations(variable_data::AbstractVector, window_size_points::Int)
    n = length(variable_data)
    
    # Calculate rolling median
    rolling_median_values = calculate_rolling_median(variable_data, window_size_points)
    
    # Calculate absolute deviations from rolling median (reuse this array)
    absolute_deviations = similar(variable_data)
    @inbounds @simd for i in 1:n
        absolute_deviations[i] = abs(variable_data[i] - rolling_median_values[i])
    end
    
    # Calculate MAD (Median Absolute Deviation)
    mad_values = calculate_rolling_median(absolute_deviations, window_size_points)
    
    # Apply pattern detection using neighboring points (modifies absolute_deviations in-place)
    pattern_adjusted_deviations = calculate_pattern_deviation(absolute_deviations)
    
    # Normalize by MAD with small epsilon to avoid division by zero (reuse pattern_adjusted_deviations)
    @inbounds @simd for i in 1:n
        pattern_adjusted_deviations[i] = pattern_adjusted_deviations[i] / (mad_values[i] + 1e-10)
    end
    
    return pattern_adjusted_deviations
end

"""
    _apply_spike_threshold_and_remove_for_group!(variable_group::VariableGroup, high_frequency_data::DimArray, 
                                               combined_normalized_deviations::Vector, group_index::Int)

Apply spike detection threshold for a specific variable group and remove detected spikes by setting them to NaN.
Uses the group's own spike threshold. Optimized version with pre-computed threshold and efficient indexing.
"""
function _apply_spike_threshold_and_remove_for_group!(variable_group::VariableGroup, high_frequency_data::DimArray, 
                                                     combined_normalized_deviations::Vector, group_index::Int)
    # Pre-compute normalized threshold (constant for this group)
    normalized_threshold = variable_group.spike_threshold / 0.6745
    
    # Find spike indices efficiently
    n_time_points = length(combined_normalized_deviations)
    spikes_detected_count = 0
    
    # Count spikes and apply threshold in single pass
    @inbounds for time_index in 1:n_time_points
        if abs(combined_normalized_deviations[time_index]) >= normalized_threshold
            spikes_detected_count += 1
            
            # Set spikes to NaN for all variables in this group immediately
            for variable_name in variable_group.variables
                if variable_name ∈ dims(high_frequency_data, Var)
                    variable_time_series = @view high_frequency_data[Var=At(variable_name)]
                    variable_time_series[time_index] = NaN
                end
            end
        end
    end
    
    # Report results
    if spikes_detected_count > 0
        println("    Group $group_index ('$(variable_group.name)'): Detected $spikes_detected_count spikes, setting to NaN")
    else
        println("    Group $group_index ('$(variable_group.name)'): No spikes detected")
    end
end
