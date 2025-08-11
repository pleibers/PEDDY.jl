export WindDoubleRotation

using Statistics
using Dates

 
"""
    WindDoubleRotation(; block_duration_minutes=30.0, variables=[:Ux, :Uy, :Uz])

Implements double rotation coordinate transformation to align wind measurements
with the mean streamline coordinate system.

The double rotation method:
1. Divides data into blocks of specified duration
2. First rotation: sets mean(v) = 0 by rotating around z-axis
3. Second rotation: sets mean(w) = 0 by rotating around y-axis
4. Applies rotations to transform wind components in-place

# Parameters
- `block_duration_minutes`: Duration of each averaging block in minutes (default: 30.0)
- `variables`: Wind component variables to rotate (default: [:Ux, :Uy, :Uz])

# Examples
```julia
# Default 30-minute blocks
double_rotation = WindDoubleRotation()

# Custom 15-minute blocks
double_rotation = WindDoubleRotation(block_duration_minutes=15.0)

# Custom variables
double_rotation = WindDoubleRotation(Ux=:u, Uy=:v, Uz=:w)
```

# References
Standard eddy covariance double rotation method for coordinate transformation.
"""
struct WindDoubleRotation{N<:Real} <: AbstractDoubleRotation
    block_duration_minutes::N
    Ux::Symbol
    Uy::Symbol
    Uz::Symbol
    
    function WindDoubleRotation(; number_type=Float64, block_duration_minutes=30.0, Ux=:Ux, Uy=:Uy, Uz=:Uz)
        new{number_type}(block_duration_minutes, Ux, Uy, Uz)
    end
end

"""
    rotate!(double_rotation::WindDoubleRotation, high_frequency_data::DimArray, low_frequency_data; kwargs...)

Apply double rotation coordinate transformation to wind measurements.

The algorithm processes data in blocks and applies two sequential rotations:
1. First rotation (θ): Aligns mean wind with x-axis (sets mean v-component to zero)
2. Second rotation (φ): Tilts coordinate system so mean w-component is zero

Modifies the wind components in-place and stores rotation angles in low_frequency_data.
"""
function rotate!(double_rotation::WindDoubleRotation{N}, high_frequency_data::DimArray, low_frequency_data; kwargs...) where {N}
    # Calculate block size from time dimension
    block_size_points = _calculate_block_size(high_frequency_data, double_rotation.block_duration_minutes)
    
    println("Double rotation for blocks of $(double_rotation.block_duration_minutes) minutes")
    println("Block size: $block_size_points points")
    
    # Verify all required variables exist
    for var in [double_rotation.Ux, double_rotation.Uy, double_rotation.Uz]
        if var ∉ dims(high_frequency_data, Var)
            @warn "Variable $var not found in data, skipping double rotation"
            return
        end
    end
    
    # Calculate block indices
    n_time_points = length(dims(high_frequency_data, Ti))
    block_indices = _calculate_block_indices(n_time_points, block_size_points)
    
    println("Processing $(length(block_indices)) blocks")
    
    # Store rotation angles (will be added to low_frequency_data if needed)
    rotation_angles = Vector{NamedTuple{(:theta, :phi), Tuple{N, N}}}()
    
    # Process each block
    for (block_idx, (start_idx, end_idx)) in enumerate(block_indices)
        # Extract wind components for this block
        u_var, v_var, w_var = double_rotation.Ux, double_rotation.Uy, double_rotation.Uz
        
        u_data = high_frequency_data[Var(u_var), Ti(start_idx:end_idx)]
        v_data = high_frequency_data[Var(v_var), Ti(start_idx:end_idx)]
        w_data = high_frequency_data[Var(w_var), Ti(start_idx:end_idx)]
        
        # Create wind matrix [u, v, w]
        wind_matrix = hcat(u_data[:], v_data[:], w_data[:])
        
        # Apply double rotation
        wind_rotated, theta, phi = _apply_double_rotation(wind_matrix)
        
        # Update data in-place with rounded values (5 decimal places)
        high_frequency_data[Var(u_var), Ti(start_idx:end_idx)] .= round.(wind_rotated[:, 1], digits=5)
        high_frequency_data[Var(v_var), Ti(start_idx:end_idx)] .= round.(wind_rotated[:, 2], digits=5)
        high_frequency_data[Var(w_var), Ti(start_idx:end_idx)] .= round.(wind_rotated[:, 3], digits=5)
        
        # Store rotation angles
        push!(rotation_angles, (theta=theta, phi=phi))
    end
    
    println("Double rotation completed for $(length(block_indices)) blocks")
    
    # TODO: Consider storing rotation angles in low_frequency_data if needed
    # This would require extending the low_frequency_data structure
    
    return nothing
