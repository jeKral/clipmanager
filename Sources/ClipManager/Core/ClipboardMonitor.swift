import AppKit
import Combine

final class ClipboardMonitor {

    static let shared = ClipboardMonitor()

    var onNewItem: ((ClipboardItem) -> Void)?

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    /// The pasteboard `changeCount` produced by our own programmatic writes
    /// (auto-paste / manual copy). Only *that exact* change is skipped on the
    /// next poll. This replaces the old `ignoringNextChange` bool flag, which was
    /// racy: a user copy that landed right after a paste was also swallowed.
    private var ignoredChangeCount: Int?

    private init() {}

    /// Call immediately AFTER writing to the general pasteboard from our own code.
    /// `changeCount` updates synchronously on write, so this captures the exact
    /// value the next poll will see, and lets us skip just that one change.
    func markOwnWrite() {
        ignoredChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Control

    func start() {
        guard timer == nil else { return }
        // Use a RunLoop timer so it fires even during scroll events
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private func checkForChanges() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        // Skip the change we produced ourselves (auto-paste / re-copy).
        if current == ignoredChangeCount {
            ignoredChangeCount = nil
            return
        }

        guard let storageDir = ClipboardStore.shared.storageDirectory else { return }
        guard let item = ClipboardItemFactory.fromCurrentPasteboard(storageDirectory: storageDir) else { return }

        onNewItem?(item)
    }
}
