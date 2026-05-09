import Foundation
import Defaults
import SwiftUI
import Combine

@MainActor
class ClaudeCodeManager: ObservableObject {
    static let shared = ClaudeCodeManager()

    @Published var isConnected: Bool = false
    @Published var lastEvent: ClaudeCodeEvent?
    @Published var recentEvents: [ClaudeCodeEvent] = []
    @Published var pendingPermission: ClaudeCodePermissionRequest?
    @Published var isActive: Bool = false
    @Published var hooksInstalled: Bool = false

    // Session tracking
    @Published var currentFile: String?
    @Published var totalInputTokens: Int = 0
    @Published var totalOutputTokens: Int = 0
    @Published var totalCostUsd: Double = 0
    @Published var toolCallCount: Int = 0
    @Published var lastDurationMs: Int = 0

    // Computed Claude Code config stats
    var mcpServerCount: Int {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcp = settings["mcpServers"] as? [String: Any]
        else { return 0 }
        return mcp.count
    }

    var configuredHookCount: Int {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any]
        else { return 0 }
        var count = 0
        for (_, entries) in hooks {
            if let entries = entries as? [[String: Any]] {
                for entry in entries {
                    if let handlers = entry["hooks"] as? [[String: Any]] {
                        count += handlers.count
                    }
                }
            }
        }
        return count
    }

    var ruleCount: Int {
        let claudeMdPaths = [
            NSHomeDirectory() + "/.claude/CLAUDE.md",
            NSHomeDirectory() + "/.claude/settings.json"
        ]
        var count = 0
        for path in claudeMdPaths {
            if FileManager.default.fileExists(atPath: path) {
                count += 1
            }
        }
        // Check project-level CLAUDE.md
        let projectClaudeMd = FileManager.default.currentDirectoryPath + "/CLAUDE.md"
        if FileManager.default.fileExists(atPath: projectClaudeMd) {
            count += 1
        }
        return count
    }

    private var socketFileDescriptor: Int32 = -1
    private var listeningTask: Task<Void, Never>?
    private var cleanupTimer: Timer?

    // Tools that only read data — safe to auto-approve
    private let safeReadTools: Set<String> = [
        "Read", "Grep", "Glob", "NotebookRead",
        "WebFetch", "WebSearch", "TodoRead", "Task",
        "Agent", "mcp__.*__read.*", "mcp__.*__search.*",
        "mcp__.*__list.*", "mcp__.*__get.*"
    ]

    private let socketPath: String = {
        let dir = NSHomeDirectory() + "/.boringnotch"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/claude-code.sock"
    }()

    private let hookScriptDir = NSHomeDirectory() + "/.claude/hooks"
    private let hookScriptPath = NSHomeDirectory() + "/.claude/hooks/boringnotch-hook.sh"

    private init() {
        hooksInstalled = FileManager.default.fileExists(atPath: hookScriptPath)
        if Defaults[.showClaudeCodeNotifier] {
            start()
        }
    }

    func start() {
        guard socketFileDescriptor == -1 else { return }
        listenForEvents()
        startCleanupTimer()
    }

    func stop() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        listeningTask?.cancel()
        listeningTask = nil
        if socketFileDescriptor >= 0 {
            close(socketFileDescriptor)
            socketFileDescriptor = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
        isConnected = false
    }

    // MARK: - Socket Server

    private func listenForEvents() {
        try? FileManager.default.removeItem(atPath: socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        socketFileDescriptor = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        socketPath.withCString { ptr in
            _ = strncpy(&addr.sun_path.0, ptr, maxLength - 1)
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult >= 0 else {
            close(fd)
            socketFileDescriptor = -1
            return
        }

        guard listen(fd, 5) >= 0 else {
            close(fd)
            socketFileDescriptor = -1
            return
        }

        Task { @MainActor in
            self.isConnected = true
        }

        listeningTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                let sockFD = fd
                let clientFD = accept(sockFD, nil, nil)
                guard clientFD >= 0 else { continue }
                Task.detached {
                    await self?.readAndHandleClient(fd: clientFD)
                }
            }
        }
    }

    private func readAndHandleClient(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = read(fd, &buffer, buffer.count)

        guard bytesRead > 0 else {
            close(fd)
            return
        }

        let data = Data(buffer[0..<Int(bytesRead)])
        guard let event = parseEvent(from: data) else {
            close(fd)
            return
        }

        let needsResponse = event.eventType == .preToolUse

        Task { @MainActor [weak self] in
            self?.handleEvent(event, clientFD: fd, needsResponse: needsResponse)
        }
    }

    private nonisolated func parseEvent(from data: Data) -> ClaudeCodeEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventTypeName = json["hook_event_name"] as? String,
              let eventType = ClaudeCodeEventType(rawValue: eventTypeName),
              let sessionId = json["session_id"] as? String
        else {
            return nil
        }

        let toolName = json["tool_name"] as? String
        let toolInput: String? = {
            if let input = json["tool_input"],
               let inputData = try? JSONSerialization.data(withJSONObject: input, options: .sortedKeys) {
                return String(data: inputData, encoding: .utf8)
            }
            return nil
        }()
        let message = json["message"] as? String ?? json["notification"] as? String
        let cwd = json["cwd"] as? String
        let origin = json["origin"] as? String ?? detectOrigin()

        // Extract file path from tool input
        let currentFile: String? = {
            if let input = json["tool_input"] as? [String: Any] {
                return input["file_path"] as? String ?? input["path"] as? String
            }
            return nil
        }()

        // Session stats (from Stop events or session data)
        let inputTokens = json["input_tokens"] as? Int
        let outputTokens = json["output_tokens"] as? Int
        let totalCostUsd = json["total_cost_usd"] as? Double
        let mcpServerCount = json["mcp_server_count"] as? Int
        let hookCount = json["hook_count"] as? Int
        let toolCount = json["tool_count"] as? Int
        let durationMs = json["duration_ms"] as? Int

        return ClaudeCodeEvent(
            eventType: eventType,
            sessionId: sessionId,
            toolName: toolName,
            toolInput: toolInput,
            message: message,
            cwd: cwd,
            origin: origin,
            currentFile: currentFile,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalCostUsd: totalCostUsd,
            mcpServerCount: mcpServerCount,
            hookCount: hookCount,
            toolCount: toolCount,
            durationMs: durationMs
        )
    }

    private nonisolated func detectOrigin() -> String {
        let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? ""
        if termProgram == "vscode" {
            return "vscode"
        }
        return "terminal"
    }

    private func handleEvent(_ event: ClaudeCodeEvent, clientFD: Int32, needsResponse: Bool) {
        lastEvent = event
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 20 {
            recentEvents = Array(recentEvents.prefix(20))
        }

        // Update session tracking
        if let file = event.currentFile {
            currentFile = file
        }
        if let tokens = event.inputTokens { totalInputTokens = tokens }
        if let tokens = event.outputTokens { totalOutputTokens = tokens }
        if let cost = event.totalCostUsd { totalCostUsd = cost }
        if event.eventType == .preToolUse { toolCallCount += 1 }
        if let ms = event.durationMs { lastDurationMs = ms }

        switch event.eventType {
        case .stop:
            isActive = false
            if Defaults[.claudeCodeSoundNotification] {
                playNotificationSound()
            }
            showSneakPeek(icon: "checkmark.circle.fill")
            close(clientFD)

        case .notification:
            if Defaults[.claudeCodeSoundNotification] {
                playNotificationSound()
            }
            showSneakPeek(icon: "bell.fill")
            close(clientFD)

        case .preToolUse:
            isActive = true
            if shouldAutoApprove(event) {
                sendPermissionResponse(fd: clientFD, approved: true, reason: "Auto-approved (read-only)")
            } else if Defaults[.claudeCodeAutoApprove] {
                sendPermissionResponse(fd: clientFD, approved: true, reason: "Auto-approved")
            } else {
                let request = ClaudeCodePermissionRequest(event: event, socketFileDescriptor: clientFD)
                pendingPermission = request
            }
        }
    }

    private func shouldAutoApprove(_ event: ClaudeCodeEvent) -> Bool {
        guard let toolName = event.toolName else { return false }
        for safeTool in safeReadTools {
            if toolName.range(of: safeTool, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Permission

    func approvePermission() {
        guard let request = pendingPermission else { return }
        sendPermissionResponse(fd: request.socketFileDescriptor, approved: true, reason: "Approved by user")
        pendingPermission = nil
        // Jump to source after approving
        jumpToSource()
    }

    func denyPermission() {
        guard let request = pendingPermission else { return }
        sendPermissionResponse(fd: request.socketFileDescriptor, approved: false, reason: "Denied by user")
        pendingPermission = nil
    }

    private func sendPermissionResponse(fd: Int32, approved: Bool, reason: String) {
        let decision = approved ? "allow" : "deny"
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason
            ]
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: response) {
            jsonData.withUnsafeBytes { ptr in
                _ = write(fd, ptr.baseAddress, jsonData.count)
            }
        }
        close(fd)
    }

    // MARK: - Jump to Source

    func jumpToSource() {
        let event = pendingPermission?.event ?? lastEvent
        guard let event = event else { return }

        // Determine the target path: use file if available, otherwise cwd
        let targetPath: String
        if let file = event.currentFile {
            targetPath = file
        } else if let cwd = event.cwd {
            targetPath = cwd
        } else {
            return
        }

        let origin = event.origin ?? "terminal"

        switch origin {
        case "vscode":
            openInVSCode(path: targetPath)

        default:
            openInTerminal()
        }
    }

    private func openInVSCode(path: String) {
        // Try multiple known locations for `code` CLI
        let codePaths = [
            "/usr/local/bin/code",
            "/opt/homebrew/bin/code",
            NSHomeDirectory() + "/.local/bin/code"
        ]

        for codePath in codePaths {
            guard FileManager.default.isExecutableFile(atPath: codePath) else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: codePath)
            process.arguments = ["--reuse-window", path]
            try? process.run()
            return
        }

        // Fallback: use `open -a "Visual Studio Code"` with the path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Visual Studio Code", path]
        try? process.run()
    }

    private func openInTerminal() {
        let script = """
        tell application "System Events"
            set terminalApps to name of every process whose background only is false and name contains "Terminal"
            set itermApps to name of every process whose background only is false and name contains "iTerm"
            set allApps to terminalApps & itermApps
            if (count of allApps) > 0 then
                tell application (item 1 of allApps) to activate
            else
                tell application "Terminal" to activate
            end if
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
    }

    // MARK: - Hook Installation

    func installHooks() {
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(atPath: hookScriptDir, withIntermediateDirectories: true)
            let hookScript = generateHookScript()
            try hookScript.write(toFile: hookScriptPath, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptPath)
            updateClaudeCodeSettings(install: true)
            hooksInstalled = true
            print("Claude Code hooks installed to \(hookScriptPath)")
        } catch {
            print("Failed to install Claude Code hooks: \(error)")
        }
    }

    func uninstallHooks() {
        try? FileManager.default.removeItem(atPath: hookScriptPath)
        updateClaudeCodeSettings(install: false)
        hooksInstalled = false
    }

    private func generateHookScript() -> String {
        return """
        #!/usr/bin/env python3
        \"\"\"Boring Notch Claude Code hook script.\"\"\"
        import json, socket, sys, os, time

        SOCKET_PATH = "\(socketPath)"

        # Track session stats
        STATE_FILE = os.path.expanduser("~/.boringnotch/claude-session-state.json")

        def load_state():
            try:
                with open(STATE_FILE) as f:
                    return json.load(f)
            except:
                return {"tool_count": 0, "start_time": time.time()}

        def save_state(state):
            try:
                os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
                with open(STATE_FILE, "w") as f:
                    json.dump(state, f)
            except:
                pass

        def enrich_event(event_data):
            \"\"\"Add session stats and origin to event data.\"\"\"
            event_data["origin"] = "vscode" if os.environ.get("VSCODE_INJECTION") else \
                "vscode" if os.environ.get("TERM_PROGRAM") == "vscode" else "terminal"

            state = load_state()
            state["tool_count"] = state.get("tool_count", 0) + 1
            event_data["tool_count"] = state["tool_count"]
            event_data["duration_ms"] = int((time.time() - state.get("start_time", time.time())) * 1000)

            # Extract file path from tool_input
            tool_input = event_data.get("tool_input", {})
            if isinstance(tool_input, dict):
                if "file_path" in tool_input:
                    event_data["current_file"] = tool_input["file_path"]
                elif "path" in tool_input:
                    event_data["current_file"] = tool_input["path"]

            # Add config stats for Stop events
            if event_data.get("hook_event_name") in ("Stop", "StopFailure"):
                try:
                    settings_path = os.path.expanduser("~/.claude/settings.json")
                    with open(settings_path) as f:
                        settings = json.load(f)
                    mcp = settings.get("mcpServers", {})
                    event_data["mcp_server_count"] = len(mcp)
                    hooks = settings.get("hooks", {})
                    hook_count = 0
                    for entries in hooks.values():
                        if isinstance(entries, list):
                            for entry in entries:
                                if isinstance(entry, dict):
                                    hook_count += len(entry.get("hooks", []))
                    event_data["hook_count"] = hook_count
                except:
                    pass

            save_state(state)
            return event_data

        def send_event(event_data):
            event_data = enrich_event(event_data)
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                sock.settimeout(5)
                sock.connect(SOCKET_PATH)
                sock.sendall(json.dumps(event_data).encode())
                return sock
            except Exception:
                try: sock.close()
                except: pass
                return None

        def handle_permission(event_data):
            sock = send_event(event_data)
            if sock is None:
                return
            try:
                sock.settimeout(30)
                response_data = sock.recv(4096)
                if response_data:
                    resp = json.loads(response_data)
                    output = resp.get("hookSpecificOutput", {})
                    decision = output.get("permissionDecision", "allow")
                    reason = output.get("permissionDecisionReason", "")
                    result = {
                        "hookSpecificOutput": {
                            "hookEventName": "PreToolUse",
                            "permissionDecision": decision,
                            "permissionDecisionReason": reason
                        }
                    }
                    print(json.dumps(result))
                    if decision == "deny":
                        sys.exit(0)
            except socket.timeout:
                pass
            except Exception:
                pass
            finally:
                try: sock.close()
                except: pass

        def handle_notification(event_data):
            sock = send_event(event_data)
            if sock:
                try: sock.close()
                except: pass

        def handle_stop():
            # Reset session state on stop
            state = load_state()
            state["start_time"] = time.time()
            state["tool_count"] = 0
            save_state(state)

        def main():
            try:
                event_data = json.load(sys.stdin)
            except Exception:
                return
            event_name = event_data.get("hook_event_name", "")
            if event_name == "PreToolUse":
                handle_permission(event_data)
            elif event_name in ("Stop", "Notification", "StopFailure"):
                handle_notification(event_data)
                if event_name in ("Stop", "StopFailure"):
                    handle_stop()

        if __name__ == "__main__":
            main()
        """
    }

    private func updateClaudeCodeSettings(install: Bool) {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        let fileManager = FileManager.default

        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        if var hooks = settings["hooks"] as? [String: Any] {
            for eventName in ["Stop", "Notification", "PreToolUse"] {
                if var eventHooks = hooks[eventName] as? [[String: Any]] {
                    eventHooks.removeAll { entry in
                        if let handlers = entry["hooks"] as? [[String: Any]] {
                            return handlers.contains { handler in
                                if let cmd = handler["command"] as? String {
                                    return cmd.contains("boringnotch-hook")
                                }
                                return false
                            }
                        }
                        return false
                    }
                    if eventHooks.isEmpty {
                        hooks.removeValue(forKey: eventName)
                    } else {
                        hooks[eventName] = eventHooks
                    }
                }
            }
            settings["hooks"] = hooks.isEmpty ? nil : hooks
        }

        if install {
            if settings["hooks"] == nil {
                settings["hooks"] = [String: Any]()
            }
            var hooks = settings["hooks"] as? [String: Any] ?? [String: Any]()

            let hookEntry: [String: Any] = [
                "type": "command",
                "command": hookScriptPath
            ]

            for eventName in ["Stop", "Notification", "PreToolUse"] {
                var eventHooks = hooks[eventName] as? [[String: Any]] ?? []
                eventHooks.append([
                    "matcher": "",
                    "hooks": [hookEntry]
                ])
                hooks[eventName] = eventHooks
            }
            settings["hooks"] = hooks
        }

        if settings["hooks"] == nil {
            settings.removeValue(forKey: "hooks")
        }

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath))
        }
    }

    // MARK: - Helpers

    private func playNotificationSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "boring", fileExtension: "m4a")
    }

    private func showSneakPeek(icon: String) {
        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .claudeCode,
            duration: 5.0,
            value: 0,
            icon: icon
        )
    }

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let cutoff = Date().addingTimeInterval(-3600)
                self.recentEvents.removeAll { $0.timestamp < cutoff }
            }
        }
    }
}