end

"""
    _calculate_block_size(data::DimArray, block_duration_minutes) -> Int

Calculate the number of data points in a block based on sampling frequency.
"""
function _calculate_block_size(data::DimArray, block_duration_minutes) 
    time_dim = dims(data, Ti)
    
    if length(time_dim) < 2
        throw(ArgumentError("Need at least 2 time points to calculate sampling frequency"))
    end
    
    # Calculate sampling frequency from time difference
    time_diff = time_dim[2] - time_dim[1]
    # FIXME: Dont know yet which unit this is
    freq_seconds = Dates.value(time_diff) / 1000.0  # Convert to seconds
    
    block_duration_seconds = block_duration_minutes * 60.0
    block_size = round(Int, block_duration_seconds / freq_seconds)
    
    return max(1, block_size)  # Ensure at least 1 point per block
end

"""
    _calculate_block_indices(n_points::Int, block_size::Int) -> Vector{Tuple{Int, Int}}

Calculate start and end indices for each block.
"""
function _calculate_block_indices(n_points::Int, block_size::Int)
    indices = Vector{Tuple{Int, Int}}()
    
    start_idx = 1
    while start_idx <= n_points - block_size
        end_idx = start_idx + block_size - 1
        push!(indices, (start_idx, end_idx))
        start_idx += block_size
    end
    
    # Adjust last block to include remaining points
    if !isempty(indices)
        indices[end] = (indices[end][1], n_points)
    else
        # Handle case where data is shorter than one block
        push!(indices, (1, n_points))
    end
    
    return indices
end

"""
    _apply_double_rotation(wind_matrix::Matrix{N}) where N -> Tuple{Matrix{N}, N, N}

Apply double rotation to wind matrix.

Returns rotated wind matrix and rotation angles (theta, phi).
"""
function _apply_double_rotation(wind_matrix::Matrix{N}) where {N}
    # First rotation: set mean(v) = 0
    mean_u = mean_skipnan(wind_matrix[:, 1])
    mean_v = mean_skipnan(wind_matrix[:, 2])
    
    theta = atan(mean_v, mean_u)
    
    # First rotation matrix (around z-axis)
    cos_theta = cos(theta)
    sin_theta = sin(theta)
    rot1 = [cos_theta -sin_theta 0.0;
            sin_theta  cos_theta 0.0;
            0.0        0.0       1.0]
    
    # Apply first rotation
    wind1 = wind_matrix * rot1
    
    # Second rotation: set mean(w) = 0
    mean_u1 = mean_skipnan(wind1[:, 1])
    mean_w1 = mean_skipnan(wind1[:, 3])
    
    phi = atan(mean_w1, mean_u1)
    
    # Second rotation matrix (around y-axis)
    cos_phi = cos(phi)
    sin_phi = sin(phi)
    rot2 = [cos_phi  0.0 -sin_phi;
            0.0      1.0  0.0;
            sin_phi  0.0  cos_phi]
    
    # Apply second rotation
    wind_rotated = wind1 * rot2
    
    return wind_rotated, theta, phi
end
