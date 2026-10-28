# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [0.3.0] - 2026-10-28

### Added
- Animated pet, now the default look: a hand-drawn face with an animation for each state (blinking at rest, loading eyes while thinking, typing on a keyboard while working, a wink and a happy face when done, a question mark when Claude needs you, and "z"s when asleep). The ASCII pet is still available under Settings → Pet style.
- Pet color picker in Settings, for both looks.

### Changed
- The pet sits on a Liquid Glass background on macOS 26 and later.
- The caption under the pet shows the state and the chat name on two lines.

## [0.2.1] - 2026-10-26

### Changed
- Downloads are now drag-to-Applications DMG installers, separate for Apple Silicon (`Claudio-AppleSilicon.dmg`) and Intel (`Claudio-Intel.dmg`), instead of zip files.

## [0.2.0] - 2026-10-26

First public release of Claudio, a desktop companion for Claude Code on macOS.

### Desktop pet
- Floating ASCII pet, always on top and on every Space, with an animation for each state: idle (blinks every 6 s), thinking (the eyes fill up ○ ◔ ◑ ◕ ●), working, done, needs you, and asleep after 15 minutes without activity.
- Drag it anywhere on any display; it remembers its position and comes back into view if a monitor is unplugged. "Reset pet position" in the menu.
- The caption under the pet ("Thinking… · chat name") shifts inward near screen edges and is truncated with "…" if it doesn't fit; a subtle shadow keeps it readable on light backgrounds.

### Reply bubble
- When a chat finishes, a bubble shows the start of Claude's last reply (4 lines at most), its question and the answers it suggests. Clicking an answer copies it and opens that exact chat in the Claude app.
- If it doesn't fit above the pet, the bubble moves below, to the right or to the left, from the very first moment.
- Up to 3 stacked bubbles with an orange counter when several chats need you.
- Closing a bubble with ✕, or switching to the Claude app, stops the pet asking for attention and clears delivered notifications. If you're already in the Claude app, the bubble fades out after 6 seconds.

### Menu bar
- Click the icon for Claude-style usage bars for the 5-hour session and the weekly limit, blue, orange from 70% and red from 90%.
- Hover the icon to list your recent chats with their state; click one to open it.
- Usage is estimated locally from your chat history and calibrated by hand with `/usage`. No login required.

### Notifications and settings
- Sound and macOS notification, set separately for "done" and "needs you". Defaults: no sound when done, "Pop" when Claude asks for permission.
- Settings: open at login, show the pet, sounds, notifications, alert only when the Claude app isn't in front, and a test alert.
- English interface, or Spanish when the Mac is set to Spanish.

### Other
- 100% local: no network access, no accounts, no telemetry, read-only access to Claude's local files.
- App icon, also shown in notifications and bubbles.
- Separate downloads for Apple Silicon (`Claudio-AppleSilicon.zip`) and Intel (`Claudio-Intel.zip`).
- Debug modes `--dump`, `--parse`, `--usage` and `--calibrate`, plus a sample-data mode for screenshots (see `docs/screenshots/`).

[0.3.0]: https://github.com/melikslab/claudio/releases/tag/v0.3.0
[0.2.1]: https://github.com/melikslab/claudio/releases/tag/v0.2.1
[0.2.0]: https://github.com/melikslab/claudio/releases/tag/v0.2.0
