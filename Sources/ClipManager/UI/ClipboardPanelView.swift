import SwiftUI

// MARK: - ClipboardPanelView

struct ClipboardPanelView: View {

    @EnvironmentObject var store: ClipboardStore

    @State private var selectedIndex: Int = 0
    @State private var searchText: String = ""
    @FocusState private var isFocused: Bool

    private var displayItems: [ClipboardItem] {
        // Pinned items always at top, then rest sorted by timestamp desc
        let pinned   = store.items.filter { $0.isPinned }
        let unpinned = store.items.filter { !$0.isPinned }
        return pinned + unpinned
    }

    private var delegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    var body: some View {
        ZStack {
            // Background: glass material
            GlassBackground()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                itemList
                Divider().opacity(0.4)
                footer
            }
        }
        .frame(width: 420, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 28, x: 0, y: 14)
        .padding(8)
        .focusable()
        .focused($isFocused)
        .panelKeyboardShortcuts(
            escape:    { closePanel() },
            upArrow:   { moveSelection(by: -1) },
            downArrow: { moveSelection(by: 1) },
            returnKey: { pasteSelected() }
        )
        .onAppear {
            selectedIndex = 0
            isFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clipboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Historie schránky")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Text("\(store.items.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Button {
                store.clearAll(keepPinned: true)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Vymazat historii (zachovat připnuté)")

            Button {
                (NSApp.delegate as? AppDelegate)?.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Nastavení")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - List

    private var itemList: some View {
        Group {
            if displayItems.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemView(
                                    item: item,
                                    isSelected: selectedIndex == index
                                )
                                .id(item.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    pasteItem(item)
                                }
                                .contextMenu {
                                    itemContextMenu(item: item)
                                }

                                if index < displayItems.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 12)
                                        .opacity(0.3)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { idx in
                        if let item = displayItems[safe: idx] {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(item.id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("Schránka je prázdná")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Label("Vybrat", systemImage: "return")
            Label("Navigovat", systemImage: "arrow.up.arrow.down")
            Label("Zavřít", systemImage: "escape")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.quaternary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func itemContextMenu(item: ClipboardItem) -> some View {
        Button(item.isPinned ? "Odepnout" : "Připnout") {
            store.togglePin(item)
        }
        Divider()
        Button("Smazat", role: .destructive) {
            store.removeItem(item)
            selectedIndex = min(selectedIndex, max(0, displayItems.count - 2))
        }
    }

    // MARK: - Actions

    private func pasteItem(_ item: ClipboardItem) {
        if AppSettings.shared.pasteOnSelect {
            delegate?.pasteItem(item)
        } else {
            PasteService.writeToPasteboard(item)
            ClipboardMonitor.shared.markOwnWrite()
            closePanel()
        }
    }

    private func pasteSelected() {
        guard let item = displayItems[safe: selectedIndex] else { return }
        pasteItem(item)
    }

    private func closePanel() {
        delegate?.closePanel()
    }

    private func moveSelection(by delta: Int) {
        guard !displayItems.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), displayItems.count - 1)
    }
}

// MARK: - GlassBackground

struct GlassBackground: View {
    var body: some View {
        ZStack {
            if #available(macOS 26, *) {
                Color.clear
                    .background(.regularMaterial)
            } else {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            }
        }
    }
}

// MARK: - NSVisualEffectView wrapper

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material      = material
        v.blendingMode  = blendingMode
        v.state         = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material     = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Keyboard shortcuts (macOS 14+; fallback: mouse + auto-close)

private extension View {
    @ViewBuilder
    func panelKeyboardShortcuts(
        escape: @escaping () -> Void,
        upArrow: @escaping () -> Void,
        downArrow: @escaping () -> Void,
        returnKey: @escaping () -> Void
    ) -> some View {
        if #available(macOS 14.0, *) {
            self
                .onKeyPress(.escape)    { escape();    return .handled }
                .onKeyPress(.upArrow)   { upArrow();   return .handled }
                .onKeyPress(.downArrow) { downArrow(); return .handled }
                .onKeyPress(.return)    { returnKey(); return .handled }
        } else {
            self
        }
    }
}
