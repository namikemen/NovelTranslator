import SwiftUI

public struct UpdateAvailableSheet: View {
    @ObservedObject var updateManager: AppUpdateManager
    let release: GitHubRelease
    @Environment(\.dismiss) private var dismiss

    public init(updateManager: AppUpdateManager, release: GitHubRelease) {
        self.updateManager = updateManager
        self.release = release
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text("New Version Available!")
                        .font(.headline)
                    Text("\(release.displayTitle) (Current: v\(updateManager.currentAppVersion))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            if let body = release.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Release Notes:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(body)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 160)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                }
            } else {
                Text("A new release is ready with improvements, speed enhancements, and bug fixes.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("View on GitHub") {
                    updateManager.openReleaseWebpage(release: release)
                }
                .buttonStyle(.link)

                Spacer()

                Button("Later") {
                    dismiss()
                }

                Button("Download Update") {
                    updateManager.downloadAndOpen(release: release)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
