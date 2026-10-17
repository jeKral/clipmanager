import Foundation
import AppKit

// MARK: - UpdateChecker
// Simple GitHub Releases-based update checker.
// TODO: Replace with Sparkle 2 for automatic background updates.

enum UpdateChecker {

    private static let repoAPI = "https://api.github.com/repos/jeKral/clipmanager/releases/latest"

    static func checkForUpdates(force: Bool = false) {
        guard AppSettings.shared.checkUpdates || force else { return }

        guard let url = URL(string: repoAPI) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClipManager/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                  !release.draft,
                  !release.prerelease else { return }

            let latest = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName

            guard isNewerVersion(latest, than: currentVersion) else { return }

            DispatchQueue.main.async {
                presentUpdateAlert(latestVersion: latest, releaseURL: release.htmlURL)
            }
        }.resume()
    }

    // MARK: - Helpers

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static func isNewerVersion(_ remote: String, than local: String) -> Bool {
        remote.compare(local, options: .numeric) == .orderedDescending
    }

    private static func presentUpdateAlert(latestVersion: String, releaseURL: String) {
        let alert = NSAlert()
        alert.messageText = "Dostupná nová verze ClipManager \(latestVersion)"
        alert.informativeText = "Stáhni aktualizaci z GitHubu."
        alert.addButton(withTitle: "Stáhnout")
        alert.addButton(withTitle: "Přeskočit")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: releaseURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - GitHub API model

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName    = "tag_name"
        case htmlURL    = "html_url"
        case draft
        case prerelease
    }
}
