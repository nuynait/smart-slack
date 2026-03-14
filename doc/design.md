# SmartSlack - System Design Document

This document describes the architecture, data flow, and implementation details of SmartSlack. It is intended as a reference for developers (or AI coding assistants) working on the codebase.

---

## Overview

SmartSlack is a macOS menu bar application that:
1. Monitors Slack conversations on user-defined schedules
2. Feeds new messages to Claude Code CLI for analysis
3. Presents AI-generated summaries and draft replies
4. Lets the user send, rewrite, or ignore drafts

The app runs persistently in the menu bar. Closing the window does not stop monitoring.

---

## Technology Stack

- **Language:** Swift 5.10
- **UI Framework:** SwiftUI with AppKit integration (NSStatusItem for menu bar)
- **Minimum OS:** macOS 14.0
- **Build System:** XcodeGen (`project.yml`)
- **External Dependencies:** None (pure Apple frameworks + Claude CLI)

---

## File Structure

```
SmartSlack/
├── SmartSlackApp.swift              # @main, Window scene, environment injection
├── AppDelegate.swift                # NSStatusItem menu bar, badge counts, Combine
├── Info.plist                       # App metadata
├── SmartSlack.entitlements          # Empty (sandbox disabled)
├── Assets.xcassets/                 # App icon
│
├── Models/
│   ├── Schedule.swift               # Schedule, Session, DraftEntry, enums
│   └── SlackModels.swift            # Slack API types: SlackChannel, SlackMessage, SlackFile, responses
│
├── Services/
│   ├── SlackService.swift           # Actor-based Slack REST client
│   ├── ClaudeService.swift          # Claude CLI Process spawning
│   ├── SchedulerEngine.swift        # Timer management + execution pipeline
│   ├── ScheduleStore.swift          # JSON file persistence + FS watching
│   ├── LogService.swift             # Event logging to files
│   ├── KeychainService.swift        # Keychain token CRUD
│   └── UserColorStore.swift         # Persistent user color assignments
│
├── ViewModels/
│   └── AppViewModel.swift           # Root state: auth, user cache, ownership
│
├── Views/
│   ├── ContentView.swift            # Auth gate
│   ├── LoginView.swift              # Token input + setup instructions
│   ├── MainView.swift               # NavigationSplitView + toolbar
│   ├── SidebarView.swift            # Active/Completed/Failed tabs + list
│   ├── ScheduleRowView.swift        # Row: status dot, name, countdown
│   ├── ScheduleDetailView.swift     # Full detail: header, session, conversation
│   ├── DraftView.swift              # Send/Rewrite/Ignore actions
│   ├── DraftHistoryView.swift       # Previous drafts with send fallback
│   ├── AddScheduleFromLinkView.swift # Create schedule from Slack message link
│   ├── EditScheduleView.swift       # Edit schedule properties
│   ├── IntervalPickerView.swift     # Preset buttons + adaptive slider
│   ├── HistoryView.swift            # Paginated session history window
│   ├── LogViewerView.swift          # Filterable log viewer window with auto-scroll
│   ├── MarkdownView.swift           # Markdown renderer for Claude summaries
│   └── SlackImageView.swift         # Async Slack image downloader + preview
│
└── Utilities/
    ├── Constants.swift              # Paths, keychain IDs, Slack config
    └── Extensions.swift             # Colors, formatters, button styles, formCard
```

---

## Data Models

### Schedule

The central data model. Stored as individual JSON files.

```
Schedule
├── id: UUID                    # Unique identifier, also the filename
├── name: String                # User-defined name
├── type: ScheduleType          # .channel | .thread | .dm | .dmgroup
├── channelId: String           # Slack channel/conversation ID
├── threadTs: String?           # Thread parent timestamp (for .thread type)
├── channelName: String         # Display name
├── prompt: String              # Instructions for Claude
├── intervalSeconds: Int        # Check frequency (1s to 86400s)
├── status: ScheduleStatus      # .active | .completed | .failed
├── createdAt: Date
├── lastRun: Date?              # When the schedule last executed
├── lastMessageTs: String?      # Slack timestamp of last processed message
├── sessions: [Session]         # All Claude analysis sessions
├── pendingMessages: [SlackMessage]  # Owner messages waiting for next Claude session
└── initialMessageCount: Int   # Max messages to include on first fetch (default 5)
```

### Session

