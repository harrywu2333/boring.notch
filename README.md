<h1 align="center">
  <br>
  <a href="http://theboring.name"><img src="https://framerusercontent.com/images/RFK4vs0kn8pRMuOO58JeyoemXA.png?scale-down-to=256" alt="Boring Notch" width="150"></a>
  <br>
  Boring Notch
  <br>
</h1>

<p align="center">
  A fork of <a href="https://github.com/TheBoredTeam/boring.notch">Boring Notch</a> with personal additions.
</p>

A dynamic MacBook notch overlay built with SwiftUI. This fork adds a Pomodoro timer, removes the Shelf/AirDrop feature, and keeps all the original media playback, calendar, and HUD functionality.

## What's Different

- **Pomodoro Timer** — Work/break countdown timer accessible from the notch. Shows countdown in the closed notch, full controls in the expanded view. Configurable durations in Settings.
- **Shelf/AirDrop removed** — The file staging Shelf tab has been disconnected to simplify the UI.
- **Now Playing as default media source** — Uses the system MediaRemote framework to detect and control any media app (Spotify, browsers, NeteaseMusic, etc.), not just Apple Music.
- **Unique bundle ID** — `com.hw.boringnotch` so it doesn't conflict with the official app.

## Building from Source

### Prerequisites

- macOS 14 or later
- Xcode 16 or later

### Build & Run

```bash
git clone https://github.com/harrywu2333/boring.notch.git
cd boring.notch
xcodebuild build -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -destination 'platform=macOS'
open ~/Library/Developer/Xcode/DerivedData/boringNotch-*/Build/Products/Debug/boringNotch.app
```

### Post-Setup

1. **Grant Accessibility** — System Settings > Privacy & Security > Accessibility > enable boringNotch
2. **Select media source** — In app settings, choose "Now Playing" to control any media app
3. **Enable Pomodoro** — In app settings, toggle "Show Pomodoro timer"

## Features (from upstream)

- Music playback live activity with visualizer
- Calendar & Reminders integration
- Camera mirror
- Battery indicator & charging animation
- System HUD replacements (volume, brightness, backlight)
- Multi-monitor support
- Customizable notch sizing

## Acknowledgments

Based on [Boring Notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam.
