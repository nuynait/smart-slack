# SmartSlack - Claude Code Instructions

## Project Overview

SmartSlack is a macOS menu bar app that monitors Slack conversations on schedules, uses Claude Code CLI to analyze new messages and draft replies, and lets users send/rewrite/ignore drafts.

## Build & Run

```bash
xcodegen generate      # Generate Xcode project from project.yml
xcodebuild -project SmartSlack.xcodeproj -scheme SmartSlack -configuration Debug build
```

Always run `xcodegen generate` after adding or removing Swift files.

## Architecture

- **Models/** - Data types: `Schedule`, `Session`, `SlackMessage`, `SlackFile`
- **Services/** - Business logic: `SlackService` (actor), `ClaudeService` (subprocess), `SchedulerEngine` (timers), `ScheduleStore` (JSON persistence), `LogService`, `KeychainService`, `UserColorStore`
- **ViewModels/** - `AppViewModel` is the root state manager
- **Views/** - SwiftUI views using `@EnvironmentObject` for state
- **Utilities/** - `Constants.swift` (paths, config), `Extensions.swift` (colors, formatters, button styles)

See `doc/design.md` for detailed system design, data models, execution flows, and implementation guide.

## Key Patterns

- macOS Form layout: use `ScrollView` + `VStack` + `.formCard()` modifier, NOT SwiftUI `Form` (causes half-width issues on macOS)
- Buttons: use custom styles `.primary`, `.secondary`, `.destructive`, `.smallSecondary` defined in Extensions.swift
- Slack API: actor-based `SlackService` with snake_case JSON decoding
- Claude CLI: `claude --print --output-format text` via `Process`, prompt on stdin, parse JSON from stdout
- File persistence: individual JSON files per schedule in `~/Library/Application Support/SmartSlack/schedules/`
- New files: always run `xcodegen generate` after creating new `.swift` files

## Important Rules

- **Update `doc/design.md`** whenever you change architecture, add models/services/views, or modify data flow
- Owner messages (from token holder) are identified by `appVM.slackUserId` — they get `.primary` color, gray background, and "owner" label in conversations
- `Schedule.pendingMessages` stores owner-only messages between Claude sessions — must default to `[]` in decoder for backward compatibility
- `IntervalPickerView` slider renders async (100ms delay) to prevent UI freeze
- The `--file` flag does NOT work with `claude --print` — don't use it
- `latestSession` returns the latest session with a non-nil summary (Claude-processed), not just `sessions.last`
