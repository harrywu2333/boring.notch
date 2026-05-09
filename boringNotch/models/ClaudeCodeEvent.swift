import Foundation

enum ClaudeCodeEventType: String, Codable {
    case stop
    case notification
    case preToolUse = "PreToolUse"
}

struct ClaudeCodeEvent: Codable, Identifiable {
    let id: UUID
    let eventType: ClaudeCodeEventType
    let sessionId: String
    let toolName: String?
    let toolInput: String?
    let message: String?
    let cwd: String?
    let origin: String?
    let timestamp: Date

    // Session-level stats (from hook events)
    let currentFile: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalCostUsd: Double?
    let mcpServerCount: Int?
    let hookCount: Int?
    let toolCount: Int?
    let durationMs: Int?

    init(
        eventType: ClaudeCodeEventType,
        sessionId: String,
        toolName: String? = nil,
        toolInput: String? = nil,
        message: String? = nil,
        cwd: String? = nil,
        origin: String? = nil,
        currentFile: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalCostUsd: Double? = nil,
        mcpServerCount: Int? = nil,
        hookCount: Int? = nil,
        toolCount: Int? = nil,
        durationMs: Int? = nil
    ) {
        self.id = UUID()
        self.eventType = eventType
        self.sessionId = sessionId
        self.toolName = toolName
        self.toolInput = toolInput
        self.message = message
        self.cwd = cwd
        self.origin = origin
        self.timestamp = Date()
        self.currentFile = currentFile
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalCostUsd = totalCostUsd
        self.mcpServerCount = mcpServerCount
        self.hookCount = hookCount
        self.toolCount = toolCount
        self.durationMs = durationMs
    }
}

enum ClaudeCodeSessionOrigin: String {
    case terminal
    case vscode
}

struct ClaudeCodePermissionRequest: Identifiable {
    let id: UUID
    let event: ClaudeCodeEvent
    let socketFileDescriptor: Int32

    init(event: ClaudeCodeEvent, socketFileDescriptor: Int32) {
        self.id = event.id
        self.event = event
        self.socketFileDescriptor = socketFileDescriptor
    }
}
