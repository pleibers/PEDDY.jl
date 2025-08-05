export SimpleSigmundDespiking

using Statistics
using Dates

"""
    SimpleSigmundDespiking(; window_minutes=5.0, spike_threshold=6.0, variables=[:Ux, :Uy, :Uz, :Ts])

Implements the modified MAD (Median Absolute Deviation) filter for spike detection
based on Sigmund et al. (2022). This despiking method:

1. Calculates rolling median and MAD over a specified window
2. Computes deviation patterns using neighboring points
3. Identifies spikes based on combined variable thresholds
4. Sets detected spikes to NaN

# Parameters
- `window_minutes`: Window size in minutes for rolling statistics (default: 5.0)
- `spike_threshold`: Threshold for spike detection (default: 6.0, normalized by 0.6745)
- `variables`: Variables to process for spike detection
"""
struct SimpleSigmundDespiking <: AbstractDespiking
    window_minutes::Float64
    spike_threshold::Float64
    variables::Vector{Symbol}
    
    function SimpleSigmundDespiking(; window_minutes=5.0, spike_threshold=6.0, 
                                   variables=[:Ux, :Uy, :Uz, :Ts])
        new(window_minutes, spike_threshold, variables)
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
    # Get time dimension and calculate sampling frequency
    time_dim = dims(high_frequency_data, Ti)
    if length(time_dim) < 2
        @warn "Insufficient data points for despiking"
        return
    end
    
    # Calculate sampling frequency (assuming regular intervals)
    dt = time_dim[2] - time_dim[1]
    dt_seconds = Dates.value(dt) / 1000.0  # Convert milliseconds to seconds
    freq_hz = 1.0 / dt_seconds  # Frequency in Hz
    
    # Calculate window size in data points (5 minutes default)
    window_size = round(Int, despiking.window_minutes * 60 * freq_hz)
    window_size = max(window_size, 3)  # Minimum window size
    
    # Adjust window size if data is too small (use at most 1/3 of data length)
    data_length = length(dims(high_frequency_data, Ti))
    if window_size > data_length ÷ 3
        window_size = max(data_length ÷ 3, 3)
        @warn "Adjusted window size to $window_size points due to limited data ($(data_length) points)"
    end
    
    println("Processing spike detection with window size: $window_size points")
    
    # Initialize combined deviation array
    combined_deviation = nothing
    variables_processed = 0
    
    # Process each variable
    for var in despiking.variables
        if var ∉ dims(high_frequency_data, Var)
            continue  # Skip if variable doesn't exist
        end
        
        # Get data for this variable
        data_values = @view high_frequency_data[Var=At(var)]
        n_points = length(data_values)
        
        if n_points < window_size
            @warn "Data length ($n_points) smaller than window size ($window_size) for variable $var"
            continue
        end
        
        # Calculate rolling median
        rolling_median = calculate_rolling_median(data_values, window_size)
        
        # Calculate absolute deviations from rolling median
        df_di = abs.(data_values .- rolling_median)
        
        # Calculate MAD (Median Absolute Deviation)
        df_MAD = calculate_rolling_median(df_di, window_size)
        
        # Apply pattern detection using neighboring points
        df_hat = calculate_pattern_deviation(df_di)
        
        # Normalize by MAD
        df_hat_MAD = df_hat ./ (df_MAD .+ 1e-10)  # Add small epsilon to avoid division by zero
        
        # Store normalized deviations for combined spike detection
        variables_processed += 1
        if combined_deviation === nothing
            combined_deviation = copy(df_hat_MAD)
        else
            combined_deviation .+= df_hat_MAD
        end
    end
    
    # Check if any variables were processed
    if combined_deviation === nothing
        @warn "No variables were processed for spike detection"
        return
    end
    
    # Identify spikes based on combined threshold
    spike_threshold_normalized = despiking.spike_threshold / 0.6745
    spike_condition = abs.(combined_deviation) .>= spike_threshold_normalized
    
    # Count and remove spikes
    n_spikes = sum(spike_condition)
    if n_spikes > 0
        println("Detected $n_spikes spikes, setting to NaN")
        
        # Set spikes to NaN for all processed variables
        for var in despiking.variables
            if var ∈ dims(high_frequency_data, Var)
                data_values = @view high_frequency_data[Var=At(var)]
                data_values[spike_condition] .= NaN
            end
        end
        
        # Also check for H2O variables (corrected or original)
        h2o_vars = [:LI_H2Om_corr, :LI_H2Om, :H2O]
        for h2o_var in h2o_vars
            if h2o_var ∈ dims(high_frequency_data, Var)
                # Calculate H2O-specific spike detection
                data_values = @view high_frequency_data[Var=At(h2o_var)]
                rolling_median = calculate_rolling_median(data_values, window_size)
                df_di = abs.(data_values .- rolling_median)
                df_MAD = calculate_rolling_median(df_di, window_size)
                df_hat = calculate_pattern_deviation(df_di)
                df_hat_MAD = df_hat ./ (df_MAD .+ 1e-10)
                
                h2o_spike_condition = abs.(df_hat_MAD) .>= spike_threshold_normalized
                combined_h2o_spikes = spike_condition .| h2o_spike_condition
                
                n_h2o_spikes = sum(combined_h2o_spikes) - sum(spike_condition)
                if n_h2o_spikes > 0
                    println("Detected additional $n_h2o_spikes H2O spikes for $h2o_var")
                end
                
                data_values[combined_h2o_spikes] .= NaN
                break  # Only process the first H2O variable found
            end
        end
    else
        println("No spikes detected")
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
