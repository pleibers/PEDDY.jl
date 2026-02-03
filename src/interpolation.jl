using DimensionalData
using Interpolations

# Export interpolation types and methods
export InterpolationMethod, Linear, Quadratic, Cubic
export GeneralInterpolation

"""
    InterpolationMethod

Abstract type for different interpolation methods.
"""
abstract type InterpolationMethod end

"""
    Linear <: InterpolationMethod

Linear interpolation method.
"""
struct Linear <: InterpolationMethod end

"""
    Quadratic <: InterpolationMethod

Quadratic interpolation method.
"""
struct Quadratic <: InterpolationMethod end

"""
    Cubic <: InterpolationMethod

Cubic spline interpolation method.
"""
struct Cubic <: InterpolationMethod end

"""
    GeneralInterpolation{T, M} <: AbstractGapFilling

General interpolation gap filling method that interpolates small gaps (≤ max_gap_size consecutive missing values)
in time series data using various interpolation methods via Interpolations.jl.

# Fields
- `max_gap_size::Int`: Maximum number of consecutive missing values to interpolate (default: 10)
- `variables::Vector{Symbol}`: Variables to apply gap filling to
- `method::InterpolationMethod`: Interpolation method to use (Linear, Quadratic, Cubic)
"""
struct GeneralInterpolation{T<:Integer,M<:InterpolationMethod} <: AbstractGapFilling
    max_gap_size::T
    variables::Vector{Symbol}
    method::M
end

# Constructor with defaults
function GeneralInterpolation(; max_gap_size::Int=10,
                              variables::Vector{Symbol}=[:Ux, :Uy, :Uz, :Ts, :H2O, :LI_H2Om,
                                                         :LI_H2Om_corr],
                              method::InterpolationMethod=Linear())
    return GeneralInterpolation(max_gap_size, variables, method)
end

"""
    fill_gaps!(gap_filling::GeneralInterpolation, high_frequency_data, low_frequency_data; kwargs...)

Apply interpolation gap filling to specified variables in the high frequency data.
This replicates the Python pepy interpolation logic within the Peddy.jl pipeline.

# Arguments
- `gap_filling::GeneralInterpolation`: Gap filling configuration
- `high_frequency_data`: DimArray containing high frequency measurements
- `low_frequency_data`: Low frequency data (not used in this implementation)
- `kwargs...`: Additional keyword arguments

# Notes
Modifies `high_frequency_data` in-place by filling small gaps with interpolated values.
Only gaps with ≤ max_gap_size consecutive missing values are filled.
"""
function fill_gaps!(gap_filling::GeneralInterpolation, high_frequency_data,
                    low_frequency_data; kwargs...)
    logger = get(kwargs, :logger, nothing)
    timestamps = logger === nothing ? nothing : collect(dims(high_frequency_data, Ti))
    # Process each specified variable
    for var in gap_filling.variables
        if var in dims(high_frequency_data, Var)
            # Explicitly create a view to ensure in-place modification
            data_slice = @view high_frequency_data[Var=At(var)]
            interpolate_small_gaps!(data_slice, gap_filling.max_gap_size,
                                    gap_filling.method;
                                    logger=logger, variable=var, timestamps=timestamps)
        else
            @debug "Variable $var not found in high frequency data"
        end
    end

    return nothing
end

"""
    interpolate_small_gaps!(data::AbstractArray, max_gap_size::Int, method::InterpolationMethod)

Interpolate small gaps (≤ max_gap_size consecutive missing values) in a time series using the specified interpolation method.
Larger gaps are left as missing values.

# Arguments
- `data`: Array containing the time series data with missing values
- `max_gap_size`: Maximum number of consecutive missing values to interpolate
- `method`: Interpolation method to use (Linear, Quadratic, Cubic)

# Returns
- Modifies `data` in-place, filling small gaps with interpolated values
"""
function interpolate_small_gaps!(data::AbstractArray, max_gap_size::Int,
                                 method::InterpolationMethod; logger=nothing,
                                 variable=nothing, timestamps=nothing)
    n = length(data)
    n == 0 && return data

    # Find missing value positions
    missing_mask = isnan.(data)
    any(missing_mask) || return data  # No missing values

    # Identify consecutive missing value groups
    gap_groups = identify_gap_groups(missing_mask)

    # Only interpolate small gaps
    for (start_idx, end_idx) in gap_groups
        gap_size = end_idx - start_idx + 1
        if gap_size <= max_gap_size
            interpolate_gap!(data, start_idx, end_idx, method)
            if logger !== nothing && timestamps !== nothing && variable !== nothing
                success = all(!isnan(data[i]) for i in start_idx:end_idx)
                category = success ? :gap_filled : :gap_unfilled
                log_event!(logger, :gap_filling, category;
                           variable=variable,
                           start_time=timestamps[start_idx],
                           end_time=timestamps[end_idx],
                           gap_samples=gap_size,
                           method=string(typeof(method)))
            end
        elseif logger !== nothing && timestamps !== nothing && variable !== nothing
            log_event!(logger, :gap_filling, :gap_skipped;
                       variable=variable,
                       start_time=timestamps[start_idx],
                       end_time=timestamps[end_idx],
                       gap_samples=gap_size,
                       method=string(typeof(method)))
        end
    end

    return data
