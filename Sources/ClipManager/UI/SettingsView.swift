import SwiftUI
import ClipManagerCore

// MARK: - SettingsView

struct SettingsView: View {

    @EnvironmentObject var store: ClipboardStore
    @ObservedObject var license: LicenseStore
    @ObservedObject private var settings = AppSettings.shared

    @State private var isRecordingHotkey = false
    @State private var historyLimitStr: String = ""
    @State private var serialInput: String = ""
    @State private var relayURLStr: String = ""
    @State private var activationError: String?

    var body: some View {
        Form {
            licenseSection
            generalSection
            hotkeySection
            storageSection
            telemetrySection
            updateSection
            dangerSection
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
        .onAppear {
            historyLimitStr = "\(settings.historyLimit)"
            relayURLStr = license.relayURL
        }
    }

    // MARK: - Sections

    private var licenseSection: some View {
        Section("Licence") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(licenseStatusTitle)
                        .font(.headline)
                    Text(license.decision.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Circle()
                    .fill(licenseStatusColor)
                    .frame(width: 10, height: 10)
            }

            if let plan = license.decision.plan {
                HStack {
                    Text("Tarif")
                    Spacer()
                    Text(plan.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            if let expires = license.decision.expiresAt {
                HStack {
                    Text("Platnost do")
                    Spacer()
                    Text(Self.dateFormatter.string(from: expires))
                        .foregroundStyle(.secondary)
                }
            }

            if let error = activationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                TextField("CLIP-SOLO-20261231-XXXXXXXXXXXXXXXXXXXX-xxxxxxxx", text: $serialInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Aktivovat") {
                    activateLicense()
                }
                .disabled(serialInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Text("ID instalace")
                Spacer()
                Text(license.installId)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button("Kopírovat") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(license.installId, forType: .string)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    private var generalSection: some View {
        Section("Obecné") {
            Toggle("Spustit při přihlášení", isOn: $settings.launchAtLogin)

            Toggle("Automaticky vložit (Cmd+V) po výběru", isOn: $settings.pasteOnSelect)

            HStack {
                Text("Limit historie")
                Spacer()
                TextField("100", text: $historyLimitStr)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .onSubmit {
                        if let val = Int(historyLimitStr), val > 0, val <= 10_000 {
                            settings.historyLimit = val
                        } else {
                            historyLimitStr = "\(settings.historyLimit)"
                        }
                    }
                Text("položek")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hotkeySection: some View {
        Section("Klávesová zkratka") {
            HStack {
                Text("Zobrazit historii")
                Spacer()
                HotkeyBadge(displayString: settings.hotkeyDisplayString)
                Button("Změnit…") {
                    // TODO: Present hotkey recorder sheet
                    // For now, show a placeholder
                    showHotkeyPickerAlert()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    private var storageSection: some View {
        Section("Ukládání") {
            Toggle("Zachovat historii přes restart", isOn: $settings.persistHistory)

            HStack {
                Text("Uloženo položek")
                Spacer()
                Text("\(store.items.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button("Vymazat historii (zachovat připnuté)") {
                store.clearAll(keepPinned: true)
            }
            .foregroundStyle(.red)
        }
    }

    private var telemetrySection: some View {
        Section("Telemetrie") {
            Toggle("Posílat anonymní telemetrii (verze, OS, stav licence)", isOn: Binding(
                get: { license.telemetryEnabled },
                set: { license.setTelemetryEnabled($0) }
            ))

            HStack {
                TextField("http://127.0.0.1:8787", text: $relayURLStr)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Uložit") {
                    license.setRelayURL(relayURLStr)
                }
                .disabled(relayURLStr.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .help("Adresa relay služby (licenční kontrola + telemetrie).")

            Button("Hlásit chybu…") {
                (NSApp.delegate as? AppDelegate)?.presentReportBug()
            }
            .help("Anonymní hlášení: vytvoří issue na GitHubu s verzí, OS a výňatkem logu.")
        }
    }

    private var updateSection: some View {
        Section("Aktualizace") {
            Toggle("Kontrolovat aktualizace automaticky", isOn: $settings.checkUpdates)

            Button("Zkontrolovat nyní") {
                UpdateChecker.checkForUpdates(force: true)
            }
        }
    }

    private var dangerSection: some View {
        Section("Přístupnost") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatické vkládání")
                        .font(.body)
                    Text("Vyžaduje povolení v Nastavení systému → Soukromí → Přístupnost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Otevřít nastavení") {
                    PasteService.requestAccessibilityIfNeeded()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Hotkey picker (simplified alert for now)

    private func showHotkeyPickerAlert() {
        let alert = NSAlert()
        alert.messageText = "Klávesová zkratka"
        alert.informativeText = "Úprava klávesové zkratky bude dostupná v další verzi.\n\nAktuální zkratka: \(settings.hotkeyDisplayString)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - License

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d. M. yyyy"
        f.locale = Locale(identifier: "cs_CZ")
        return f
    }()

    private var licenseStatusTitle: String {
        switch license.decision.state {
        case .allowed: return "Platná licence"
        case .grace:   return "Milostné období"
        case .blocked: return "Licence blokována"
        }
    }

    private var licenseStatusColor: Color {
        switch license.decision.state {
        case .allowed: return .green
        case .grace:   return .orange
        case .blocked: return .red
        }
    }

    private func activateLicense() {
        do {
            try license.activate(serial: serialInput)
            activationError = nil
            serialInput = ""
        } catch {
            activationError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

// MARK: - HotkeyBadge

struct HotkeyBadge: View {
    let displayString: String

    var body: some View {
        Text(displayString)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
