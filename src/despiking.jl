export SimpleSigmundDespiking, VariableGroup

using Statistics
using Dates

"""
    VariableGroup(name::String, variables::Vector{Symbol}; spike_threshold::Float64=6.0)

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
gas_group = VariableGroup("Gas Analyzer", [:CO2, :H2O], spike_threshold=8.0)
```
"""
struct VariableGroup
    name::String
    variables::Vector{Symbol}
    spike_threshold::Float64
    
    function VariableGroup(name::String, variables::Vector{Symbol}; spike_threshold::Float64=6.0)
        new(name, variables, spike_threshold)
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
        VariableGroup("Sonic Temperature", [:Ts], spike_threshold=5.0),
        VariableGroup("Gas Analyzer", [:CO2, :H2O], spike_threshold=8.0)
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
struct SimpleSigmundDespiking <: AbstractDespiking
    window_minutes::Float64
    variable_groups::Vector{VariableGroup}
    
    function SimpleSigmundDespiking(; window_minutes=5.0, variable_groups=VariableGroup[])
        # Default group if none provided
        if isempty(variable_groups)
            default_group = VariableGroup("Default Sonic", [:Ux, :Uy, :Uz, :Ts], spike_threshold=6.0)
            variable_groups = [default_group]
        end
        new(window_minutes, variable_groups)
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
"""
function calculate_rolling_median(data::AbstractVector, window_size::Int)
    n = length(data)
    result = similar(data)
    half_window = window_size ÷ 2
    
    for i in 1:n
        # Define window bounds with center alignment
        start_idx = max(1, i - half_window)
        end_idx = min(n, i + half_window)
        
        # Extract window data, filtering out NaN values
        window_data = data[start_idx:end_idx]
        valid_data = filter(!isnan, window_data)
        
        if length(valid_data) > 0
            result[i] = median(valid_data)
        else
            result[i] = NaN
        end
    end
    
    return result
end

"""
    calculate_pattern_deviation(df_di::AbstractVector) -> Vector

Calculate pattern deviation using neighboring points:
df_hat = |df_di| - 0.5 * (|df_di[i-1]| + |df_di[i+1]|)
"""
function calculate_pattern_deviation(df_di::AbstractVector)
    n = length(df_di)
    df_hat = similar(df_di)
    
    for i in 1:n
        abs_di = abs(df_di[i])
        
        # Handle boundary conditions
        if i == 1
            neighbor_avg = abs(df_di[2]) / 2.0  # Only right neighbor
        elseif i == n
            neighbor_avg = abs(df_di[n-1]) / 2.0  # Only left neighbor
        else
            neighbor_avg = 0.5 * (abs(df_di[i-1]) + abs(df_di[i+1]))
        end
        
        df_hat[i] = abs_di - 0.5 * neighbor_avg
    end
    
    return df_hat
end

# Helper functions for improved readability

"""
    _calculate_window_size(high_frequency_data::DimArray, window_minutes::Float64) -> Int

Calculate window size in data points from time dimension and desired window duration.
"""
function _calculate_window_size(high_frequency_data::DimArray, window_minutes::Float64)
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
"""
function _calculate_mad_normalized_deviations(variable_data::AbstractVector, window_size_points::Int)
    # Calculate rolling median
    rolling_median_values = calculate_rolling_median(variable_data, window_size_points)
    
    # Calculate absolute deviations from rolling median
    absolute_deviations = abs.(variable_data .- rolling_median_values)
    
    # Calculate MAD (Median Absolute Deviation)
    mad_values = calculate_rolling_median(absolute_deviations, window_size_points)
    
    # Apply pattern detection using neighboring points
    pattern_adjusted_deviations = calculate_pattern_deviation(absolute_deviations)
    
    # Normalize by MAD with small epsilon to avoid division by zero
    epsilon = 1e-10
    normalized_deviations = pattern_adjusted_deviations ./ (mad_values .+ epsilon)
    
    return normalized_deviations
end

"""
    _apply_spike_threshold_and_remove_for_group!(var_group::VariableGroup, high_frequency_data::DimArray, 
                                               group_combined_deviations::Vector, group_idx::Int)

Apply spike detection threshold for a specific variable group and remove detected spikes by setting them to NaN.
Uses the group's own spike threshold.
"""
function _apply_spike_threshold_and_remove_for_group!(var_group::VariableGroup, high_frequency_data::DimArray, 
                                                     group_combined_deviations::Vector, group_idx::Int)
    # Apply threshold (normalized by 0.6745 factor from Sigmund et al.)
    threshold_normalized = var_group.spike_threshold / 0.6745
    spike_indices = abs.(group_combined_deviations) .>= threshold_normalized
    
    # Count detected spikes
    num_spikes_detected = sum(spike_indices)
    
    if num_spikes_detected > 0
        println("    Group $group_idx ('$(var_group.name)'): Detected $num_spikes_detected spikes, setting to NaN")
        
        # Set spikes to NaN for all variables in this group
        for variable_name in var_group.variables
            if variable_name ∈ dims(high_frequency_data, Var)
                variable_data = @view high_frequency_data[Var=At(variable_name)]
                variable_data[spike_indices] .= NaN
            end
        end
    else
        println("    Group $group_idx ('$(var_group.name)'): No spikes detected")
    end
end
