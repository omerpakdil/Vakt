import XCTest
@testable import Vakt

final class SupabaseBackendConfigurationTests: XCTestCase {
    func testLoadsCloudConfigurationFromEnvironment() throws {
        let configuration = try SupabaseBackendConfiguration.load(
            environment: [
                SupabaseBackendConfiguration.urlKey: "https://example.supabase.co",
                SupabaseBackendConfiguration.publishableKeyKey: "sb_publishable_12345678901234567890",
            ]
        )

        XCTAssertEqual(configuration.url.absoluteString, "https://example.supabase.co")
        XCTAssertEqual(configuration.publishableKey, "sb_publishable_12345678901234567890")
    }

    func testMissingConfigurationIsReportedWithoutCrashing() {
        XCTAssertThrowsError(
            try SupabaseBackendConfiguration.load(
                environment: [
                    SupabaseBackendConfiguration.urlKey: " ",
                    SupabaseBackendConfiguration.publishableKeyKey: " ",
                ]
            )
        ) { error in
            XCTAssertEqual(error as? BackendError, .notConfigured)
        }
    }

    func testRejectsSecretKey() {
        XCTAssertThrowsError(
            try SupabaseBackendConfiguration.load(
                environment: [
                    SupabaseBackendConfiguration.urlKey: "https://example.supabase.co",
                    SupabaseBackendConfiguration.publishableKeyKey: "sb_secret_12345678901234567890",
                ]
            )
        ) { error in
            guard case .invalidConfiguration = error as? BackendError else {
                return XCTFail("Expected invalid configuration")
            }
        }
    }

    func testRejectsLegacyCloudKeyBecauseItsRoleCannotBeVerified() {
        XCTAssertThrowsError(
            try SupabaseBackendConfiguration.load(
                environment: [
                    SupabaseBackendConfiguration.urlKey: "https://example.supabase.co",
                    SupabaseBackendConfiguration.publishableKeyKey: "eyJhbGciOiJIUzI1NiJ9.legacy-key",
                ]
            )
        ) { error in
            guard case .invalidConfiguration = error as? BackendError else {
                return XCTFail("Expected invalid configuration")
            }
        }
    }

    func testRejectsInsecureRemoteURL() {
        XCTAssertThrowsError(
            try SupabaseBackendConfiguration.load(
                environment: [
                    SupabaseBackendConfiguration.urlKey: "http://example.supabase.co",
                    SupabaseBackendConfiguration.publishableKeyKey: "sb_publishable_12345678901234567890",
                ]
            )
        ) { error in
            guard case .invalidConfiguration = error as? BackendError else {
                return XCTFail("Expected invalid configuration")
            }
        }
    }

    func testAllowsHTTPForLocalSupabase() throws {
        let configuration = try SupabaseBackendConfiguration.load(
            environment: [
                SupabaseBackendConfiguration.urlKey: "http://127.0.0.1:54321",
                SupabaseBackendConfiguration.publishableKeyKey: "local_publishable_key_1234567890",
            ]
        )

        XCTAssertEqual(configuration.url.port, 54321)
    }
}
