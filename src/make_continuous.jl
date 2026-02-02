export MakeContinuous
export make_continuous!

"""
    MakeContinuous(; step_size_ms=50, max_gap_minutes=5.0)

Pipeline step that ensures a continuous high-frequency time axis by inserting
missing timestamps (up to `max_gap_minutes`) at a fixed resolution given by
`step_size_ms`. All non-time variables for inserted rows are filled with `NaN`.

Gaps larger than `max_gap_minutes` are left untouched (a warning is emitted).

# Fields
- `step_size_ms::Int`: Expected sampling interval in milliseconds (default 50 ms ⇒ 20 Hz).
- `max_gap_minutes::Real`: Maximum gap length to fill (default 5 minutes).
"""
struct MakeContinuous{T<:Real} <: AbstractMakeContinuous
    step_size_ms::Int
    max_gap_minutes::T

    function MakeContinuous(; step_size_ms::Int=50, max_gap_minutes::T=5.0) where {T<:Real}
        step_size_ms > 0 || throw(ArgumentError("step_size_ms must be positive"))
        max_gap_minutes > 0 || throw(ArgumentError("max_gap_minutes must be positive"))
        return new{T}(step_size_ms, max_gap_minutes)
    end
end

"""
    make_continuous!(mc::MakeContinuous, high_frequency_data::DimArray, low_frequency_data; kwargs...)

Insert missing timestamps into `high_frequency_data` (returns a new DimArray).
Rows added contain `NaN` for all non-time variables.

# Notes
- Assumes the DimArray has `Ti` and `Var` dimensions.
- Keeps original ordering; ensures resulting time axis is strictly increasing.
"""
function make_continuous!(
    mc::MakeContinuous,
    high_frequency_data::DimArray,
    low_frequency_data;
    kwargs...
)
    ti_dim = dims(high_frequency_data, Ti)
    n = length(ti_dim)
    n <= 1 && return high_frequency_data

    step_ms_val = mc.step_size_ms
    max_gap_ms_val = round(Int, mc.max_gap_minutes * 60_000)
    logger = get(kwargs, :logger, nothing)

    # --- Pass 1: Count total insertions (no allocations) ---
    total_insertions = _count_total_insertions(ti_dim, step_ms_val, max_gap_ms_val, n)
    total_insertions == 0 && return high_frequency_data

    # --- Pass 2: Build expanded arrays and fill ---
    old_data = parent(high_frequency_data)
    T_elem = eltype(old_data)
    T_time = eltype(ti_dim)
    n_vars = size(old_data, 2)
    new_n = n + total_insertions

    new_matrix = Matrix{T_elem}(undef, new_n, n_vars)
    new_times = Vector{T_time}(undef, new_n)

    _fill_expanded_arrays!(
        new_matrix, new_times, old_data, ti_dim,
        step_ms_val, max_gap_ms_val, n, n_vars, logger, mc.max_gap_minutes
    )

    var_names = val(dims(high_frequency_data, :Var))
    return DimArray(new_matrix, (Ti(new_times), Var(var_names)))
end

"""
    _count_insertions(gap_ms, step_ms) -> Int

Count how many timestamps to insert for a gap of `gap_ms` milliseconds.
"""
@inline function _count_insertions(gap_ms::Int, step_ms::Int)
    return max(0, div(gap_ms, step_ms) - 1)
end

"""
    _count_total_insertions(ti_dim, step_ms, max_gap_ms, n) -> Int

Count total insertions needed across all fillable gaps (no allocations).
"""
function _count_total_insertions(ti_dim, step_ms::Int, max_gap_ms::Int, n::Int)
    total = 0
    @inbounds for i in 2:n
        gap_ms = Dates.value(ti_dim[i] - ti_dim[i - 1])
        if gap_ms > step_ms && gap_ms <= max_gap_ms
            total += _count_insertions(gap_ms, step_ms)
        end
    end
    return total
end

"""
    _log_gap!(logger, t_prev, t_curr, gap_ms, filled, inserted_points, max_gap_minutes)

Log a gap event if logger is provided.
"""
@inline function _log_gap!(logger, t_prev, t_curr, gap_ms::Int, filled::Bool, inserted_points::Int, max_gap_minutes)
    logger === nothing && return nothing
    log_event!(
        logger, :make_continuous, :time_gap;
        start_time=t_prev,
        end_time=t_curr,
        filled=filled,
        inserted_points=inserted_points,
        gap_seconds=gap_ms / 1000
    )
    return nothing
end

"""
    _fill_expanded_arrays!(new_matrix, new_times, old_data, ti_dim, step_ms, max_gap_ms, n, n_vars, logger, max_gap_minutes)

Fill the expanded matrix and time vector by copying original rows and inserting NaN rows.
Recomputes gaps on-the-fly to avoid storing gap specifications.
"""
function _fill_expanded_arrays!(
    new_matrix::Matrix{T},
    new_times::Vector{D},
    old_data::AbstractMatrix{T},
    ti_dim,
    step_ms::Int,
    max_gap_ms::Int,
    n::Int,
    n_vars::Int,
    logger,
    max_gap_minutes
) where {T<:Real, D<:DateTime}
    step_period = Millisecond(step_ms)
    nan_val = T(NaN)
    write_row = 1

    # Copy first row
    @inbounds begin
        for col in 1:n_vars
            new_matrix[write_row, col] = old_data[1, col]
        end
        new_times[write_row] = ti_dim[1]
        write_row += 1
    end

    @inbounds for read_row in 2:n
        t_prev = ti_dim[read_row - 1]
        t_curr = ti_dim[read_row]
        gap_ms_val = Dates.value(t_curr - t_prev)

        # Check for gap that needs filling
        if gap_ms_val > step_ms
            if gap_ms_val <= max_gap_ms
                num_insert = _count_insertions(gap_ms_val, step_ms)
                # Insert NaN rows for the gap
                for k in 1:num_insert
                    for col in 1:n_vars
                        new_matrix[write_row, col] = nan_val
                    end
                    new_times[write_row] = t_prev + k * step_period
                    write_row += 1
                end
                _log_gap!(logger, t_prev, t_curr, gap_ms_val, true, num_insert, max_gap_minutes)
            else
                @warn "Skipping large gap > max_gap_minutes" gap_minutes = gap_ms_val / 60_000.0 max_gap_minutes = max_gap_minutes start = t_prev stop = t_curr
                _log_gap!(logger, t_prev, t_curr, gap_ms_val, false, 0, max_gap_minutes)
            end
        end

        # Copy current row
        for col in 1:n_vars
            new_matrix[write_row, col] = old_data[read_row, col]
        end
        new_times[write_row] = t_curr
        write_row += 1
    end
    return nothing
end
