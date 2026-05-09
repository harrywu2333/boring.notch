import Defaults
import SwiftUI

struct ClaudeCodeView: View {
    @ObservedObject var manager = ClaudeCodeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                if let permission = manager.pendingPermission {
                    permissionView(permission)
                } else if manager.isActive || manager.lastEvent != nil {
                    activeSessionView
                } else {
                    idleView
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var idleView: some View {
        VStack(spacing: 6) {
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Claude Code")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(manager.isConnected ? "Listening" : "Not connected")
                .font(.caption2)
                .foregroundStyle(manager.isConnected ? .green : .secondary)
        }
    }

    private var activeSessionView: some View {
        VStack(spacing: 8) {
            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(manager.isActive ? .orange : .green)
                    .frame(width: 6, height: 6)
                Text(manager.isActive ? "Working..." : "Done")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            // Current file
            if let file = manager.currentFile {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(fileShortName(file))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            // Session stats
            HStack(spacing: 12) {
                statBadge(
                    icon: "arrow.up.circle.fill",
                    label: formatTokens(manager.totalInputTokens),
                    color: .blue
                )
                statBadge(
                    icon: "arrow.down.circle.fill",
                    label: formatTokens(manager.totalOutputTokens),
                    color: .green
                )
                statBadge(
                    icon: "wrench.and.screwdriver.fill",
                    label: "\(manager.toolCallCount)",
                    color: .orange
                )
            }

            // Config stats
            HStack(spacing: 12) {
                statBadge(
                    icon: "server.rack",
                    label: "\(manager.mcpServerCount) MCPs",
                    color: .purple
                )
                statBadge(
                    icon: "link",
                    label: "\(manager.configuredHookCount) hooks",
                    color: .cyan
                )
                statBadge(
                    icon: "doc.plaintext",
                    label: "\(manager.ruleCount) rules",
                    color: .mint
                )
            }

            // Last tool used
            if let event = manager.lastEvent, let toolName = event.toolName {
                Text(toolName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: Capsule())
            }

            // Jump to source button
            if manager.lastEvent?.cwd != nil || manager.currentFile != nil {
                Button(action: { manager.jumpToSource() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.up.left")
                        Text("Jump to source")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    private func statBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func permissionView(_ request: ClaudeCodePermissionRequest) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.yellow)
                Text("Permission Required")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
            }

            if let toolName = request.event.toolName {
                Text(toolName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if let toolInput = request.event.toolInput {
                Text(toolInput)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(6)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 16) {
                Button(action: { manager.denyPermission() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Deny")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.red.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: { manager.approvePermission() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Approve")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fileShortName(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count > 2 {
            return "…/" + components.suffix(2).joined(separator: "/")
        }
        return path
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

struct ClaudeCodeClosedNotchView: View {
    @ObservedObject var manager = ClaudeCodeManager.shared

    var body: some View {
        HStack(spacing: 6) {
            if manager.pendingPermission != nil {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 12))
                Text("Permission")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
            } else if manager.isActive {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                HStack(spacing: 3) {
                    Text("Claude")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if let file = manager.currentFile {
                        Text(fileShortName(file))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else if let event = manager.lastEvent {
                Circle()
                    .fill(event.eventType == .stop ? .green : .orange)
                    .frame(width: 6, height: 6)
                Text(event.eventType == .stop ? "Done" : "Claude")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Claude")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 30, alignment: .center)
    }

    private func fileShortName(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count > 1 {
            return components.last ?? path
        }
        return path
    }
}
