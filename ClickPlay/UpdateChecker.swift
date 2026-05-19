import Foundation

struct UpdateCheckResult {
    let currentVersion: String
    let latestVersion: String
    let releaseURL: URL
    let releaseName: String?

    var isUpdateAvailable: Bool {
        guard let current = AppVersion(currentVersion),
              let latest = AppVersion(latestVersion) else {
            return false
        }

        return current < latest
    }
}

enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case requestFailed(Int)
    case missingReleaseURL
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Click Play could not read the latest release information."
        case let .requestFailed(statusCode):
            return "GitHub returned an unexpected response (\(statusCode))."
        case .missingReleaseURL:
            return "The latest release did not include a page to open."
        case let .invalidVersion(version):
            return "Click Play could not understand the release version \"\(version)\"."
        }
    }
}

final class UpdateChecker {
    static let shared = UpdateChecker()

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/TheOPBunny/ClickPlay/releases/latest")!
    private let defaults: UserDefaults
    private let session: URLSession
    private let bundle: Bundle
    private let lastAutomaticCheckKey = "lastUpdateCheckDate"
    private let skippedUpdateVersionKey = "skippedUpdateVersion"
    private let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        bundle: Bundle = .main
    ) {
        self.defaults = defaults
        self.session = session
        self.bundle = bundle
    }

    func checkForUpdatesIfNeeded(now: Date = Date()) async throws -> UpdateCheckResult? {
        guard shouldRunAutomaticCheck(now: now) else {
            return nil
        }

        defaults.set(now, forKey: lastAutomaticCheckKey)
        let result = try await checkForUpdates()
        guard !isSkippedUpdate(result) else {
            return nil
        }

        return result
    }

    func skipVersion(_ version: String) {
        defaults.set(version, forKey: skippedUpdateVersionKey)
    }

    func checkForUpdates() async throws -> UpdateCheckResult {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClickPlay", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.requestFailed(httpResponse.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let releaseURL = URL(string: release.htmlURL) else {
            throw UpdateCheckError.missingReleaseURL
        }

        let currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let latestVersion = Self.normalizedVersion(from: release.tagName)

        guard AppVersion(latestVersion) != nil else {
            throw UpdateCheckError.invalidVersion(release.tagName)
        }

        return UpdateCheckResult(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseURL: releaseURL,
            releaseName: release.name
        )
    }

    private func shouldRunAutomaticCheck(now: Date) -> Bool {
        guard let lastCheck = defaults.object(forKey: lastAutomaticCheckKey) as? Date else {
            return true
        }

        return now.timeIntervalSince(lastCheck) >= automaticCheckInterval
    }

    private func isSkippedUpdate(_ result: UpdateCheckResult) -> Bool {
        guard result.isUpdateAvailable else {
            return false
        }

        return defaults.string(forKey: skippedUpdateVersionKey) == result.latestVersion
    }

    private static func normalizedVersion(from tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let dot = Unicode.Scalar(".")
        let versionScalars = withoutPrefix.unicodeScalars.prefix {
            CharacterSet.decimalDigits.contains($0) || $0 == dot
        }

        return String(String.UnicodeScalarView(versionScalars))
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
    }
}

private struct AppVersion: Comparable {
    let components: [Int]

    init?(_ version: String) {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let dot = Unicode.Scalar(".")
        let versionScalars = withoutPrefix.unicodeScalars.prefix {
            CharacterSet.decimalDigits.contains($0) || $0 == dot
        }
        let versionText = String(String.UnicodeScalarView(versionScalars))
        let components = versionText
            .split(separator: ".")
            .compactMap { Int($0) }

        guard !components.isEmpty else {
            return nil
        }

        self.components = components
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)

        for index in 0..<maxCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }
}
