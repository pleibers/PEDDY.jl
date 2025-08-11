export Non-OrthogonalMRD, get_mrd_results

using Dates

"""
    Non-OrthogonalMRD(; M=11, Mx=0, shift=256, a=:Uz, b=:Ts, gap_threshold_seconds=10.0, normalize=false)

Multi-Resolution Decomposition (MRD) step adapted from the pepy project (Vickers & Mahrt 2003; Howell & Mahrt 1997).

Computes an orthogonal multiresolution covariance between variables `a` and `b` over
sliding, gap-aware blocks of length 2^M samples, stepped by `shift` samples.

Minimal results are stored inside the struct and can be retrieved with `get_mrd_results`.

# Parameters
- `M::Int`: Maximum scale exponent; block length is 2^M samples (default 11)
- `Mx::Int`: Lowest scale to include (0 means include all scales 1..M)
- `shift::Int`: Step size in samples between successive MRD blocks
- `a::Symbol`: First variable (e.g., :Uz)
- `b::Symbol`: Second variable (e.g., :Ts)
- `gap_threshold_seconds::Real`: Maximum allowed time gap within a block
- `normalize::Bool`: If true, normalizes MRD using centered moving-average of a*b

# Notes
- Uses `mean_skipnan` to ignore NaNs, consistent with the package style.
- Does not mutate the data; only computes decomposition and stores results.
"""
mutable struct Non-OrthogonalMRD{T<:Real} <: AbstractMRD
    M::Int
    Mx::Int
    shift::Int
    a::Symbol
    b::Symbol
    gap_threshold_seconds::T
    normalize::Bool
    results::Union{Nothing, NamedTuple}

    function Non-OrthogonalMRD(; number_type=Float64, M::Int=11, Mx::Int=0, shift::Int=256,
                           a::Symbol=:Uz, b::Symbol=:Ts,
                           gap_threshold_seconds::Real=10.0,
                           normalize::Bool=false)
        gap_thr = convert(number_type, gap_threshold_seconds)
        new{number_type}(M, Mx, shift, a, b, gap_thr, normalize, nothing)
    end
end

"""
    decompose!(m::Non-OrthogonalMRD, high_frequency_data::DimArray, low_frequency_data; kwargs...)

Run the MRD on high-frequency data for variables `m.a` and `m.b`.
Stores results in `m.results` as a NamedTuple with fields:
- `scales`: Vector of time scales in seconds for indices 1..M (2^i * dt)
- `mrd`: Matrix of size (M, nblocks) with MRD per scale and block
- `times`: Vector of midpoint times for each block
"""
function decompose!(m::Non-OrthogonalMRD, high_frequency_data::DimArray, low_frequency_data; kwargs...)
    # Validate variables exist
    for var in (m.a, m.b)
        if var ∉ dims(high_frequency_data, Var)
            @warn "Variable $(var) not found in data, skipping MRD"
            m.results = nothing
            return nothing
        end
    end

    # Extract time dimension and sampling period (seconds)
    time_dim = dims(high_frequency_data, Ti)
    num_samples = length(time_dim)
    if num_samples < 2
        @warn "Not enough samples for MRD"
        m.results = nothing
        return nothing
    end

    sampling_period_seconds = _sampling_period_seconds(time_dim)

    # Detect large gaps (true if a gap occurs after index i)
    gap_after_flags = _detect_gaps_after(time_dim, m.gap_threshold_seconds)
    gap_prefix_sum = cumsum(Int.(gap_after_flags))

    # Block configuration
    block_length = 2^m.M
    block_shift = m.shift
    if block_length > num_samples
        @warn "Block length 2^M=$(block_length) exceeds data length $(num_samples); using single block"
    end

    # Precompute normalization series if requested
    normalization_series = nothing
    if m.normalize
        a_full = high_frequency_data[Var(m.a), Ti(1:num_samples)][:]
        b_full = high_frequency_data[Var(m.b), Ti(1:num_samples)][:]
        product_series = similar(a_full)
        @inbounds for i in eachindex(product_series)
            product_series[i] = a_full[i] * b_full[i]
        end
        small_window = 2^11
        large_window = 2^m.M
        tmp_avg = _moving_average_centered(product_series, small_window)
        normalization_series = _moving_average_centered(tmp_avg, large_window)
    end

    # Iterate blocks
    mrd_columns_per_block = Vector{Vector{Float64}}()
    block_mid_times = Vector{eltype(time_dim)}()

    block_start_index = 1
    while block_start_index + block_length - 1 <= num_samples
        block_end_index = block_start_index + block_length - 1

        # Check that no large gap occurs inside [block_start_index, block_end_index]
        has_internal_gap = (gap_prefix_sum[block_end_index - 1] - (block_start_index >= 2 ? gap_prefix_sum[block_start_index - 1] : 0)) > 0
        if !has_internal_gap
            a_block = high_frequency_data[Var(m.a), Ti(block_start_index:block_end_index)][:]
            b_block = high_frequency_data[Var(m.b), Ti(block_start_index:block_end_index)][:]
            scale_covariances = _mrd_block(a_block, b_block, m.M, m.Mx)

            if m.normalize
                mid_index = block_start_index + (block_end_index - block_start_index) ÷ 2
                denom = (normalization_series === nothing ? 1.0 : normalization_series[mid_index])
                norm_factor = sum(@view scale_covariances[1:min(11, length(scale_covariances))]) / denom
                if isfinite(norm_factor) && norm_factor != 0.0
                    @. scale_covariances = scale_covariances / norm_factor
                end
            end

            push!(mrd_columns_per_block, scale_covariances)
            push!(block_mid_times, time_dim[block_start_index + (block_end_index - block_start_index) ÷ 2])
        end

        block_start_index += block_shift
    end

    # Assemble results matrix M x nblocks (pad columns if needed)
    nblocks = length(mrd_columns_per_block)
    if nblocks == 0
        @warn "No MRD blocks computed (gaps or configuration)"
        m.results = nothing
        return nothing
    end

    M = m.M
    mrd_mat = fill(NaN, M, nblocks)
    for (j, col) in enumerate(mrd_columns_per_block)
        @inbounds for i in 1:min(M, length(col))
            mrd_mat[i, j] = col[i]
        end
    end

    scales = [2.0^i * sampling_period_seconds for i in 1:M]
    m.results = (scales=scales, mrd=mrd_mat, times=block_mid_times)
    return nothing
