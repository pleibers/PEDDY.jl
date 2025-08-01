struct OnlyDiagnostics <: AbstractQC end

function quality_control!(qc::OnlyDiagnostics, high_frequency_data::DimArray, low_frequency_data::DimArray, sensor::S; kwargs...) where S <: AbstractSensor
    check_diagnostics!(sensor, high_frequency_data)
end
    