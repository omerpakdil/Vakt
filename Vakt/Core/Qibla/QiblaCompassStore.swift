import CoreLocation
import Foundation

enum QiblaCompassStatus: Equatable {
    case idle
    case permissionNeeded
    case locating
    case calibrating
    case ready
    case denied
    case unavailable
    case failed(String)
}

struct QiblaCompassReading: Equatable {
    let coordinate: Coordinate
    let qiblaBearing: CLLocationDirection
    let deviceHeading: CLLocationDirection
    let angleToQibla: Double
    let headingAccuracy: CLLocationDirection
    let locationAccuracy: CLLocationAccuracy
    let distanceKilometers: Double
    let usesSavedLocation: Bool

    var absoluteAngle: Double {
        abs(angleToQibla)
    }

    var isAligned: Bool {
        absoluteAngle <= 5 && headingQuality != .poor
    }

    var headingQuality: QiblaHeadingQuality {
        guard headingAccuracy >= 0 else { return .unknown }

        switch headingAccuracy {
        case 0...18:
            return .good
        case 18...38:
            return .fair
        default:
            return .poor
        }
    }

    var turnInstruction: String {
        if isAligned {
            return L10n.text(.qiblaAhead)
        }

        if angleToQibla > 0 {
            return L10n.text(.qiblaTurnRight)
        }

        return L10n.text(.qiblaTurnLeft)
    }
}

enum QiblaHeadingQuality: Equatable {
    case good
    case fair
    case poor
    case unknown
}

@MainActor
final class QiblaCompassStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: QiblaCompassStatus = .idle
    @Published private(set) var reading: QiblaCompassReading?

#if DEBUG
    @Published private(set) var isUsingDebugHeading = false
    @Published private(set) var debugHeading: CLLocationDirection = 0
#endif

    private static let cachedLocationKey = "vakt.qibla.cachedLocation.v1"

    private let locationManager = CLLocationManager()
    private let calculator: QiblaDirectionCalculator
    private var coordinate: Coordinate?
    private var usesSavedLocation = false
    private var latestHeading: CLHeading?
    private var hasStarted = false

    init(calculator: QiblaDirectionCalculator = QiblaDirectionCalculator()) {
        self.calculator = calculator
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 250
        locationManager.headingFilter = 1
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        guard CLLocationManager.headingAvailable() else {
            status = .unavailable
            return
        }

        restoreCachedLocationIfAvailable()
        requestLocationIfAllowed()
        startHeadingUpdates()
        publishReadingIfPossible()
    }

    func stop() {
        hasStarted = false
#if DEBUG
        isUsingDebugHeading = false
#endif
        locationManager.stopUpdatingHeading()
        locationManager.stopUpdatingLocation()
    }

#if DEBUG
    func startDebugHeadingSimulation() {
        isUsingDebugHeading = true

        if coordinate == nil {
            restoreCachedLocationIfAvailable()
        }

        if coordinate == nil {
            coordinate = Self.debugFallbackCoordinate
            usesSavedLocation = false
        }

        publishReadingIfPossible(locationAccuracy: -1)
    }

    func setDebugHeading(_ heading: CLLocationDirection) {
        debugHeading = Self.normalizedHeading(heading)

        if isUsingDebugHeading {
            publishReadingIfPossible(locationAccuracy: -1)
        }
    }

    func stopDebugHeadingSimulation() {
        isUsingDebugHeading = false
        publishReadingIfPossible()
    }