end

"""
    get_mrd_results(m::Non-OrthogonalMRD)

Return MRD results stored in the step, or `nothing` if not computed.
"""
get_mrd_results(m::Non-OrthogonalMRD) = m.results


# -------------------- Internals --------------------

"""
    _sampling_period_seconds(ti_dim) -> Float64

Compute the sampling period in seconds from the first two time coordinates.
"""
function _sampling_period_seconds(ti_dim)
    if length(ti_dim) < 2
        return 0.0
    end
    Δt = ti_dim[2] - ti_dim[1]
    # Convert to seconds (Dates.value returns milliseconds for Millisecond period)
    return Dates.value(Δt) / 1000.0
end

"""
    _detect_gaps_after(ti_dim, threshold_seconds) -> Vector{Bool}

Boolean vector where element i is true if there is a gap after index i (i.e., between i and i+1).
"""
function _detect_gaps_after(ti_dim, threshold_seconds)
    n = length(ti_dim)
    flags = falses(n)
    if n < 2
        return flags
    end
    thr = float(threshold_seconds)
    @inbounds for i in 1:(n - 1)
        dt = ti_dim[i + 1] - ti_dim[i]
        sec = Dates.value(dt) / 1000.0
        flags[i] = (sec > thr)
    end
    return flags
end

"""
    _mrd_block(a::AbstractVector{<:Real}, b::AbstractVector{<:Real}, M::Int, Mx::Int) -> Vector{Float64}

Compute MRD for a single block of length 2^M samples, returning a vector of size M
with entries corresponding to scales 1..M (1-indexed).
"""
function _mrd_block(a::AbstractVector{<:Real}, b::AbstractVector{<:Real}, M::Int, Mx::Int)
    @assert length(a) == length(b)
    n = length(a)
    @assert n == 2^M "Block length must be 2^M"

    # Working copies for in-place mean removal per scale
    working_a = collect(float.(a))
    working_b = collect(float.(b))

    scale_covariances = fill(0.0, M)  # 1..M

    # Iterate from largest scale current_scale = M down to Mx+1
    for scale_offset in 0:(M - Mx - 1)
        current_scale = M - scale_offset
        window_length = 2^current_scale
        num_windows = Int(round((2.0^M) / window_length))  # = 2^(M-current_scale)

        # Window means and mean removal
        accumulated_covariance = 0.0
        valid_window_count = 0

        for window_index in 0:(num_windows - 1)
            start_index = Int(round(window_index * window_length)) + 1  # 1-based
            # Compute NaN-skipping means in [start_index, start_index + window_length - 1]
            window_mean_a = mean_skipnan(@view working_a[start_index:(start_index + window_length - 1)])
            window_mean_b = mean_skipnan(@view working_b[start_index:(start_index + window_length - 1)])

            # Subtract window means in-place
            @inbounds for t in start_index:(start_index + window_length - 1)
                if !isnan(working_a[t])
                    working_a[t] -= window_mean_a
                end
                if !isnan(working_b[t])
                    working_b[t] -= window_mean_b
                end
            end

            # Accumulate covariance of window means
            if !(isnan(window_mean_a) || isnan(window_mean_b))
                accumulated_covariance += window_mean_a * window_mean_b
                valid_window_count += 1
            end
        end

        if valid_window_count > 1
            scale_covariances[current_scale] = accumulated_covariance / valid_window_count
        else
            scale_covariances[current_scale] = NaN
        end
    end

    return scale_covariances
end

"""
    _moving_average_centered(x::AbstractVector{<:Real}, window::Int) -> Vector{Float64}

Centered moving-average with NaN skipping and min_periods=1.
"""
function _moving_average_centered(x::AbstractVector{<:Real}, window::Int)
    n = length(x)
    out = Vector{Float64}(undef, n)
    half = window ÷ 2
    @inbounds for i in 1:n
        lo = max(1, i - half)
        hi = min(n, i + half)
        out[i] = mean_skipnan(@view x[lo:hi])
    end
    return out
end