One execution of the monitoring pipeline.

```
Session
├── sessionId: UUID
├── timestamp: Date
├── messages: [SlackMessage]    # Messages analyzed in this session
├── summary: String?            # Claude's summary
├── draftReply: String?         # Claude's suggested reply
├── draftHistory: [DraftEntry]  # Previous drafts from rewrites
├── finalAction: FinalAction    # .pending | .sent | .ignored
└── sentMessage: String?        # The actual text that was sent
```

### SlackMessage

```
SlackMessage
├── type: String?
├── user: String?               # Slack user ID
├── text: String?
├── ts: String?                 # Slack timestamp (e.g., "1710384000.123456")
├── threadTs: String?
├── replyCount: Int?
└── files: [SlackFile]?         # Attached files
```

### SlackFile

```
SlackFile
├── id: String
├── name: String?
├── mimetype: String?           # e.g., "image/png"
├── filetype: String?           # e.g., "png"
├── urlPrivateDownload: String? # Full resolution download URL
├── urlPrivate: String?         # View URL (needs auth)
├── thumb360/thumb480/thumb720  # Thumbnail URLs
```

---

## Core Services

### SlackService (actor)

Thread-safe Slack API client using `URLSession`. All methods are async.

**Key methods:**
- `authTest()` → validates token, returns user/team info
- `listConversations()` → paginated fetch of all channels/DMs/groups
- `conversationsHistory(channelId:, oldest:)` → fetch channel messages since timestamp
- `conversationsReplies(channelId:, ts:, oldest:)` → fetch thread replies
- `postMessage(channelId:, text:, threadTs:)` → send message (appends draft signature)
- `conversationsInfo(channelId:)` → get channel details (used for link resolution)
- `usersInfo(userId:)` → get user profile
- `downloadFile(url:, to:)` → download private file with auth header

All requests use `Authorization: Bearer <token>` header. JSON responses decoded with snake_case strategy.

### ClaudeService (enum, static methods)

Invokes Claude Code CLI as a subprocess.

**Methods:**
- `analyze(messages:, prompt:, channelName:, scheduleId:, ownerUserId:, ownerDisplayName:, imagePaths:, userNames:)` → `AnalysisResult`
- `rewrite(messages:, allSummaries:, draftHistory:, originalPrompt:, rewritePrompt:, channelName:, scheduleId:, ownerUserId:, ownerDisplayName:, imagePaths:, userNames:)` → `AnalysisResult`
- `cleanupOutput(for:)` — deletes output directory for a schedule

**How it works (file-based output):**
1. Builds a text prompt with message history, owner context, image references, and user instructions
2. Creates output directory: `~/Library/Application Support/SmartSlack/claude_output/{scheduleId}/`
3. Clears any previous `summary.md` and `draft.txt` from the output directory
4. Instructs Claude to write two files:
   - `summary.md` — markdown-formatted summary of the conversation
   - `draft.txt` — plain text draft reply for Slack
5. Spawns `claude --print --output-format text --allowedTools Write` as a `Process`
6. Writes prompt to stdin, closes stdin
7. Waits for process to exit
8. Reads `summary.md` and `draft.txt` from the output directory
9. Returns `AnalysisResult` with summary, draft, raw prompt, and raw stdout

**Why file-based output:** Previous approach asked Claude to output JSON with summary and draft_reply fields. This broke when markdown summaries contained characters that made JSON parsing unreliable (curly braces, newlines, special characters). Writing to separate files eliminates all parsing issues.

**User name resolution:** Before calling Claude, the `SchedulerEngine` resolves all user IDs to display names:
- Message author IDs are resolved via `SlackService.usersInfo()`
- `<@USERID>` mentions in message text are replaced with `@displayName`
- Resolved names are cached in `AppViewModel.userNameCache` and passed via `userNames` parameter
- This ensures Claude sees human-readable names, not raw Slack user IDs

**Owner context:** When owner info is available, the prompt tells Claude:
- Who the owner is (name + user ID)
- That messages from the owner are their own
- To write in first person as the owner
- Not to repeat/contradict the owner's previous messages

**Important:** Uses `--print` mode (stateless, no conversation history in Claude). The `--allowedTools Write` flag grants Claude the Write tool to create output files. Each call is independent.

### SchedulerEngine (ObservableObject, @MainActor)

Manages the execution lifecycle of all schedules.

