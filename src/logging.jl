using Dates

struct ProcessingLogEntry
    stage::Symbol
    category::Symbol
    variable::Union{Symbol,Nothing}
    start_time::Union{DateTime,Nothing}
    end_time::Union{DateTime,Nothing}
    details::Dict{Symbol,Any}
end

mutable struct ProcessingLogger
    entries::Vector{ProcessingLogEntry}
    stage_durations::Dict{Symbol,Float64}
end

ProcessingLogger() = ProcessingLogger(ProcessingLogEntry[], Dict{Symbol,Float64}())

function log_event!(logger::ProcessingLogger, stage::Symbol, category::Symbol;
                    variable::Union{Symbol,Nothing}=nothing,
                    start_time::Union{DateTime,Nothing}=nothing,
                    end_time::Union{DateTime,Nothing}=start_time,
                    kwargs...)
    details = Dict{Symbol,Any}(kwargs)
    if start_time !== nothing && end_time === nothing
        end_time = start_time
    end
    if start_time !== nothing && end_time !== nothing && !haskey(details, :duration_seconds)
        duration = Dates.value(end_time - start_time) / 1000
        details[:duration_seconds] = duration
    end
    push!(logger.entries, ProcessingLogEntry(stage, category, variable, start_time, end_time, details))
    return nothing
end
log_event!(::Nothing, ::Symbol, ::Symbol; kwargs...) = nothing

function record_stage_time!(logger::ProcessingLogger, stage::Symbol, seconds::Real)
    logger === nothing && return nothing
    logger.stage_durations[stage] = get(logger.stage_durations, stage, 0.0) + float(seconds)
    return nothing
end
record_stage_time!(::Nothing, ::Symbol, ::Real) = nothing

function write_processing_log(logger::ProcessingLogger, filepath::AbstractString)
    open(filepath, "w") do io
        println(io, "stage,category,variable,start_timestamp,end_timestamp,duration_seconds,details")
        for entry in logger.entries
            println(io, _format_entry(entry))
        end
        for (stage, seconds) in sort(collect(logger.stage_durations); by=x->string(x[1]))
            details = Dict{Symbol,Any}(:duration_seconds => seconds)
            runtime_entry = ProcessingLogEntry(stage, :runtime, nothing, nothing, nothing, details)
            println(io, _format_entry(runtime_entry))
        end
    end
end
write_processing_log(::Nothing, ::AbstractString) = nothing

function _format_entry(entry::ProcessingLogEntry)
    stage = string(entry.stage)
    category = string(entry.category)
    variable = isnothing(entry.variable) ? "" : string(entry.variable)
    start_ts = _format_time(entry.start_time)
    end_ts = _format_time(entry.end_time)
    details, duration_str = _split_details(entry.details)
    return string(stage, ",", category, ",", variable, ",", start_ts, ",", end_ts, ",",
                  duration_str, ",", details)
end

function _format_time(t)
    t === nothing && return ""
    return Dates.format(t, dateformat"yyyy-mm-ddTHH:MM:SS.s")
end

function _split_details(details::Dict{Symbol,Any})
    isempty(details) && return "", ""
    details_copy = copy(details)
    duration_val = ""
    if haskey(details_copy, :duration_seconds)
        duration_val = string(details_copy[:duration_seconds])
        delete!(details_copy, :duration_seconds)
    end
    detail_str = isempty(details_copy) ? "" : _details_string(details_copy)
    return detail_str, duration_val
end

function _details_string(details::Dict{Symbol,Any})
    pairs_str = Vector{String}(undef, length(details))
    idx = 1
    for key in sort(collect(keys(details)); by=string)
        pairs_str[idx] = string(key, "=", details[key])
        idx += 1
    end
    return join(pairs_str, ";")
end

log_index_runs!(::Nothing, ::Symbol, ::Symbol, ::Union{Symbol,Nothing}, ::AbstractVector, ::AbstractVector{Int}; kwargs...) = nothing
function log_index_runs!(logger::ProcessingLogger, stage::Symbol, category::Symbol,
                         variable::Union{Symbol,Nothing}, timestamps::AbstractVector,
                         indices::AbstractVector{Int}; include_run_length::Bool=false,
                         kwargs...)
    logger === nothing && return nothing
    isempty(indices) && return nothing
    sorted = sort(collect(indices))
    run_start = sorted[1]
    prev_idx = run_start
    for idx in Base.Iterators.drop(sorted, 1)
        if idx == prev_idx + 1
            prev_idx = idx
            continue
        end
        if include_run_length
            run_len = prev_idx - run_start + 1
            log_event!(logger, stage, category; variable=variable,
                       start_time=timestamps[run_start], end_time=timestamps[prev_idx],
                       kwargs..., samples_in_run=run_len)
        else
            log_event!(logger, stage, category; variable=variable,
                       start_time=timestamps[run_start], end_time=timestamps[prev_idx], kwargs...)
        end
        run_start = idx
        prev_idx = idx
    end
    if include_run_length
        run_len = prev_idx - run_start + 1
        log_event!(logger, stage, category; variable=variable,
                   start_time=timestamps[run_start], end_time=timestamps[prev_idx],
                   kwargs..., samples_in_run=run_len)
    else
        log_event!(logger, stage, category; variable=variable,
                   start_time=timestamps[run_start], end_time=timestamps[prev_idx], kwargs...)
    end
    return nothing
end

log_mask_runs!(::Nothing, ::Symbol, ::Symbol, ::Union{Symbol,Nothing}, ::AbstractVector, ::AbstractVector{Bool}; kwargs...) = nothing
function log_mask_runs!(logger::ProcessingLogger, stage::Symbol, category::Symbol,
                        variable::Union{Symbol,Nothing}, timestamps::AbstractVector,
                        mask::AbstractVector{Bool}; kwargs...)
    logger === nothing && return nothing
    length(mask) == 0 && return nothing
    last_idx = min(length(timestamps), length(mask))
    last_idx == 0 && return nothing
    start_idx = nothing
    for idx in 1:last_idx
        flag = mask[idx]
        if flag
            if start_idx === nothing
                start_idx = idx
            end
        elseif start_idx !== nothing
            log_event!(logger, stage, category; variable=variable,
                       start_time=timestamps[start_idx], end_time=timestamps[idx-1], kwargs...)
            start_idx = nothing
        end
    end
    if start_idx !== nothing
        log_event!(logger, stage, category; variable=variable,
                   start_time=timestamps[start_idx], end_time=timestamps[last_idx], kwargs...)
    end
    return nothing
end
