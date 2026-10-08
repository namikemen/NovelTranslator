import Testing
import Foundation
@testable import NovelTranslator

@Suite("App Update Manager Tests")
struct AppUpdateManagerTests {

    @Test("Semantic version comparison correctly identifies newer versions")
    func testSemanticVersionComparison() {
        // Newer patch
        #expect(AppUpdateManager.isVersion("1.0.1", greaterThan: "1.0.0") == true)
        #expect(AppUpdateManager.isVersion("v1.0.1", greaterThan: "1.0.0") == true)
        #expect(AppUpdateManager.isVersion("1.0.10", greaterThan: "1.0.9") == true)

        // Newer minor
        #expect(AppUpdateManager.isVersion("1.1.0", greaterThan: "1.0.9") == true)
        #expect(AppUpdateManager.isVersion("v1.2", greaterThan: "1.1.5") == true)

        // Newer major
        #expect(AppUpdateManager.isVersion("2.0.0", greaterThan: "1.99.99") == true)

        // Same version
        #expect(AppUpdateManager.isVersion("1.0.0", greaterThan: "1.0.0") == false)
        #expect(AppUpdateManager.isVersion("v1.0.0", greaterThan: "1.0.0") == false)
        #expect(AppUpdateManager.isVersion("1.0", greaterThan: "1.0.0") == false)

        // Older version
        #expect(AppUpdateManager.isVersion("0.9.9", greaterThan: "1.0.0") == false)
        #expect(AppUpdateManager.isVersion("1.0.0", greaterThan: "1.0.1") == false)
        #expect(AppUpdateManager.isVersion("1.1.2", greaterThan: "1.2.0") == false)

        // Prerelease suffix handling
        #expect(AppUpdateManager.isVersion("1.2.3-beta.1", greaterThan: "1.2.2") == true)
    }

    @Test("GitHubRelease decodes standard GitHub API release response")
    func testGitHubReleaseDecoding() throws {
        let json = """
        {
            "tag_name": "v1.1.0",
            "name": "NovelTranslator 1.1.0 - Enhanced TTS & Chapter Cache",
            "body": "## What's Changed\\n- Added automatic updates\\n- Improved performance",
            "html_url": "https://github.com/namikemen/NovelTranslator/releases/tag/v1.1.0",
            "published_at": "2026-10-08T10:00:00Z",
            "assets": [
                {
                    "name": "NovelTranslator-macOS.zip",
                    "browser_download_url": "https://github.com/namikemen/NovelTranslator/releases/download/v1.1.0/NovelTranslator-macOS.zip",
                    "size": 15420000
                },
                {
                    "name": "NovelTranslator-macOS.zip.sha256",
                    "browser_download_url": "https://github.com/namikemen/NovelTranslator/releases/download/v1.1.0/NovelTranslator-macOS.zip.sha256",
                    "size": 64
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        #expect(release.tagName == "v1.1.0")
        #expect(release.cleanVersionString == "1.1.0")
        #expect(release.displayTitle.contains("NovelTranslator 1.1.0"))
        #expect(release.assets.count == 2)
        #expect(release.assets[0].name == "NovelTranslator-macOS.zip")
        #expect(release.assets[0].browserDownloadURL.contains("download/v1.1.0"))
        #expect(release.assets[0].size == 15420000)
    }

    @MainActor
    @Test("AppUpdateManager initializes with default state and current version")
    func testManagerInitialState() {
        let manager = AppUpdateManager()
        #expect(manager.isChecking == false)
        #expect(manager.updateAvailable == nil)
        #expect(manager.showUpdateSheet == false)
        #expect(!manager.currentAppVersion.isEmpty)
    }
}