**Published state:**
- `countdowns: [UUID: TimeInterval]` — seconds until next execution per schedule
- `runningSchedules: Set<UUID>` — currently executing schedules

**Timer system:**
- Each active schedule gets a 1-second repeating `Timer`
- On each tick, countdown decrements by 1
- When countdown reaches 0, `executeSchedule()` is called
- After execution, countdown resets to `schedule.intervalSeconds`

**Execution pipeline (`executeSchedule`):**
1. Guard: skip if schedule is already running (prevents concurrent execution)
2. Fetch new messages from Slack (uses `conversationsHistory` or `conversationsReplies` depending on schedule type)
3. Filter to only messages newer than `lastMessageTs`
4. On first fetch (`lastMessageTs` is nil), limit to `initialMessageCount` most recent messages
5. If no new messages → update `lastRun`, return
6. If all new messages are from owner → store in `pendingMessages`, advance `lastMessageTs`, return (skip Claude)
7. Merge `pendingMessages` with new messages for full context
8. Download images from messages to temp directory
9. Call `ClaudeService.analyze()` with all messages + image paths
10. Log the prompt sent and response received
11. Create a `Session` with messages, summary, draft
12. Update schedule: set `lastRun`, advance `lastMessageTs`, clear `pendingMessages`, append session
13. On error: mark schedule as `.failed`, stop timer

**Owner message handling:**
- Messages from the token owner are detected by comparing `message.user` to the stored `ownerUserId`
- If ALL new messages are from the owner, Claude is skipped but messages are saved to `pendingMessages`
- `pendingMessages` are included in the next Claude session (merged with new non-owner messages)
- `lastMessageTs` is advanced even for owner-only batches to prevent re-fetching

### ScheduleStore (ObservableObject)

File-based persistence for schedules.

**Storage:** `~/Library/Application Support/SmartSlack/schedules/{uuid}.json`

Each schedule is a separate JSON file. Uses `JSONEncoder.slackEncoder` (snake_case keys, ISO8601 dates, pretty printed).

**File watching:** Uses `DispatchSourceFileSystemObject` on the schedules directory + a 5-second polling timer as fallback. Reloads all schedules when changes detected.

**Custom decoding:** `Schedule.init(from:)` handles backward compatibility — `pendingMessages` defaults to empty array if missing from JSON.

### LogService (ObservableObject)

**Storage:** `~/Library/Application Support/SmartSlack/logs/{scheduleId}.log` (one file per schedule)

Each log file contains compact NDJSON (newline-delimited JSON) entries. Each entry has: id, timestamp, scheduleId, sessionId, level, message. Uses a dedicated compact encoder (no pretty-printing) to ensure one JSON object per line.

**Log levels:** `verbose`, `info`, `warning`, `error` (ordered by severity, `Comparable`)

**Max file size:** 1 MB per log file. When exceeded, the file is truncated to keep the newest half of entries.

**Persistence:** Logs are loaded from disk on init and persist across app restarts. The log viewer loads all logs on appear.

**Cleanup:**
- `clearLogs(for:)` — deletes log file and in-memory entries for one schedule
- `clearAllLogs()` — clears everything
- `deleteLogsForSchedule()` — called when a schedule is deleted (along with `ClaudeService.cleanupOutput`)
- On init, legacy per-session log files (`{scheduleId}_{sessionId}.log`) are deleted and pretty-printed files are migrated to compact NDJSON

Key events logged:
- Schedule start/stop
- Message fetch results (verbose level)
- Owner-only skip decisions
- User name resolution
- Image download counts
- Full Claude prompt and response
- Errors and failures

### UserColorStore (ObservableObject)

Assigns persistent colors to Slack user IDs.

**20 preset colors** ranging across the spectrum (red, orange, amber, lime, green, teal, cyan, blue, indigo, purple, magenta, pink, brown, slate, sage, tan, plum, forest, clay, steel).

**Storage:** `~/Library/Application Support/SmartSlack/user_colors.json` — maps user ID string to color index integer.

**Auto-assignment:** First time a user is encountered, a random color index is assigned. Owner always uses `.primary` color (not from the preset palette).

**Color picker:** Users can click any name in the conversation view to open a 5x4 grid popover of the 20 preset colors. Selecting one persists the change.

---

## View Architecture

### Environment Object Chain

