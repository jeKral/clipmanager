import Foundation
import AppKit
import ClipManagerCore

/// Submits a bug report from the app.
///
/// Preferred path: the relay service (`POST /api/v1/bug`) creates a GitHub
/// issue on our behalf with a server-side token, so the user stays anonymous
/// (no GitHub account needed). Used only when anonymous telemetry is enabled.
///
/// Fallback path: open a prefilled GitHub issue form in the browser with the
/// same diagnostics — the user just has to be logged in to GitHub.
enum BugReporter {

    static let issueNewURL = "https://github.com/jeKral/clipmanager/issues/new"

    enum Outcome: Equatable {
        /// The relay created a GitHub issue at this URL.
        case issueCreated(URL)
        /// A prefilled issue form was opened in the browser.
        case prefilledOpened
    }

    /// Builds the prefilled issue title/body from the user's message plus
    /// anonymous diagnostics.
    static func diagnostics(message: String, installId: String) -> (title: String, body: String) {
        let version = Telemetry.appVersion()
        let os = "macOS \(Telemetry.currentOSVersion()) / \(Telemetry.currentArch())"
        let device = Telemetry.anonymizedInstallId(installId)
        let log = LogBuffer.shared.tail(200)

        let title = "[\(version)] \(message)"
        let body = """
        **What happened:**

        \(message)

        **Environment**

        | | |
        |---|---|
        | App | ClipManager \(version) |
        | OS | \(os) |
        | Device (anonymized) | `\(device)` |

        **Recent log**

        ```
        \(log)
        ```

        ---
        _Reported from ClipManager (no clipboard content included)._
        """
        return (title, body)
    }

    static func openPrefilledIssue(_ title: String, _ body: String) {
        var components = URLComponents(string: issueNewURL)
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "body", value: body),
        ]
        guard let url = components?.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Submits the report. Never throws and never blocks on a dead relay:
    /// any relay failure falls back to the prefilled browser form.
    static func submit(message: String, license: LicenseStore) async -> Outcome {
        if license.telemetryEnabled, let baseURL = license.relayBaseURL {
            do {
                let client = RelayClient(baseURL: baseURL)
                let report = Telemetry.currentBugReport(
                    installId: license.installId,
                    message: message,
                    log: LogBuffer.shared.tail(200)
                )
                if let issueURL = try await client.sendBugReport(report) {
                    return .issueCreated(issueURL)
                }
            } catch {
                Log.debug("bug report via relay failed: \(error.localizedDescription)")
            }
        }
        let (title, body) = diagnostics(message: message, installId: license.installId)
        openPrefilledIssue(title, body)
        return .prefilledOpened
    }
}
