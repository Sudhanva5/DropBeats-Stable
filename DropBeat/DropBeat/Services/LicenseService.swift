import Foundation
import IOKit

/// HTTP client for the licensing endpoints.
///
/// Previously spoke to Supabase through the supabase-swift SDK. Now calls the
/// Railway backend through the Cloudflare Worker, because Jio blocks Railway
/// outright — see BackendConfig for why every call goes via the proxy.
///
/// The three public methods keep their old signatures and return types, so
/// callers did not change when the transport did.
final class LicenseService {
    static let shared = LicenseService()

    private let session: URLSession
    private let decoder: JSONDecoder

    private init() {
        let configuration = URLSessionConfiguration.default
        // Licence checks must never be the reason the app appears to hang.
        // A refusal to answer is handled as a transport error by the caller,
        // which keeps a cached licence valid rather than locking the user out.
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false

        // Identify the app explicitly. Requests now pass through Cloudflare,
        // whose bot management judges by User-Agent — a generic or unfamiliar
        // one gets a 403 before it ever reaches Railway (verified: the same
        // request 403s as "Python-urllib/3.11" and 200s as a CFNetwork UA).
        // Relying on URLSession's default would leave licensing at the mercy
        // of a heuristic nobody here controls.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        configuration.httpAdditionalHeaders = [
            "User-Agent": "DropBeat/\(version) (macOS; +https://github.com/Sudhanva5/DropBeats-Stable)"
        ]

        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        // The backend emits isoformat(timespec: "seconds"), e.g.
        // "2026-08-21T10:31:11+00:00" — no fractional part, deliberately,
        // because the formatter below cannot parse one.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = formatter.date(from: raw) { return date }
            // Tolerated rather than expected: if the server ever regains a
            // fractional component, a licence should not stop decoding.
            if let date = withFractional.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(raw)"
            )
        }
        self.decoder = decoder
    }

    // MARK: - Public API

    func validateLicense(key: String) async throws -> LicenseValidationResponse {
        try await post(
            path: "/license/validate",
            body: ["key": AnyEncodable(key)],
            as: LicenseValidationResponse.self
        )
    }

    func deactivateLicense(key: String, email: String) async throws -> LicenseDeactivationResponse {
        try await post(
            path: "/license/deactivate",
            body: ["key": AnyEncodable(key), "email": AnyEncodable(email)],
            as: LicenseDeactivationResponse.self
        )
    }

    func updateOnboardingStatus(key: String, completed: Bool) async throws {
        _ = try await post(
            path: "/license/onboarding",
            body: ["key": AnyEncodable(key), "completed": AnyEncodable(completed)],
            as: LicenseDeactivationResponse.self
        )
    }

    func getDeviceIdentifier() async throws -> String {
        // Retained for callers that still ask. The backend no longer stores or
        // checks a device id — seat-binding was removed deliberately.
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert > 0 else { throw LicenseError.deviceIdGenerationFailed }
        defer { IOObjectRelease(platformExpert) }

        guard let serial = IORegistryEntryCreateCFProperty(
            platformExpert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0
        )?.takeUnretainedValue() as? String else {
            throw LicenseError.deviceIdGenerationFailed
        }
        return serial
    }

    // MARK: - Transport

    private func post<T: Decodable>(
        path: String,
        body: [String: AnyEncodable],
        as type: T.Type
    ) async throws -> T {
        guard let url = URL(string: BackendConfig.licenseURL(path: path)) else {
            throw LicenseError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.networkError
        }

        // 429 (rate limited) and 503 (licensing database unavailable) are
        // TRANSPORT failures, not licence verdicts. They arrive as
        // {"detail": "..."} and would not decode as a validation response
        // anyway — but the distinction matters more than the decoding does:
        // treating either as "invalid licence" would turn a transient blip
        // into a lockout for a paying customer. Throwing here lets
        // AppStateManager fall back to its cached, still-valid licence.
        guard (200...299).contains(http.statusCode) else {
            throw LicenseError.serviceUnavailable(status: http.statusCode)
        }

        return try decoder.decode(T.self, from: data)
    }
}

/// Minimal type-erasing wrapper so a request body can mix String and Bool
/// without a bespoke Encodable struct per endpoint.
struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeTo = { encoder in
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeTo(encoder)
    }
}

enum LicenseError: LocalizedError {
    case deviceIdGenerationFailed
    case invalidLicenseKey
    case networkError
    /// The server answered, but with a status that is not a verdict on the
    /// licence — rate limiting or a database outage.
    case serviceUnavailable(status: Int)

    var errorDescription: String? {
        switch self {
        case .deviceIdGenerationFailed:
            return "Failed to generate device identifier"
        case .invalidLicenseKey:
            return "Invalid license key"
        case .networkError:
            return "Network error occurred"
        case .serviceUnavailable(let status):
            return "Licence service temporarily unavailable (HTTP \(status))"
        }
    }
}
