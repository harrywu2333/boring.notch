import Foundation
import Defaults
import SwiftUI
import Combine

enum PomodoroState {
    case idle
    case work
    case shortBreak
    case longBreak

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
}

@MainActor
class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published var state: PomodoroState = .idle
    @Published var timeRemaining: Double = 0
    @Published var isRunning: Bool = false
    @Published var completedSessions: Int = 0

    private var timer: Timer?

    var totalTime: Double {
        switch state {
        case .idle, .work:
            return Defaults[.pomodoroWorkDuration]
        case .shortBreak:
            return Defaults[.pomodoroBreakDuration]
        case .longBreak:
            return Defaults[.pomodoroLongBreakDuration]
        }
    }

    var formattedTime: String {
        let total = max(0, Int(timeRemaining))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var progress: Double {
        guard totalTime > 0 else { return 0 }
        return 1.0 - (timeRemaining / totalTime)
    }

    private init() {
        timeRemaining = Defaults[.pomodoroWorkDuration]
    }

    func start() {
        guard !isRunning else { return }
        if state == .idle {
            state = .work
            timeRemaining = totalTime
        }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.timerTick()
            }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        state = .idle
        completedSessions = 0
        timeRemaining = Defaults[.pomodoroWorkDuration]
    }

    func skip() {
        timer?.invalidate()
        timer = nil
        sessionCompleted()
    }

    private func timerTick() {
        guard isRunning else { return }
        timeRemaining -= 1
        if timeRemaining <= 0 {
            sessionCompleted()
        }
    }

    private func sessionCompleted() {
        pause()

        switch state {
        case .work:
            completedSessions += 1
            if completedSessions % Defaults[.pomodoroLongBreakInterval] == 0 {
                state = .longBreak
            } else {
                state = .shortBreak
            }
            timeRemaining = totalTime

            if Defaults[.pomodoroSoundNotification] {
                playNotificationSound()
            }
            showSneakPeek(icon: "cup.and.saucer.fill")

            if Defaults[.pomodoroAutoStartBreaks] {
                start()
            }

        case .shortBreak, .longBreak:
            state = .work
            timeRemaining = totalTime

            if Defaults[.pomodoroSoundNotification] {
                playNotificationSound()
            }
            showSneakPeek(icon: "brain.head.profile")

            if Defaults[.pomodoroAutoStartWork] {
                start()
            }

        case .idle:
            break
        }
    }

    private func playNotificationSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "boring", fileExtension: "m4a")
    }

    private func showSneakPeek(icon: String) {
        BoringViewCoordinator.shared.toggleSneakPeek(
            status: true,
            type: .pomodoro,
            duration: 5.0,
            value: 0,
            icon: icon
        )
    }
}
