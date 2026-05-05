import Defaults
import SwiftUI

struct PomodoroView: View {
    @ObservedObject var manager = PomodoroManager.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(manager.state.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text(manager.formattedTime)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 20) {
                    Button(action: { manager.reset() }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.gray)

                    Button(action: {
                        manager.isRunning ? manager.pause() : manager.start()
                    }) {
                        Image(systemName: manager.isRunning ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)

                    Button(action: { manager.skip() }) {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.gray)
                }

                Text("Sessions: \(manager.completedSessions)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct PomodoroClosedNotchView: View {
    @ObservedObject var manager = PomodoroManager.shared

    var body: some View {
        Text(manager.formattedTime)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(height: 30, alignment: .center)
    }
}
