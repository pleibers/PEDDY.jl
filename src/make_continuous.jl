export MakeContinuous
export make_continuous!

"""
    MakeContinuous(; step_size_ms=50, max_gap_minutes=5)

Pipeline step that ensures a continuous high-frequency time axis by inserting
missing timestamps (up to `max_gap_minutes`) at a fixed resolution given by
`step_size_ms`. All non-time variables for inserted rows are filled with `NaN`.

Gaps larger than `max_gap_minutes` are left untouched (a warning is emitted).

Fields
- `step_size_ms::Int`: Expected sampling interval in milliseconds (default 50ms => 20 Hz)
- `max_gap_minutes::Real`: Maximum gap length to fill (default 5 minutes)
"""
struct MakeContinuous{T<:Real} <: AbstractMakeContinuous
    step_size_ms::Int
    max_gap_minutes::T
    function MakeContinuous(; step_size_ms::Int=50, max_gap_minutes::T=5.0) where {T<:Real}
        step_size_ms <= 0 && throw(ArgumentError("step_size_ms must be positive"))
        max_gap_minutes <= 0 && throw(ArgumentError("max_gap_minutes must be positive"))
        new{T}(step_size_ms, max_gap_minutes)
    end
end

"""
    make_continuous!(mc::MakeContinuous, high_frequency_data::DimArray, low_frequency_data; kwargs...)

Insert missing timestamps into `high_frequency_data` in-place (returns the
mutated DimArray). Rows added contain `NaN` for all non-time variables.

Notes
- Assumes the DimArray has `Ti` and `Var` dimensions.
- Keeps original ordering; ensures resulting time axis is strictly increasing.
"""
function make_continuous!(mc::MakeContinuous, high_frequency_data::DimArray, low_frequency_data; kwargs...)
    # Extract time vector
    ti_dim = dims(high_frequency_data, Ti)
    times = collect(ti_dim)
    n = length(times)
    if n <= 1
        return high_frequency_data
    end

    step_ns = Millisecond(mc.step_size_ms)
    max_gap = Minute(mc.max_gap_minutes)

    # Accumulate row indices needing insertion specs
    gaps_to_fill = Vector{Tuple{Int,Vector{DateTime}}}()

    for i in 2:n
        t_prev = times[i-1]
        t_cur = times[i]
        D = t_cur - t_prev
        if D > step_ns
            if D <= max_gap
                # Generate intermediate timestamps (exclusive of t_prev, inclusive exclusive of t_cur)
                missing = DateTime[]
                t_next = t_prev + step_ns
                while t_next < t_cur
                    push!(missing, t_next)
                    t_next += step_ns
                end
                if !isempty(missing)
                    push!(gaps_to_fill, (i-1, missing))  # insert after index i-1
                end
            else
                @warn "Skipping large gap > max_gap_minutes" gap_minutes=Dates.value(D)/60000.0 max_gap_minutes=mc.max_gap_minutes start=t_prev stop=t_cur
            end
        end
    end

    if isempty(gaps_to_fill)
        return high_frequency_data
    end

    # Build new time axis and expanded data matrix
    total_new_rows = sum(length(g[2]) for g in gaps_to_fill)
    var_names = val(dims(high_frequency_data, :Var))
    old_data = parent(high_frequency_data)  # matrix (time, vars)
    Ttype = eltype(old_data)
    new_length = n + total_new_rows
    new_matrix = Matrix{Ttype}(undef, new_length, size(old_data,2))
    new_timevec = Vector{eltype(times)}(undef, new_length)

    gap_lookup = Dict{Int,Vector{DateTime}}(gaps_to_fill)
    write_row = 1
    for read_row in 1:n
        # copy original row
        new_matrix[write_row, :] .= old_data[read_row, :]
        new_timevec[write_row] = times[read_row]
        write_row += 1
        # insert gap rows if any after this index
        if haskey(gap_lookup, read_row)
            for t_ins in gap_lookup[read_row]
                new_matrix[write_row, :] .= NaN
                new_timevec[write_row] = t_ins
                write_row += 1
            end
        end
    end

    # Re-wrap into DimArray (same variable order)
    new_da = DimArray(new_matrix, (Ti(new_timevec), Var(var_names)))
    return new_da
end

## NOTE: No-op method for `Nothing` lives in `pipeline.jl` to mirror other steps.