end

"""
    identify_gap_groups(missing_mask::AbstractVector{Bool})

Identify groups of consecutive NaN values and return their start and end indices.
Replicates the Python pandas groupby logic for consecutive NaN detection.

# Arguments
- `missing_mask`: Boolean vector indicating NaN positions

# Returns
- Vector of tuples (start_idx, end_idx) for each consecutive missing group
"""
function identify_gap_groups(missing_mask::AbstractVector{Bool})
    gap_groups = Tuple{Int,Int}[]
    n = length(missing_mask)

    i = 1
    while i <= n
        if missing_mask[i]
            start_idx = i
            # Find end of consecutive missing values
            while i <= n && missing_mask[i]
                i += 1
            end
            end_idx = i - 1
            push!(gap_groups, (start_idx, end_idx))
        else
            i += 1
        end
    end

    return gap_groups
end

"""
    interpolate_gap!(data::AbstractArray, start_idx::Int, end_idx::Int, method::InterpolationMethod)

Perform interpolation for a gap between start_idx and end_idx using the specified method.
Uses nearest valid values before and after the gap, with fallback to forward/backward fill.

# Arguments
- `data`: Array containing the time series data
- `start_idx`: Start index of the gap (inclusive)
- `end_idx`: End index of the gap (inclusive)
- `method`: Interpolation method to use
"""
function interpolate_gap!(data::AbstractArray, start_idx::Int, end_idx::Int,
                          method::InterpolationMethod)
    n = length(data)

    # Find valid data points around the gap
    valid_indices, valid_values = find_valid_neighbors(data, start_idx, end_idx, method)

    if length(valid_indices) >= 2
        # Use Interpolations.jl for sophisticated interpolation
        interpolate_with_method!(data, start_idx, end_idx, valid_indices, valid_values,
                                 method)
    elseif length(valid_indices) == 1
        # Single neighbor - forward or backward fill
        fill_value = valid_values[1]
        for i in start_idx:end_idx
            data[i] = fill_value
        end
    end
    # If no valid neighbors, leave gap unfilled
end

"""
    find_valid_neighbors(data::AbstractArray, start_idx::Int, end_idx::Int, method::InterpolationMethod)

Find valid data points around a gap for interpolation.
The number of points depends on the interpolation method.
"""
function find_valid_neighbors(data::AbstractArray, start_idx::Int, end_idx::Int,
                              method::InterpolationMethod)
    n = length(data)
    valid_indices = Int[]
    valid_values = eltype(data)[]

    # Determine how many points we need based on method
    points_needed = get_points_needed(method)

    # Search backwards from gap
    search_idx = start_idx - 1
    points_before = 0
    while search_idx >= 1 && points_before < points_needed
        if !isnan(data[search_idx])
            pushfirst!(valid_indices, search_idx)
            pushfirst!(valid_values, data[search_idx])
            points_before += 1
        end
        search_idx -= 1
    end

    # Search forwards from gap
    search_idx = end_idx + 1
    points_after = 0
    while search_idx <= n && points_after < points_needed
        if !isnan(data[search_idx])
            push!(valid_indices, search_idx)
            push!(valid_values, data[search_idx])
            points_after += 1
        end
        search_idx += 1
    end

    return valid_indices, valid_values
end

"""
    get_points_needed(method::InterpolationMethod)

Return the minimum number of points needed for each interpolation method.
"""
get_points_needed(::Linear) = 1
get_points_needed(::Quadratic) = 2
get_points_needed(::Cubic) = 2

"""
    interpolate_with_method!(data, start_idx, end_idx, valid_indices, valid_values, method)

Perform interpolation using Interpolations.jl based on the specified method.
"""
function interpolate_with_method!(data::AbstractArray, start_idx::Int, end_idx::Int,
                                  valid_indices::Vector{Int}, valid_values::Vector,
                                  method::Linear)
    # Linear interpolation
    if length(valid_indices) >= 2
        itp = linear_interpolation(valid_indices, valid_values; extrapolation_bc=Flat())
        for i in start_idx:end_idx
            data[i] = itp(i)
        end
    end
end

function interpolate_with_method!(data::AbstractArray, start_idx::Int, end_idx::Int,
                                  valid_indices::Vector{Int}, valid_values::Vector,
                                  method::Quadratic)
    # Quadratic interpolation
    if length(valid_indices) >= 3
        itp = interpolate((valid_indices,), valid_values,
                          Gridded(Quadratic(Periodic(OnGrid()))))
        for i in start_idx:end_idx
            data[i] = itp(i)
        end
    else
        # Fall back to linear if not enough points
        interpolate_with_method!(data, start_idx, end_idx, valid_indices, valid_values,
                                 Linear())
    end
end

function interpolate_with_method!(data::AbstractArray, start_idx::Int, end_idx::Int,
                                  valid_indices::Vector{Int}, valid_values::Vector,
                                  method::Cubic)
    # Cubic spline interpolation
    if length(valid_indices) >= 4
        itp = CubicSplineInterpolation(valid_indices, valid_values)
        for i in start_idx:end_idx
            data[i] = itp(i)
        end
    else
        # Fall back to linear if not enough points
        interpolate_with_method!(data, start_idx, end_idx, valid_indices, valid_values,
                                 Linear())
    end
end
