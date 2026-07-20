import CoreLocation
import Foundation

struct MosquePlace: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let distanceMeters: CLLocationDistance
}

struct MosqueTravelEstimate: Equatable {
    let walking: TimeInterval?
    let driving: TimeInterval?
}

enum MosqueFinderState: Equatable {
    case idle
    case permissionNeeded
    case locating
    case searching
    case ready
    case empty
    case denied
    case failed(String)
}

enum MosqueDisplayFormatter {
    static func distance(_ meters: CLLocationDistance) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = VaktLocalization.appLocale
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = meters < 1_000 ? 0 : 1
        return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }

    static func duration(_ interval: TimeInterval?) -> String? {
        guard let interval, interval.isFinite, interval > 0 else { return nil }
        let minutes = max(1, Int(ceil(interval / 60)))
        return L10n.formatString("mosques.duration.minutes", minutes)
    }
}
