import CoreLocation
import Foundation
import MapKit

@MainActor
final class MosqueFinderStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var state: MosqueFinderState = .idle
    @Published private(set) var places: [MosquePlace] = []
    @Published private(set) var userCoordinate: CLLocationCoordinate2D?
    @Published private(set) var travelEstimates: [String: MosqueTravelEstimate] = [:]
    @Published var selectedPlaceID: String?

    private let locationManager = CLLocationManager()
    private var mapItems: [String: MKMapItem] = [:]
    private var searchTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var bestLocation: CLLocation?
    private var lastSearchLocation: CLLocation?
    private var lastSearchDate: Date?
    private var hasStarted = false
    #if DEBUG
    private var isStoreScreenshotPreview = false
    #endif

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.pausesLocationUpdatesAutomatically = false
        if let cachedCoordinate = Self.restoreCachedCoordinate() {
            userCoordinate = cachedCoordinate
        }
    }

    deinit {
        searchTask?.cancel()
        routeTask?.cancel()
        locationTimeoutTask?.cancel()
    }

    func start() {
        #if DEBUG
        if isStoreScreenshotPreview {
            state = .ready
            return
        }
        #endif
        hasStarted = true
        guard CLLocationManager.locationServicesEnabled() else {
            state = .denied
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            state = .permissionNeeded
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation()
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .failed(L10n.string("mosques.error.location"))
        }
    }

    func stop() {
        hasStarted = false
        locationManager.stopUpdatingLocation()
        locationTimeoutTask?.cancel()
    }

    func requestPermission() {
        hasStarted = true
        switch locationManager.authorizationStatus {
        case .notDetermined:
            state = .locating
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocation(forceSearch: true)
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .failed(L10n.string("mosques.error.location"))
        }
    }

    func refresh() {
        #if DEBUG
        if isStoreScreenshotPreview { return }
        #endif
        requestLocation(forceSearch: true)
    }

    #if DEBUG
    func configureStoreScreenshotPreview() {
        isStoreScreenshotPreview = true
        let origin = CLLocationCoordinate2D(latitude: 39.9244, longitude: 32.8702)
        userCoordinate = origin
        places = [
            MosquePlace(
                id: "maltepe",
                name: "Maltepe Camii",
                coordinate: CLLocationCoordinate2D(latitude: 39.9258, longitude: 32.8727),
                address: "Çankaya",
                distanceMeters: 310
            ),
            MosquePlace(
                id: "camlik",
                name: "Çamlıtepe Camii",
                coordinate: CLLocationCoordinate2D(latitude: 39.9222, longitude: 32.8683),
                address: "Çamlıtepe, Çankaya",
                distanceMeters: 420
            ),
            MosquePlace(
                id: "kocatepe",
                name: "Kocatepe Camii",
                coordinate: CLLocationCoordinate2D(latitude: 39.9164, longitude: 32.8606),
                address: "Kızılay, Çankaya",
                distanceMeters: 1_280
            )
        ]
        travelEstimates = [
            "maltepe": MosqueTravelEstimate(walking: 4 * 60, driving: 2 * 60),
            "camlik": MosqueTravelEstimate(walking: 6 * 60, driving: 3 * 60),
            "kocatepe": MosqueTravelEstimate(walking: 17 * 60, driving: 7 * 60)
        ]
        selectedPlaceID = places.first?.id
        state = .ready
    }
    #endif

    func select(_ place: MosquePlace) {
        selectedPlaceID = place.id
        loadTravelEstimate(for: place)
    }

    func openDirections(to place: MosquePlace) {
        guard let item = mapItems[place.id] else { return }
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.hasStarted else { return }
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.receive(location: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.places.isEmpty {
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    private func requestLocation(forceSearch: Bool = false) {
        guard locationManager.authorizationStatus == .authorizedAlways ||
                locationManager.authorizationStatus == .authorizedWhenInUse else {
            start()
            return
        }

        if !forceSearch,
           !places.isEmpty,
           let lastSearchDate,
           Date().timeIntervalSince(lastSearchDate) < 15 * 60 {
            state = .ready
            return
        }

        state = .locating
        bestLocation = nil
        locationTimeoutTask?.cancel()
        locationManager.requestLocation()
        locationManager.startUpdatingLocation()
        locationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.finishLocationRefinement()
        }
    }

    private func receive(location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else { return }

        if let bestLocation,
           bestLocation.horizontalAccuracy <= location.horizontalAccuracy {
            return
        }

        bestLocation = location
        userCoordinate = location.coordinate

        if location.horizontalAccuracy <= 65 {
            finishLocationRefinement()
        }
    }

    private func finishLocationRefinement() {
        guard let location = bestLocation else { return }
        locationTimeoutTask?.cancel()
        locationTimeoutTask = nil
        locationManager.stopUpdatingLocation()

        if let lastSearchLocation,
           !places.isEmpty,
           location.distance(from: lastSearchLocation) < 350,
           let lastSearchDate,
           Date().timeIntervalSince(lastSearchDate) < 15 * 60 {
            state = .ready
            return
        }

        search(around: location)
    }

    private func search(around location: CLLocation) {
        searchTask?.cancel()
        routeTask?.cancel()
        state = .searching
        travelEstimates = [:]

        searchTask = Task { [weak self] in
            guard let self else { return }

            do {
                let results = try await Self.searchNearbyMosques(around: location)
                guard !Task.isCancelled else { return }

                self.mapItems = Dictionary(uniqueKeysWithValues: results.map { ($0.place.id, $0.mapItem) })
                self.places = results.map(\.place)
                self.lastSearchLocation = location
                self.lastSearchDate = Date()

                guard let first = self.places.first else {
                    self.selectedPlaceID = nil
                    self.state = .empty
                    return
                }

                self.state = .ready
                self.select(self.places.first(where: { $0.id == self.selectedPlaceID }) ?? first)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.state = self.places.isEmpty ? .failed(error.localizedDescription) : .ready
            }
        }
    }

    private func loadTravelEstimate(for place: MosquePlace) {
        guard travelEstimates[place.id] == nil,
              let sourceCoordinate = userCoordinate,
              let destination = mapItems[place.id] else { return }

        routeTask?.cancel()
        routeTask = Task { [weak self] in
            guard let self else { return }
            async let walking = Self.expectedTravelTime(
                from: sourceCoordinate,
                to: destination,
                transportType: .walking
            )
            async let driving = Self.expectedTravelTime(
                from: sourceCoordinate,
                to: destination,
                transportType: .automobile
            )
            let estimate = await MosqueTravelEstimate(walking: walking, driving: driving)
            guard !Task.isCancelled else { return }
            self.travelEstimates[place.id] = estimate
        }
    }

    private static func expectedTravelTime(
        from source: CLLocationCoordinate2D,
        to destination: MKMapItem,
        transportType: MKDirectionsTransportType
    ) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = destination
        request.transportType = transportType
        request.requestsAlternateRoutes = false

        do {
            return try await MKDirections(request: request).calculate().routes.first?.expectedTravelTime
        } catch {
            return nil
        }
    }

    private struct SearchResult {
        let place: MosquePlace
        let mapItem: MKMapItem
    }

    private static func searchNearbyMosques(around location: CLLocation) async throws -> [SearchResult] {
        let radii: [CLLocationDistance] = [3_000, 8_000, 20_000]
        let countryCode = await resolvedCountryCode(for: location)
        let queries = searchQueries(for: countryCode)
        let discoveryQueries = nearbyDiscoveryQueries(for: countryCode)
        var collected: [MKMapItem] = []

        for radius in radii {
            try Task.checkCancellation()
            for query in queries {
                collected.append(contentsOf: await searchMapItems(
                    query: query,
                    center: location.coordinate,
                    radius: radius
                ))
            }

            // Local Search ranks prominent places and can omit a small mosque even
            // when it is very close. Smaller overlapping regions improve local coverage.
            if radius == radii[0] {
                for center in nearbySearchCenters(around: location.coordinate) {
                    for query in discoveryQueries {
                        collected.append(contentsOf: await searchMapItems(
                            query: query,
                            center: center,
                            radius: 1_100
                        ))
                    }
                }
            }

            let unique = deduplicated(collected, origin: location, maximumDistance: radius)
            if unique.count >= 6 || radius == radii.last {
                return unique.prefix(24).map { item in
                    let coordinate = item.placemark.coordinate
                    let distance = location.distance(from: CLLocation(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ))
                    let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedName = (name?.isEmpty == false) ? name! : L10n.string("mosques.unnamed")
                    return SearchResult(
                        place: MosquePlace(
                            id: stableID(name: resolvedName, coordinate: coordinate),
                            name: resolvedName,
                            coordinate: coordinate,
                            address: compactAddress(for: item),
                            distanceMeters: distance
                        ),
                        mapItem: item
                    )
                }
            }
        }

        return []
    }

    private static func resolvedCountryCode(for location: CLLocation) async -> String? {
        if let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
           let countryCode = placemarks.first?.isoCountryCode {
            return countryCode.uppercased()
        }
        return Locale.current.region?.identifier.uppercased()
    }

    private static func searchMapItems(
        query: String,
        center: CLLocationCoordinate2D,
        radius: CLLocationDistance
    ) async -> [MKMapItem] {
        guard !Task.isCancelled else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        guard let response = try? await MKLocalSearch(request: request).start() else {
            return []
        }
        return response.mapItems
    }

    private static func nearbySearchCenters(
        around coordinate: CLLocationCoordinate2D
    ) -> [CLLocationCoordinate2D] {
        let offsetMeters = 750.0
        let latitudeOffset = offsetMeters / 111_000
        let longitudeScale = max(0.2, cos(coordinate.latitude * .pi / 180))
        let longitudeOffset = offsetMeters / (111_000 * longitudeScale)

        return [
            CLLocationCoordinate2D(
                latitude: coordinate.latitude + latitudeOffset,
                longitude: coordinate.longitude
            ),
            CLLocationCoordinate2D(
                latitude: coordinate.latitude - latitudeOffset,
                longitude: coordinate.longitude
            ),
            CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude + longitudeOffset
            ),
            CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude - longitudeOffset
            )
        ]
    }

    private static func searchQueries(for countryCode: String?) -> [String] {
        orderedUnique(
            geographicSearchQueries(for: countryCode) +
                localizedSearchQueries +
                ["mosque", "masjid"]
        )
    }

    private static func nearbyDiscoveryQueries(for countryCode: String?) -> [String] {
        let localQueries = geographicSearchQueries(for: countryCode)
        return orderedUnique(Array((localQueries + localizedSearchQueries).prefix(1)))
    }

    private static func geographicSearchQueries(for countryCode: String?) -> [String] {
        switch countryCode {
        case "TR": ["cami", "camii", "mescit"]
        case "DE", "AT", "CH": ["Moschee"]
        case "ES", "MX", "AR", "CL", "CO", "PE": ["mezquita"]
        case "FR", "BE": ["mosquée"]
        case "ID", "MY": ["masjid", "musala"]
        case "IT": ["moschea"]
        case "NL": ["moskee"]
        case "PT", "BR": ["mesquita"]
        case "RU": ["мечеть"]
        case "PK": ["مسجد", "مصلی"]
        case "SA", "AE", "QA", "KW", "BH", "OM", "EG", "JO", "IQ", "LB": ["مسجد", "مصلى"]
        default: []
        }
    }

    private static var localizedSearchQueries: [String] {
        switch VaktLocalization.languageCode {
        case "tr": ["cami", "camii", "mescit"]
        case "ar": ["مسجد", "مصلى"]
        case "de": ["Moschee", "muslimischer Gebetsraum"]
        case "es": ["mezquita", "sala de oración musulmana"]
        case "fr": ["mosquée", "salle de prière musulmane"]
        case "id": ["masjid", "musala"]
        case "it": ["moschea", "sala di preghiera musulmana"]
        case "nl": ["moskee", "islamitische gebedsruimte"]
        case "pt": ["mesquita", "sala de oração muçulmana"]
        case "ru": ["мечеть", "мусульманская молельная комната"]
        case "ur": ["مسجد", "مصلی"]
        default: ["mosque", "masjid", "Muslim prayer room"]
        }
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }

    private static func deduplicated(
        _ items: [MKMapItem],
        origin: CLLocation,
        maximumDistance: CLLocationDistance
    ) -> [MKMapItem] {
        let sorted = items
            .filter { item in
                guard isLikelyMosque(item) else { return false }
                let coordinate = item.placemark.coordinate
                return origin.distance(from: CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )) <= maximumDistance * 1.2
            }
            .sorted { lhs, rhs in
                distance(of: lhs, from: origin) < distance(of: rhs, from: origin)
            }

        var unique: [MKMapItem] = []
        for candidate in sorted {
            let coordinate = candidate.placemark.coordinate
            let name = normalized(candidate.name ?? "")
            let duplicate = unique.contains { existing in
                let existingCoordinate = existing.placemark.coordinate
                let separation = CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ).distance(from: CLLocation(
                    latitude: existingCoordinate.latitude,
                    longitude: existingCoordinate.longitude
                ))
                let existingName = normalized(existing.name ?? "")
                return separation < 70 && (name == existingName || name.contains(existingName) || existingName.contains(name))
            }
            if !duplicate { unique.append(candidate) }
        }
        return unique
    }

    private static func isLikelyMosque(_ item: MKMapItem) -> Bool {
        let name = normalized(item.name ?? "")
        guard !name.isEmpty else { return false }

        let explicitMosqueMarkers = [
            "mosque", "masjid", "masjed", "mesjid", "musalla", "musallah",
            "musholla", "surau", "cami", "camii", "mescit", "mescid",
            "moschee", "mosquee", "moschea", "moskee", "mezquita", "mesquita",
            "мечеть", "مسجد", "جامع", "مصلى", "meczet", "dzamija", "џамија"
        ]
        if explicitMosqueMarkers.contains(where: name.contains) {
            return true
        }

        let islamicCommunityMarkers = [
            "islamic", "islam", "muslim", "diyanet", "icna", "isna",
            "prayerroom", "prayerspace", "salahroom", "salaahroom", "namazgah"
        ]
        guard islamicCommunityMarkers.contains(where: name.contains) else { return false }

        let rejectedCategories: [MKPointOfInterestCategory] = [
            .store, .restaurant, .cafe, .hotel, .foodMarket
        ]
        guard let category = item.pointOfInterestCategory else { return true }
        return !rejectedCategories.contains(category)
    }

    private static func distance(of item: MKMapItem, from origin: CLLocation) -> CLLocationDistance {
        let coordinate = item.placemark.coordinate
        return origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
    }

    private static func stableID(name: String, coordinate: CLLocationCoordinate2D) -> String {
        "\(normalized(name))|\(String(format: "%.5f", coordinate.latitude))|\(String(format: "%.5f", coordinate.longitude))"
    }

    private static func compactAddress(for item: MKMapItem) -> String? {
        let parts = [
            item.placemark.subLocality,
            item.placemark.locality,
            item.placemark.administrativeArea
        ]
        return parts.compactMap { $0 }.reduce(into: [String]()) { result, part in
            if !result.contains(part) { result.append(part) }
        }.prefix(2).joined(separator: ", ")
    }

    private static func restoreCachedCoordinate() -> CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        let decoder = JSONDecoder()

        if let data = defaults.data(forKey: "vakt.qibla.cachedLocation.v1"),
           let cached = try? decoder.decode(CachedCoordinateEnvelope.self, from: data),
           let coordinate = cached.coordinate {
            return CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }

        if let data = defaults.data(forKey: "vakt.cachedPrayerSchedule.v1"),
           let cached = try? decoder.decode(CachedCoordinateEnvelope.self, from: data),
           let coordinate = cached.coordinate {
            return CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }

        return nil
    }

    private struct CachedCoordinateEnvelope: Decodable {
        let coordinate: Coordinate?
    }
}
