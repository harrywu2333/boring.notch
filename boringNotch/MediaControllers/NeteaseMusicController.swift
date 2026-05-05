import Foundation
import Combine
import SwiftUI

class NeteaseMusicController: MediaControllerProtocol {
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.netease.163music",
        playbackRate: 1
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool { return true }
    var supportsFavorite: Bool { return false }

    private var notificationTask: Task<Void, Never>?

    init() {
        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }

    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.netease.163music.playerInfo")
            )
            for await notification in notifications {
                // Try parsing userInfo from notification first (faster than AppleScript)
                if let userInfo = notification.userInfo {
                    await self?.updateFromNotification(userInfo: userInfo)
                }
                // Always re-query via AppleScript for complete state
                await self?.updatePlaybackInfo()
            }
        }
    }

    private func updateFromNotification(userInfo: [AnyHashable: Any]) {
        var updatedState = self.playbackState
        if let name = userInfo["Name"] as? String ?? userInfo["name"] as? String {
            updatedState.title = name
        }
        if let artist = userInfo["Artist"] as? String ?? userInfo["artist"] as? String {
            updatedState.artist = artist
        }
        if let album = userInfo["Album"] as? String ?? userInfo["album"] as? String {
            updatedState.album = album
        }
        if let playing = userInfo["Player State"] as? String {
            updatedState.isPlaying = playing.lowercased() == "playing"
        }
        updatedState.lastUpdated = Date()
        self.playbackState = updatedState
    }

    deinit {
        notificationTask?.cancel()
    }

    func play() async {
        await executeCommand("play")
    }

    func pause() async {
        await executeCommand("pause")
    }

    func togglePlay() async {
        await executeCommand("playpause")
    }

    func nextTrack() async {
        await executeCommand("next track")
    }

    func previousTrack() async {
        await executeCommand("previous track")
    }

    func seek(to time: Double) async {
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }

    func toggleShuffle() async {
        // NetEase AppleScript may not support shuffle
    }

    func toggleRepeat() async {
        // NetEase AppleScript may not support repeat
    }

    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.netease.163music" }
    }

    func setFavorite(_ favorite: Bool) async {
        // NetEase AppleScript does not support favorite
    }

    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 6 else { return }
        var updatedState = self.playbackState

        updatedState.isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        updatedState.title = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        updatedState.artist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        updatedState.album = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        updatedState.currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        updatedState.duration = descriptor.atIndex(6)?.doubleValue ?? 0

        // Try to get artwork if available
        if descriptor.numberOfItems >= 7, let artworkData = descriptor.atIndex(7)?.data as Data?, !artworkData.isEmpty {
            updatedState.artwork = artworkData
        }

        updatedState.lastUpdated = Date()
        self.playbackState = updatedState
    }

    private func executeCommand(_ command: String) async {
        let script = "tell application \"NeteaseMusic\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "NeteaseMusic"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                try
                    set artData to data of artwork 1 of current track
                on error
                    set artData to ""
                end try
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, artData}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, ""}
            end try
        end tell
        """

        return try await AppleScriptHelper.execute(script)
    }
}
