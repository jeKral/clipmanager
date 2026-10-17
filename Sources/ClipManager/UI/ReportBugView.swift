import SwiftUI
import ClipManagerCore

// MARK: - ReportBugView

/// Dialog for sending an anonymous bug report. Prefer the relay (which
/// creates the GitHub issue server-side); fall back to a prefilled issue
/// form opened in the browser.
struct ReportBugView: View {

    @ObservedObject var license: LicenseStore
    let onClose: () -> Void

    @State private var message: String = ""
    @State private var isSending = false
    @State private var statusText: String?

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hlásit chybu")
                .font(.headline)

            Text("Hlášení je anonymní — obsahuje verzi aplikace, macOS, architekturu, anonymizované ID zařízení a výňatek logu. Obsah schránky se NENÍ zařazuje.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $message)
                .font(.body)
                .frame(minHeight: 110, maxHeight: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                )

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Zrušit") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button(isSending ? "Odsílám…" : "Odeslat") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedMessage.isEmpty || isSending)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func submit() {
        guard !isSending, !trimmedMessage.isEmpty else { return }
        isSending = true
        statusText = nil

        Task {
            let outcome = await BugReporter.submit(message: trimmedMessage, license: license)
            switch outcome {
            case .issueCreated(let url):
                NSWorkspace.shared.open(url)
                statusText = "Děkujeme! Na GitHubu byl vytvořen anonymní issue: \(url.absoluteString)"
            case .prefilledOpened:
                statusText = "Otevřel jsem formulář v prohlížeči — dokonči posílání (přihlášení do GitHubu stačí jednorázově)."
            }
            isSending = false
        }
    }
}