#endif

    func requestLocationPermission() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = .denied
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            status = .locating
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestLiveLocation()
        case .denied, .restricted:
            status = coordinate == nil ? .denied : .calibrating
            publishReadingIfPossible()
        @unknown default:
            status = .failed("Location permission could not be read.")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.requestLocationIfAllowed()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let horizontalAccuracy = location.horizontalAccuracy

        Task { @MainActor [weak self] in
            self?.receive(coordinate: coordinate, horizontalAccuracy: horizontalAccuracy)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor [weak self] in
            self?.receive(heading: newHeading)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.coordinate != nil {
                self.status = .calibrating
                self.publishReadingIfPossible()
            } else {
                self.status = .failed(error.localizedDescription)
            }
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    private func requestLocationIfAllowed() {
        guard CLLocationManager.locationServicesEnabled() else {
            status = coordinate == nil ? .denied : .calibrating
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            status = coordinate == nil ? .permissionNeeded : .calibrating
        case .authorizedAlways, .authorizedWhenInUse:
            requestLiveLocation()
        case .denied, .restricted:
            status = coordinate == nil ? .denied : .calibrating
            publishReadingIfPossible()
        @unknown default:
            status = .failed("Location permission could not be read.")
        }
    }

    private func requestLiveLocation() {
        status = coordinate == nil ? .locating : .calibrating
        locationManager.requestLocation()
        locationManager.startUpdatingLocation()
    }

    private func startHeadingUpdates() {
        guard CLLocationManager.headingAvailable() else {
            status = .unavailable
            return
        }

        locationManager.startUpdatingHeading()
    }

    private func receive(coordinate: Coordinate, horizontalAccuracy: CLLocationAccuracy) {
        self.coordinate = coordinate
        usesSavedLocation = false
        cache(coordinate: coordinate, horizontalAccuracy: horizontalAccuracy)
        publishReadingIfPossible(locationAccuracy: horizontalAccuracy)
    }

    private func receive(heading: CLHeading) {
        latestHeading = heading
        publishReadingIfPossible()
    }

    private func publishReadingIfPossible(locationAccuracy: CLLocationAccuracy? = nil) {
        guard let coordinate else {
            if shouldShowLocatingWithoutCoordinate {
                status = .locating
            }
            return
        }

        let heading: CLLocationDirection
        let headingAccuracy: CLLocationDirection

#if DEBUG
        if isUsingDebugHeading {
            heading = debugHeading
            headingAccuracy = 5
        } else {
            guard let latestHeading else {
                status = .calibrating
                return
            }

            heading = latestHeading.trueHeading >= 0 ? latestHeading.trueHeading : latestHeading.magneticHeading
            headingAccuracy = latestHeading.headingAccuracy
        }
#else
        guard let latestHeading else {
            status = .calibrating
            return
        }

        heading = latestHeading.trueHeading >= 0 ? latestHeading.trueHeading : latestHeading.magneticHeading
        headingAccuracy = latestHeading.headingAccuracy
#endif

        guard heading >= 0 else {
            status = .calibrating
            return
        }

        let qiblaBearing = calculator.bearingTowardQibla(from: coordinate)
        let angleToQibla = calculator.signedAngleToQibla(
            qiblaBearing: qiblaBearing,
            deviceHeading: heading
        )

        reading = QiblaCompassReading(
            coordinate: coordinate,
            qiblaBearing: qiblaBearing,
            deviceHeading: heading,
            angleToQibla: angleToQibla,
            headingAccuracy: headingAccuracy,
            locationAccuracy: locationAccuracy ?? cachedLocationAccuracy ?? -1,
            distanceKilometers: calculator.distanceToQiblaKilometers(from: coordinate),
            usesSavedLocation: usesSavedLocation
        )
        status = .ready
    }

    private var shouldShowLocatingWithoutCoordinate: Bool {
        switch status {
        case .permissionNeeded, .denied, .failed:
            return false
        case .idle, .locating, .calibrating, .ready, .unavailable:
            return true
        }
    }

    private var cachedLocationAccuracy: CLLocationAccuracy? {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedLocationKey),
              let cached = try? JSONDecoder().decode(CachedQiblaLocation.self, from: data) else {
            return nil
        }
        return cached.horizontalAccuracy
    }

    private func restoreCachedLocationIfAvailable() {
        guard coordinate == nil,
              let data = UserDefaults.standard.data(forKey: Self.cachedLocationKey),
              let cached = try? JSONDecoder().decode(CachedQiblaLocation.self, from: data),
              Date().timeIntervalSince(cached.savedAt) < 60 * 60 * 24 * 30 else {
            return
        }

        coordinate = cached.coordinate
        usesSavedLocation = true
    }

    private func cache(coordinate: Coordinate, horizontalAccuracy: CLLocationAccuracy) {
        let cached = CachedQiblaLocation(
            coordinate: coordinate,
            horizontalAccuracy: horizontalAccuracy,
            savedAt: Date()
        )

        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: Self.cachedLocationKey)
        }
    }

#if DEBUG
    private static let debugFallbackCoordinate = Coordinate(latitude: 37.7749, longitude: -122.4194)

    private static func normalizedHeading(_ heading: CLLocationDirection) -> CLLocationDirection {
        let value = heading.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }
#endif
}

private struct CachedQiblaLocation: Codable {
    let coordinate: Coordinate
    let horizontalAccuracy: CLLocationAccuracy
    let savedAt: Date
}
