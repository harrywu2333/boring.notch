import Defaults
import SwiftUI

struct ClipboardView: View {
    @ObservedObject var manager = ClipboardManager.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                // Header
                HStack {
                    Text("Clipboard")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    if !manager.entries.isEmpty {
                        Button(action: { manager.clear() }) {
                            Text("Clear")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)

                // Entries list
                if manager.entries.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "clipboard")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No items yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(manager.entries) { entry in
                                clipboardEntryRow(entry)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(maxHeight: 180)
                }
            }
            .padding(.top, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func clipboardEntryRow(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: entry.type == .url ? "link" : "doc.plaintext")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            // Content
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.preview)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Time
            Text(entry.timeAgo)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(manager.lastCopied?.id == entry.id ? Color.green.opacity(0.15) : Color.white.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            manager.copyToClipboard(entry)
        }
        .contextMenu {
            Button("Copy") {
                manager.copyToClipboard(entry)
            }
            if entry.type == .url, let url = URL(string: entry.content) {
                Button("Open URL") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Remove", role: .destructive) {
                manager.remove(entry)
            }
        }
    }
}

struct ClipboardClosedNotchView: View {
    @ObservedObject var manager = ClipboardManager.shared

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clipboard.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("\(manager.entries.count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(height: 30, alignment: .center)
    }
}
