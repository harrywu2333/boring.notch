import Foundation
import AppKit
import Defaults
import SwiftUI

struct ClipboardEntry: Identifiable, Equatable {
    let id: UUID
    let content: String
    let type: ClipboardType
    let timestamp: Date

    enum ClipboardType: String {
        case text
        case url
    }

    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 80 {
            return String(trimmed.prefix(80)) + "…"
        }
        return trimmed
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }

    static func == (lhs: ClipboardEntry, rhs: ClipboardEntry) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published var entries: [ClipboardEntry] = []
    @Published var lastCopied: ClipboardEntry?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let maxEntries = 20

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
        if Defaults[.showClipboardManager] {
            start()
        }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let content = pasteboard.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        // Skip if same as last entry
        if entries.first?.content == content { return }

        let type: ClipboardEntry.ClipboardType = {
            if let _ = URL(string: content), content.hasPrefix("http") {
                return .url
            }
            return .text
        }()

        let entry = ClipboardEntry(
            id: UUID(),
            content: content,
            type: type,
            timestamp: Date()
        )

        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    func copyToClipboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.content, forType: .string)
        lastCopied = entry
        lastChangeCount = pasteboard.changeCount
    }

    func clear() {
        entries.removeAll()
    }

    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
    }
}
