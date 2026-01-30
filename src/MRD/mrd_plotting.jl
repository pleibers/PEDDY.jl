# MRD plotting support (RecipesBase)
# Provides a generic payload function for MRD types and a plotting recipe for AbstractMRD.

# Disclaimer: This is fully AI generated, and i do not know if it is useful in a general sense or specific for the MRD implemented here

module MRDPlotting

using ..PEDDY
using RecipesBase
using Dates
using Statistics

# Expose the payload function for extension by other MRD implementations
export mrd_plot_payload

"""
    mrd_plot_payload(m::AbstractMRD) -> (scales, mrd, mrd_std, times)

Return the generic plotting payload for any MRD type:
- `scales::AbstractVector{<:Real}`: dyadic time scales (seconds)
- `mrd::AbstractMatrix{<:Real}`: contributions at (scale, block)
- `mrd_std::AbstractMatrix{<:Real}`: per-scale uncertainty (sample std across windows)
- `times::AbstractVector`: mid-times for each block

Other MRD types should overload this if they do not store results
in the same shape as `OrthogonalMRD`.
"""
function mrd_plot_payload(m::PEDDY.AbstractMRD)
    res = try
        PEDDY.get_mrd_results(m)
    catch
        nothing
    end
    res === nothing && error("No MRD results available. Run decompose! first.")
    return (scales = res.scales, mrd = res.mrd, mrd_std = res.mrd_std, times = res.times)
end

# Internal helpers
_nanfilter(v) = filter(!isnan, v)

function _per_scale_summary(mrd::AbstractMatrix{<:Real})
    M, n = size(mrd)
    med = similar(mrd, M)
    q25 = similar(mrd, M)
    q75 = similar(mrd, M)
    # @inbounds
    for i in 1:M
        row = view(mrd, i, :)
        vals = _nanfilter(collect(row))
        if isempty(vals)
            med[i] = NaN; q25[i] = NaN; q75[i] = NaN
        else
            med[i] = median(vals)
            q25[i] = quantile(vals, 0.25)
            q75[i] = quantile(vals, 0.75)
        end
    end
    return (median = med, q25 = q25, q75 = q75)
end

# Recipe for plotting an AbstractMRD object via Plots.jl
# Usage examples (after using Plots; using PEDDY):
#   plot(mrd_step)                         # heatmap, log-scale y
#   plot(mrd_step; kind=:heatmap)          # explicit heatmap
#   plot(mrd_step; kind=:summary)          # per-scale median with interquartile ribbon
# Keywords:
#   kind::Symbol = :heatmap | :summary
#   metric::Symbol = :mrd      # :mrd or :std
#   logscale::Bool = true      # apply log10 on scale axis
#   clims = nothing            # pass through to heatmap
#   colormap = :viridis        # pass through to heatmap
#   title = nothing
#   xlabel = "Time"
#   ylabel = "Scale (s)"
@recipe function f(m::PEDDY.AbstractMRD; kind = :summary,
                                 metric = :mrd,
                                 logscale = true,
                                 clims = nothing,
                                 colormap = :viridis,
                                 title = nothing,
                                 xlabel = nothing,
                                 ylabel = nothing)
    payload = mrd_plot_payload(m)
    scales, times = payload.scales, payload.times
    mat = metric === :mrd ? payload.mrd : payload.mrd_std

    # Remove custom/alias kwargs from plotattributes to avoid leaking unsupported keys
    delete!(plotattributes, :kind)
    delete!(plotattributes, :metric)
    delete!(plotattributes, :logscale)
    delete!(plotattributes, :colormap)
    # Keep xlabel/ylabel so users can pass custom/LaTeX labels

    @assert size(mat, 1) == length(scales)
    @assert size(mat, 2) == length(times)

    if kind == :heatmap
        seriestype := :heatmap
        xguide --> (xlabel === nothing ? "Time" : xlabel)
        yguide --> (ylabel === nothing ? "Scale (s)" : ylabel)
        legend --> false
        if title !== nothing
            title --> title
        end
        if logscale
            yscale --> :log10
        end
        if clims !== nothing
            clims --> clims
        end
        seriescolor --> colormap
        # (x, y, z) where z[i,j] corresponds to y[i], x[j]
        times, scales, mat
    elseif kind == :summary
        seriestype := :line
        # x is scale axis here
        xguide --> (xlabel === nothing ? "Scale (s)" : xlabel)
        yguide --> (ylabel === nothing ? (metric === :mrd ? "Contribution (×1000)" : "Std (ddof=1)") : ylabel)
        legend --> :topright
        if title !== nothing
            title --> title
        end
        if logscale
            xscale --> :log10
        end
        summ = _per_scale_summary(mat)
        # Apply 1000x scaling for contribution values only (keep std as-is)
        factor = (metric === :mrd) ? 1000 : 1
        factored_median = summ.median .* factor
        factored_q25 = summ.q25 .* factor
        factored_q75 = summ.q75 .* factor
        # Main median line
        @series begin
            label := "median"
            scales, factored_median
        end
        # Ribbon for IQR
        @series begin
            # Show only the shaded IQR region (no top outline)
            label := "quartile range"
            fillrange := factored_q25
            seriestype := :line
            fillalpha := 0.25
            linealpha := 0.0
            linecolor := :transparent
            scales, factored_q75
        end
    else
        error("Unknown kind=$(kind). Use :heatmap or :summary.")
    end
end

end # module
