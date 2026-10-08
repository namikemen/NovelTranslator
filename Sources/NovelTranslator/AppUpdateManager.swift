import Foundation
import AppKit

public struct GitHubReleaseAsset: Codable, Sendable, Identifiable {
    public var id: String { browserDownloadURL }
    public let name: String
    public let browserDownloadURL: String
    public let size: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

public struct GitHubRelease: Codable, Sendable, Identifiable {
    public var id: String { tagName }
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: String
    public let publishedAt: String?
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }

    public var displayTitle: String {
        if let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return tagName
    }

    public var cleanVersionString: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\r\n"))
    }
}

@MainActor
public class AppUpdateManager: ObservableObject {
    public static let shared = AppUpdateManager()

    public static let repoOwner = "namikemen"
    public static let repoName = "NovelTranslator"
    public static let releasesAPIURL = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"

    @Published public var isChecking: Bool = false
    @Published public var updateAvailable: GitHubRelease? = nil
    @Published public var showUpdateSheet: Bool = false
    @Published public var isUpToDateAlertShown: Bool = false
    @Published public var checkError: String? = nil
    @Published public var lastCheckDate: Date? = nil

    public var currentAppVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.isEmpty {
            return version
        }
        return "1.0.0"
    }

    public init() {}

    /// Checks for updates against GitHub Releases.
    /// If `silent` is true, dialogs are suppressed when already on the latest version or if network fails.
    public func checkForUpdates(silent: Bool = false) async {
        if isChecking { return }
        isChecking = true
        checkError = nil

        defer {
            isChecking = false
            lastCheckDate = Date()
        }

        do {
            let release = try await fetchLatestRelease()
            let latestVersion = release.cleanVersionString

            if Self.isVersion(latestVersion, greaterThan: currentAppVersion) {
                self.updateAvailable = release
                self.showUpdateSheet = true
            } else {
                self.updateAvailable = nil
                if !silent {
                    self.isUpToDateAlertShown = true
                }
            }
        } catch {
            if !silent {
                self.checkError = error.localizedDescription
            }
        }
    }

    public func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: Self.releasesAPIURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("NovelTranslator/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw NSError(domain: "AppUpdateManager", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "No public releases found yet on GitHub repository \(Self.repoOwner)/\(Self.repoName)."
                ])
            }
            throw NSError(domain: "AppUpdateManager", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "GitHub Releases API returned status code \(httpResponse.statusCode)."
            ])
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// Opens the direct download URL if a .zip release asset exists, otherwise opens the GitHub Release page in default browser.
    public func downloadAndOpen(release: GitHubRelease) {
        if let zipAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
           let zipURL = URL(string: zipAsset.browserDownloadURL) {
            NSWorkspace.shared.open(zipURL)
        } else if let releaseURL = URL(string: release.htmlURL) {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    public func openReleaseWebpage(release: GitHubRelease) {
        if let url = URL(string: release.htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Semantic Version Comparison
    /// Returns true if candidate version is strictly greater than current version
    public nonisolated static func isVersion(_ candidate: String, greaterThan current: String) -> Bool {
        let cleanCandidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        let cleanCurrent = current.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))

        let candComponents = parseVersionComponents(cleanCandidate)
        let currComponents = parseVersionComponents(cleanCurrent)

        let maxCount = max(candComponents.count, currComponents.count)
        for i in 0..<maxCount {
            let candVal = (i < candComponents.count) ? candComponents[i] : 0
            let currVal = (i < currComponents.count) ? currComponents[i] : 0
            if candVal > currVal {
                return true
            } else if candVal < currVal {
                return false
            }
        }
        return false
    }

    private nonisolated static func parseVersionComponents(_ version: String) -> [Int] {
        let mainPart = version.components(separatedBy: CharacterSet(charactersIn: "-+")).first ?? version
        return mainPart.split(separator: ".").compactMap { Int($0) }
    }
}
