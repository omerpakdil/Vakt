import CoreLocation
import Foundation

struct QiblaDirectionCalculator {
    static let kaabaCoordinate = Coordinate(latitude: 21.422487, longitude: 39.826206)

    func bearingTowardQibla(from coordinate: Coordinate) -> CLLocationDirection {
        bearing(from: coordinate, to: Self.kaabaCoordinate)
    }

    func signedAngleToQibla(
        qiblaBearing: CLLocationDirection,
        deviceHeading: CLLocationDirection
    ) -> Double {
        Self.signedAngle(from: deviceHeading, to: qiblaBearing)
    }

    func distanceToQiblaKilometers(from coordinate: Coordinate) -> Double {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let kaaba = CLLocation(
            latitude: Self.kaabaCoordinate.latitude,
            longitude: Self.kaabaCoordinate.longitude
        )
        return origin.distance(from: kaaba) / 1_000
    }

    private func bearing(from origin: Coordinate, to destination: Coordinate) -> CLLocationDirection {
        let originLatitude = origin.latitude.degreesToRadians
        let destinationLatitude = destination.latitude.degreesToRadians
        let longitudeDelta = (destination.longitude - origin.longitude).degreesToRadians

        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let x = cos(originLatitude) * sin(destinationLatitude)
            - sin(originLatitude) * cos(destinationLatitude) * cos(longitudeDelta)

        return atan2(y, x).radiansToDegrees.normalizedDegrees
    }

    static func signedAngle(from heading: CLLocationDirection, to bearing: CLLocationDirection) -> Double {
        let difference = (bearing - heading + 540).truncatingRemainder(dividingBy: 360) - 180
        return difference == -180 ? 180 : difference
    }
}

private extension Double {
    var degreesToRadians: Double {
        self * .pi / 180
    }

    var radiansToDegrees: Double {
        self * 180 / .pi
    }

    var normalizedDegrees: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }
}
