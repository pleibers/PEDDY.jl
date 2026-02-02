"""
    OutputSplitter

Adapter that wraps another `AbstractOutput` and writes multiple files by
splitting the input data into consecutive time blocks.

Fields:
- `output::AbstractOutput`: The underlying writer (e.g., `ICSVOutput`, `NetCDFOutput`).
- `block_duration::Dates.Period`: Size of each time block (e.g., `Dates.Hour(1)`).
- `naming::Symbol`: Suffixing strategy, `:time` (start timestamp + period) or `:index`.
"""

@doc (@doc OutputSplitter) OutputSplitter

@kwdef struct OutputSplitter{O<:AbstractOutput} <: AbstractOutput
    output::O
    block_duration::Dates.Period
    naming::Symbol = :time # :time or :index suffixing strategy
end

# --- Public API ---
"""
    write_data(splitter::OutputSplitter, hf::DimArray, lf::Union{Nothing,DimArray}=nothing; kwargs...) -> nothing

Split `hf` (and optional `lf`) by the time dimension into blocks of
`splitter.block_duration` and delegate each block to the wrapped output.
Returns `nothing`.
"""
function write_data(splitter::OutputSplitter,
                    high_frequency_data::DimArray,
                    low_frequency_data::Union{Nothing,DimArray}=nothing; kwargs...)
    # Determine time dimension and its labels for HF data
    hf_dims = dims(high_frequency_data)
    tdim_idx = findfirst(d -> d isa Ti, hf_dims)
    isnothing(tdim_idx) && error("OutputSplitter: time dimension (Ti) not found in high_frequency_data.dims")

    time_labels = collect(hf_dims[tdim_idx])
    length(time_labels) == 0 && return nothing
    
    # Precompute LF presence and time dimension
    lf_tdim_exists = false
    if low_frequency_data !== nothing
        lf_tdim_exists = !isnothing(findfirst(d -> d isa Ti, dims(low_frequency_data)))
        lf_tdim_exists || error("OutputSplitter: time dimension (Ti) not found in low_frequency_data.dims")
    end

    # Iterate blocks by half-open intervals [t0, t0+Δ) using selectors
    t_cursor = time_labels[1]
    t_last = time_labels[end]
    block_index = 1
    while t_cursor <= t_last
        t_stop = t_cursor + splitter.block_duration
        # HF slice via predicate selector
        hf_block = high_frequency_data[Ti=Where(t -> t >= t_cursor && t < t_stop)]
        if _isempty_time(hf_block)
            # advance and continue
            t_cursor = t_stop
            block_index += 1
            continue
        end

        # LF slice, if present
        lf_block = nothing
        if low_frequency_data !== nothing
            tmp = low_frequency_data[Ti=Where(t -> t >= t_cursor && t < t_stop)]
            lf_block = _isempty_time(tmp) ? nothing : tmp
        end

        # Construct per-block base name: base + firstTimestamp + blockDuration
        new_base = _append_block_suffix(
            _get_base_filename(splitter.output),
            splitter.naming,
            block_index,
            t_cursor,
            splitter.block_duration,
        )
        block_output = _make_block_output(splitter.output, new_base)

        write_data(block_output, hf_block, lf_block; kwargs...)

        block_index += 1
        t_cursor = t_stop
    end
    return nothing
end

# --- Helpers: base filename and reconstruction for known outputs ---

# Extract base filename if available
"""Extract the base filename (without extension) from common output structs."""
function _get_base_filename(out)
    # Try common filename fields; fallback to "output"
    if hasproperty(out, :base_filename)
        base, _ext = splitext(getproperty(out, :base_filename))
        return base
    elseif hasproperty(out, :filename)
        base, _ext = splitext(getproperty(out, :filename))
        return base
    else
        return "output"
    end
end

# Determine if a DimArray block has zero length along time dimension
"""Return `true` if `data` has no entries along the time dimension."""
function _isempty_time(data)
    td = findfirst(d -> d isa Ti, dims(data))
    return isnothing(td) || size(data, td) == 0
end

# Suffix formatting
"""Create a per-block suffix according to `naming` (:index or :time)."""
function _append_block_suffix(base::AbstractString, naming::Symbol, idx::Int, tstart, period)
    if naming === :index
        return string(base, "_block", lpad(string(idx), 4, '0'))
    elseif naming === :time
        return string(base, "_", _fmt_time_label(tstart), "_", _fmt_period(period))
    else
        error("OutputSplitter: unknown naming strategy $(naming). Use :time or :index.")
    end
end

_fmt_time_label(dt::Dates.DateTime) = Dates.format(dt, dateformat"yyyymmddTHHMMSS")
_fmt_time_label(d::Dates.Date) = Dates.format(d, dateformat"yyyymmdd")
_fmt_time_label(x) = string(x) # fallback

_fmt_period(p::Dates.Millisecond) = string(Dates.value(p), "ms")
_fmt_period(p::Dates.Second) = string(Dates.value(p), "s")
_fmt_period(p::Dates.Minute) = string(Dates.value(p), "m")
_fmt_period(p::Dates.Hour) = string(Dates.value(p), "h")
_fmt_period(p::Dates.Day) = string(Dates.value(p), "d")
_fmt_period(p) = replace(string(p), r"[^0-9A-Za-z]+" => "") # generic fallback

# Default: if an output type is not handled explicitly, try to reconstruct via keywords
_make_block_output(out, new_base) = _reconstruct_with_base_filename(out, new_base)

# Attempt generic reconstruction using keyword constructor copying over fields
function _reconstruct_with_base_filename(out, new_base)
    # Only rebuild if the type actually has a filename field
    T = typeof(out)
    fnames = fieldnames(T)
    has_base = any(==( :base_filename), fnames)
    has_file = any(==( :filename), fnames)
    if !(has_base || has_file)
        return out
    end
    vals = ntuple(i -> begin
            f = fnames[i]
            f === :base_filename && return new_base
            f === :filename && return new_base
            return getfield(out, f)
        end, length(fnames))
    return T(vals...)
end

# Explicit methods for known outputs to avoid surprises
if isdefined(@__MODULE__, :ICSVOutput)
    _make_block_output(out::ICSVOutput, new_base) = ICSVOutput(
        base_filename=new_base,
        location=out.location,
        fields=out.fields,
        field_delimiter=out.field_delimiter,
        nodata=out.nodata,
    )
end
if isdefined(@__MODULE__, :NetCDFOutput)
    _make_block_output(out::NetCDFOutput, new_base) = NetCDFOutput(
        base_filename=new_base,
        location=out.location,
        fields=out.fields,
        fill_value=out.fill_value,
    )
end