```
SmartSlackApp
  └── ContentView
        └── MainView (or LoginView)
              ├── SidebarView
              └── ScheduleDetailView
                    ├── DraftView
                    └── DraftHistoryView

Injected environment objects:
- AppViewModel (appVM)
- ScheduleStore (scheduleStore)
- SchedulerEngine (schedulerEngine)
- LogService (logService)
- UserColorStore (userColorStore)
```

### Menu Bar (AppDelegate)

- `NSStatusItem` with `variableLength`
- Button displays: SF Symbol + green active count + red failed count
- Uses `NSMutableAttributedString` for colored text
- Combine subscription on `scheduleStore.$schedules` to update badge
- Click behavior: activates app and opens/focuses main window
- `applicationShouldTerminateAfterLastWindowClosed` returns `false`

### Conversation Display (ScheduleDetailView)

Messages from all sessions + pendingMessages are deduplicated by `ts` and sorted newest-first.

**Visual indicators:**
- **"New" highlight:** Blue tint on messages from the latest Claude-processed session (session with summary != nil)
- **"Older" divider:** Orange line between new and historical messages
- **Owner messages:** Gray background, `.primary` name color, "owner" label below name, slightly lighter text
- **Other users:** Background tinted with their assigned color at 8% opacity, name in assigned color
- **Image previews:** Inline below message text, max 240x180px, async loaded with caching

### IntervalPickerView

Adaptive slider system based on preset selection:

| Preset | Step | Range |
|--------|------|-------|
| 5s | 1s | 1s – 29s |
| 30s | 1s | 6s – 59s |
| 1m | 1s | 31s – 299s |
| 5m | 1s | 61s – 599s |
| 10m | 1s | 301s – 1799s |
| 30m | 1s | 601s – 3599s |
| 1h | 1min | 31m – 299m |
| 5h | 1min | 61m – 1440m |

The slider renders asynchronously (100ms delay) to prevent dialog freeze.

### Custom Button Styles

Four styles defined in Extensions.swift:
- **PrimaryButtonStyle** — solid accent color fill, white text, press scale animation
- **SecondaryButtonStyle** — translucent background, thin border, adapts to dark/light mode
- **DestructiveButtonStyle** — soft red tint, red text
- **SmallSecondaryButtonStyle** — compact version for inline contexts

### MarkdownView

Custom view that renders markdown text with proper formatting:
- Parses blocks: headings (H1-H3), bullet lists, numbered lists, paragraphs
- Renders inline markdown (bold, italic, code, links) via `AttributedString(markdown:)`
- Used for displaying Claude's markdown-formatted summaries

### Log Viewer (LogViewerView)

Opens in a separate `NSWindow`. Features:
- **Level filter:** Minimum severity filter (verbose/info/warning/error), defaults to `info`
- **Schedule filter:** Filter by schedule name, shows only schedules with existing logs
- **Auto-scroll toggle:** When enabled, view automatically scrolls to the latest entry as new logs arrive. Manual scrolling disables auto-scroll. Toggle button in toolbar.
- **Clear buttons:** Clear logs for filtered schedule, or clear all
- **Reload button:** Reloads all logs from disk
- Shows timestamp, level, schedule name, and message per entry

### Separate Windows

