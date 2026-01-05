import Foundation

/// Formats file sizes using binary unit thresholds while respecting the caller's locale.
/// Uses KB/MB/GB labels for readability (matching the rest of the app).
func localizedFileSizeString(bytes: Int64, locale: Locale) -> String {
    let clampedBytes = max(Int64(0), bytes)

    let unit: UnitInformationStorage
    let value: Double
    if clampedBytes >= 1_073_741_824 {
        unit = .gigabytes
        value = Double(clampedBytes) / 1_073_741_824.0
    } else if clampedBytes >= 1_048_576 {
        unit = .megabytes
        value = Double(clampedBytes) / 1_048_576.0
    } else if clampedBytes >= 1024 {
        unit = .kilobytes
        value = Double(clampedBytes) / 1024.0
    } else {
        unit = .bytes
        value = Double(clampedBytes)
    }

    let formatter = MeasurementFormatter()
    formatter.locale = locale
    formatter.unitOptions = .providedUnit
    formatter.unitStyle = .medium
    formatter.numberFormatter.locale = locale
    formatter.numberFormatter.minimumFractionDigits = 0
    switch unit {
    case .megabytes, .gigabytes:
        formatter.numberFormatter.maximumFractionDigits = value < 10 ? 1 : 0
    default:
        formatter.numberFormatter.maximumFractionDigits = 0
    }

    return formatter.string(from: Measurement(value: value, unit: unit))
}
