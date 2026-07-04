import Foundation

struct SupabaseBackendConfiguration: Equatable, Sendable {
    static let urlKey = "SUPABASE_URL"
    static let publishableKeyKey = "SUPABASE_PUBLISHABLE_KEY"

    let url: URL
    let publishableKey: String

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> SupabaseBackendConfiguration {
        let urlValue = resolvedValue(for: urlKey, bundle: bundle, environment: environment)
        let keyValue = resolvedValue(for: publishableKeyKey, bundle: bundle, environment: environment)

        guard let urlValue, let keyValue else {
            throw BackendError.notConfigured
        }
        guard
            let url = URL(string: urlValue),
            let scheme = url.scheme?.lowercased(),
            let host = url.host,
            !host.isEmpty,
            scheme == "https" || (scheme == "http" && Self.isLocalHost(host))
        else {
            throw BackendError.invalidConfiguration(message: "Supabase URL is invalid.")
        }
        guard !keyValue.lowercased().hasPrefix("sb_secret_") else {
            throw BackendError.invalidConfiguration(
                message: "A Supabase secret key must never be bundled in the app."
            )
        }
        guard keyValue.count >= 20 else {
            throw BackendError.invalidConfiguration(message: "Supabase publishable key is invalid.")
        }
        guard Self.isLocalHost(host) || keyValue.hasPrefix("sb_publishable_") else {
            throw BackendError.invalidConfiguration(
                message: "Use a Supabase publishable key for the iOS app."
            )
        }

        return SupabaseBackendConfiguration(url: url, publishableKey: keyValue)
    }

    private static func resolvedValue(
        for key: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> String? {
        let candidate = environment[key] ?? bundle.object(forInfoDictionaryKey: key) as? String
        guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        guard
            !value.isEmpty,
            !value.contains("$("),
            value != "YOUR_\(key)"
        else {
            return nil
        }
        return value
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
