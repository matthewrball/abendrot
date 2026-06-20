import Foundation

/// A curated list of major cities (name + representative coordinate) for the no-permission manual
/// location override. Deliberately includes cities that differ meaningfully from their time zone's
/// representative coordinate (e.g. San Francisco/Seattle within America/Los_Angeles).
public enum MajorCities {
    public struct City: Hashable, Sendable, Identifiable {
        public let name: String
        public let coordinate: TimeZoneCoordinates.Coordinate
        public var id: String { name }

        public init(name: String, coordinate: TimeZoneCoordinates.Coordinate) {
            self.name = name
            self.coordinate = coordinate
        }
    }

    /// ~40 major cities across regions, alphabetical by name.
    public static let all: [City] = [
        City(name: "Amsterdam", coordinate: .init(latitude: 52.37, longitude: 4.90)),
        City(name: "Athens", coordinate: .init(latitude: 37.98, longitude: 23.73)),
        City(name: "Auckland", coordinate: .init(latitude: -36.85, longitude: 174.76)),
        City(name: "Bangkok", coordinate: .init(latitude: 13.76, longitude: 100.50)),
        City(name: "Beijing", coordinate: .init(latitude: 39.90, longitude: 116.41)),
        City(name: "Berlin", coordinate: .init(latitude: 52.52, longitude: 13.40)),
        City(name: "Boston", coordinate: .init(latitude: 42.36, longitude: -71.06)),
        City(name: "Buenos Aires", coordinate: .init(latitude: -34.61, longitude: -58.38)),
        City(name: "Cairo", coordinate: .init(latitude: 30.04, longitude: 31.24)),
        City(name: "Chicago", coordinate: .init(latitude: 41.85, longitude: -87.65)),
        City(name: "Delhi", coordinate: .init(latitude: 28.61, longitude: 77.21)),
        City(name: "Denver", coordinate: .init(latitude: 39.74, longitude: -104.98)),
        City(name: "Dublin", coordinate: .init(latitude: 53.35, longitude: -6.26)),
        City(name: "Dubai", coordinate: .init(latitude: 25.20, longitude: 55.27)),
        City(name: "Hong Kong", coordinate: .init(latitude: 22.32, longitude: 114.17)),
        City(name: "Houston", coordinate: .init(latitude: 29.76, longitude: -95.37)),
        City(name: "Istanbul", coordinate: .init(latitude: 41.01, longitude: 28.98)),
        City(name: "Johannesburg", coordinate: .init(latitude: -26.20, longitude: 28.04)),
        City(name: "Lagos", coordinate: .init(latitude: 6.52, longitude: 3.38)),
        City(name: "London", coordinate: .init(latitude: 51.51, longitude: -0.13)),
        City(name: "Los Angeles", coordinate: .init(latitude: 34.05, longitude: -118.24)),
        City(name: "Madrid", coordinate: .init(latitude: 40.42, longitude: -3.70)),
        City(name: "Melbourne", coordinate: .init(latitude: -37.81, longitude: 144.96)),
        City(name: "Mexico City", coordinate: .init(latitude: 19.43, longitude: -99.13)),
        City(name: "Miami", coordinate: .init(latitude: 25.76, longitude: -80.19)),
        City(name: "Moscow", coordinate: .init(latitude: 55.76, longitude: 37.62)),
        City(name: "Mumbai", coordinate: .init(latitude: 19.08, longitude: 72.88)),
        City(name: "New York", coordinate: .init(latitude: 40.71, longitude: -74.01)),
        City(name: "Paris", coordinate: .init(latitude: 48.86, longitude: 2.35)),
        City(name: "Phoenix", coordinate: .init(latitude: 33.45, longitude: -112.07)),
        City(name: "Rome", coordinate: .init(latitude: 41.90, longitude: 12.50)),
        City(name: "San Diego", coordinate: .init(latitude: 32.72, longitude: -117.16)),
        City(name: "San Francisco", coordinate: .init(latitude: 37.77, longitude: -122.42)),
        City(name: "São Paulo", coordinate: .init(latitude: -23.55, longitude: -46.63)),
        City(name: "Seattle", coordinate: .init(latitude: 47.61, longitude: -122.33)),
        City(name: "Seoul", coordinate: .init(latitude: 37.57, longitude: 126.98)),
        City(name: "Shanghai", coordinate: .init(latitude: 31.23, longitude: 121.47)),
        City(name: "Singapore", coordinate: .init(latitude: 1.35, longitude: 103.82)),
        City(name: "Stockholm", coordinate: .init(latitude: 59.33, longitude: 18.07)),
        City(name: "Sydney", coordinate: .init(latitude: -33.87, longitude: 151.21)),
        City(name: "Tokyo", coordinate: .init(latitude: 35.68, longitude: 139.69)),
        City(name: "Toronto", coordinate: .init(latitude: 43.65, longitude: -79.38)),
        City(name: "Vancouver", coordinate: .init(latitude: 49.28, longitude: -123.12)),
    ]
}