History and Log Viewer open in separate `NSWindow` instances (created programmatically in MainView) rather than sheets or navigation destinations. Environment objects must be explicitly injected when creating these windows (they don't inherit from the main window hierarchy).

---

## Data Flow Diagrams

### Schedule Execution Flow

```
Timer tick (1s)
  │
  ▼
countdown[id] -= 1
  │
  ├─ countdown > 0 → wait
  │
  └─ countdown <= 0
       │
       ▼
     Fetch messages from Slack
       │
       ├─ First fetch? Limit to initialMessageCount most recent
       │
       ├─ No new messages → update lastRun, reset countdown
       │
       ├─ All from owner → store in pendingMessages, advance lastMessageTs, reset countdown
       │
       └─ Has non-owner messages
            │
            ▼
          Merge pendingMessages + newMessages
            │
            ▼
          Download images to temp dir
            │
            ▼
          Claude.analyze(messages, prompt, images)
            │
            ├─ Success → create Session, clear pendingMessages, reset countdown
            │
            └─ Error → mark schedule as .failed, stop timer
```

### Draft Action Flow

```
User sees draft in ScheduleDetailView
  │
  ├─ Send → SlackService.postMessage() → set finalAction = .sent
  │
  ├─ Ignore → set finalAction = .ignored
  │
  └─ Rewrite → enter feedback text
       │
       ▼
     Claude.rewrite(messages, history, feedback)
       │
       ▼
     Move current draft to draftHistory
     Set new draft from Claude response
```

### Authentication Flow

```
App Launch
  │
  ├─ Token in Keychain?
  │    ├─ Yes → SlackService(token) → authTest() → resolve owner profile → startAllActive()
  │    └─ No → show LoginView
  │
  └─ User enters token
       │
       ▼
     authTest() → success?
       ├─ Yes → save to Keychain → resolve owner profile → show MainView
       └─ No → show error
```

---

## Persistence Details

### JSON Encoding Strategy

All models use `JSONEncoder.slackEncoder` / `JSONDecoder.slackDecoder`:
- Key strategy: `convertToSnakeCase` / `convertFromSnakeCase`
- Date strategy: ISO8601
- Output: pretty printed, sorted keys

### Backward Compatibility

`Schedule.init(from:)` provides a custom decoder that defaults optional fields if missing from JSON:
- `pendingMessages` defaults to `[]`
- `initialMessageCount` defaults to `5`

This ensures old JSON files load without errors.

### File Watching

`ScheduleStore` monitors the schedules directory using:
1. `DispatchSourceFileSystemObject` — kernel-level file system event notification
2. 5-second polling timer — fallback for reliability

Both trigger `loadSchedules()` which re-reads all JSON files from disk.

---

## Key Implementation Notes

### Claude CLI Integration

- Path: `/opt/homebrew/bin/claude`
- Arguments: `["--print", "--output-format", "text", "--allowedTools", "Write"]`
- Input: prompt written to stdin, then stdin closed
- Output: Claude writes `summary.md` and `draft.txt` to `~/Library/Application Support/SmartSlack/claude_output/{scheduleId}/`
- Mode: stateless (`--print`), no conversation history saved
- The `--allowedTools Write` flag grants Claude the Write tool to create output files
- The `--file` flag is NOT used (requires session token). Images are referenced in prompt text only.
- User names are resolved before calling Claude — all `<@USERID>` mentions and message authors are replaced with display names

### Slack API Considerations

- All API calls need `Authorization: Bearer <token>`
- Private file downloads (images) also need the auth header
- Pagination: `conversations.list` uses cursor-based pagination
- Message timestamps (`ts`) are used as cursors for incremental fetching via `oldest` parameter
- DM channels have user IDs instead of names — resolved via `users.info`

### Thread Safety

- `SlackService` is an `actor` — all API calls are thread-safe
- `SchedulerEngine` is `@MainActor` — timer callbacks and state updates on main thread
- Claude subprocess runs on `DispatchQueue.global(qos: .userInitiated)` with `withCheckedContinuation`

### Image Handling

- Images are downloaded to `/tmp/SmartSlack/{sessionId}/` for Claude context
- Thumbnails cached to `/tmp/SmartSlack/thumbs/` for UI display
- `SlackImageView` checks cache before downloading
- Best thumbnail URL selected: 720 > 480 > 360 > original

---

## Adding New Features - Guide

### Adding a new field to Schedule

1. Add the field to `Schedule` struct in `Schedule.swift`
2. Add it to the `init(id:...)` parameter list with a default value
3. Add it to `init(from decoder:)` using `decodeIfPresent` with a fallback default (for backward compatibility)
4. Update any views that need to display/edit the field
5. Update this design doc

### Adding a new Slack API method

1. Add the response type to `SlackModels.swift`
2. Add the method to `SlackService.swift` using `get()` or `post()` helpers
3. The snake_case conversion is automatic via the shared decoder

### Adding a new view

1. Create the SwiftUI file in `Views/`
2. Run `xcodegen generate` to add it to the Xcode project
3. If it needs environment objects, they're already in the hierarchy

### Modifying the Claude prompt

1. Edit `ClaudeService.swift` — `analyze()` for monitoring, `rewrite()` for rewrites
2. The prompt structure: system context → owner context → messages → image references → user instructions → file write instructions
3. Claude is instructed to write `summary.md` (markdown) and `draft.txt` (plain text) to the schedule's output directory
4. Output paths are absolute paths passed in the prompt — Claude uses the Write tool to create them
