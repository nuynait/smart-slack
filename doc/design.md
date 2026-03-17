# SmartSlack - System Design Document

This document describes the architecture, data flow, and implementation details of SmartSlack. It is intended as a reference for developers (or AI coding assistants) working on the codebase.

---

## Overview

SmartSlack is a macOS menu bar application that:
1. Monitors Slack conversations on user-defined schedules
2. Feeds new messages to Claude Code CLI for analysis
3. Presents AI-generated summaries and draft replies
4. Lets the user send, rewrite, ignore, or skip drafts (Claude can auto-skip based on user-defined filters)

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
│   ├── ScheduleStore.swift          # JSON file persistence + FS watching + migration
│   ├── MemoryStore.swift            # Per-schedule memory.md persistence
│   ├── LogService.swift             # Event logging to files
│   ├── KeychainService.swift        # Keychain token CRUD
│   ├── UserColorStore.swift         # Persistent user color assignments
│   ├── NotificationService.swift    # macOS notifications + force popup management
│   ├── PromptStore.swift            # Prompt history, saved prompts, tag generation
│   └── KeyboardNavigationState.swift # Centralized keyboard navigation state
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
│   ├── ScheduleDetailView.swift     # Full detail: header (with filter/memory badges), session (with memory report), conversation; shows DraftView for pending/skipped
│   ├── DraftView.swift              # Send/Edit & Send/Rewrite/Ignore buttons; auto-send countdown (observes SchedulerEngine); skipped view with Generate Draft
│   ├── EditSendOverlay.swift        # Overlay dialog: edit draft text before sending
│   ├── RewriteOverlay.swift         # Overlay dialog: rewrite draft via Claude with instructions
│   ├── SendTargetOverlay.swift      # Overlay: choose send to channel or reply in thread
│   ├── ImagePreviewOverlay.swift    # Full-size image viewer with h/l navigation
│   ├── DraftHistoryView.swift       # Previous drafts with send fallback
│   ├── AddScheduleFromLinkView.swift # Create schedule from Slack message link (supports pre-filled initialLink); includes "When Skipped" notification picker
│   ├── EditScheduleView.swift       # Edit schedule properties; includes "When Skipped" notification picker
│   ├── IntervalPickerView.swift     # Preset buttons + adaptive slider
│   ├── HistoryView.swift            # Paginated session history window (excludes pending/skipped); shows memory report alongside summary and draft
│   ├── LogViewerView.swift          # Filterable log viewer window with auto-scroll
│   ├── MarkdownView.swift           # Markdown renderer for Claude summaries
│   ├── SlackImageView.swift         # Async Slack image downloader + preview
│   ├── SettingsView.swift           # App settings with notification/prompt config
│   ├── ForcePopupView.swift         # Always-on-top popup for force notification mode
│   ├── PromptManagerView.swift      # Manage prompt history and saved prompts
│   ├── PromptEditorView.swift       # Edit a prompt with auto-tagging
│   ├── PromptPickerView.swift       # Popup to select a saved/history prompt
│   ├── PromptInputView.swift        # Reusable prompt input with picker button
│   └── KeyboardCheatsheetView.swift # Keyboard shortcut cheatsheet overlay
│
└── Utilities/
    ├── Constants.swift              # Paths (per-schedule dirs), keychain IDs, Slack config
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
├── initialMessageCount: Int   # Max messages to include on first fetch (default 5)
├── notificationMode: NotificationMode  # .macosNotification | .forcePopup | .quiet
├── skipNotificationMode: NotificationMode  # .macosNotification | .forcePopup | .quiet (default .quiet)
├── filterSummary: String?     # One-line summary of the prompt's filter criteria (e.g., "Native development only")
├── memorySummary: String?     # One-line summary of what the prompt will memorize (e.g., "Key decisions and action items")
├── autoSend: Bool             # When true, drafts are auto-sent after 10-second countdown
└── signDrafts: Bool           # When true, appends "— drafted with Claude Code" signature to sent messages (default true; enabling autoSend forces this on)
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
├── finalAction: FinalAction    # .pending | .sent | .ignored | .skipped
├── sentMessage: String?        # The actual text that was sent
├── skipReason: String?         # Why Claude decided to skip (when finalAction == .skipped)
└── memoryReport: String?       # Claude's report of memory changes for this session
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
- `postMessage(channelId:, text:, threadTs:, appendSignature:)` → send message (appends "— drafted with Claude Code" signature when `appendSignature` is true, controlled by `schedule.signDrafts`)
- `conversationsInfo(channelId:)` → get channel details (used for link resolution)
- `usersInfo(userId:)` → get user profile
- `downloadFile(url:, to:)` → download private file with auth header

All requests use `Authorization: Bearer <token>` header. JSON responses decoded with snake_case strategy.

### ClaudeService (enum, static methods)

Invokes Claude Code CLI as a subprocess.

**Methods:**
- `analyze(messages:, prompt:, channelName:, scheduleId:, ownerUserId:, ownerDisplayName:, imagePaths:, userNames:)` → `AnalysisResult`
- `rewrite(messages:, allSummaries:, draftHistory:, originalPrompt:, rewritePrompt:, channelName:, scheduleId:, ownerUserId:, ownerDisplayName:, imagePaths:, userNames:)` → `AnalysisResult`
- `unskipRewrite(messages:, allSummaries:, originalPrompt:, channelName:, scheduleId:, ownerUserId:, ownerDisplayName:, imagePaths:, userNames:)` → `AnalysisResult` — generates a draft for a previously skipped session, telling Claude to disregard filter criteria (no user rewrite prompt needed)
- `analyzePromptMemory(prompt:)` → `String?` — analyzes whether a user prompt contains memory instructions (e.g., "remember key decisions", "track PRs"). Returns a one-line summary of what will be memorized, or nil if no memory instructions found. Called alongside `analyzePromptFilter` when prompts change.
- `cleanupOutput(for:)` — deletes output directory for a schedule

**AnalysisResult:**
```
AnalysisResult
├── summary: String?        # Claude's markdown summary
├── draft: String?          # Draft reply text (or skip reason if skipped)
├── skipped: Bool           # Whether Claude decided to skip based on user filters
├── rawPrompt: String       # Full prompt sent to Claude
├── rawResponse: String     # Raw stdout from Claude process
└── memoryReport: String?   # Brief report of memory changes (read from claude_output/memory.md)
```

**How it works (file-based output):**
1. Builds a text prompt with message history, owner context, image references, memory context, and user instructions
2. Creates output directory: `~/Library/Application Support/SmartSlack/schedulers/{scheduleId}/claude_output/`
3. Clears any previous `summary.md`, `draft.txt`, `decision.txt`, and `memory.md` from the output directory
4. Instructs Claude to write three files (plus an optional fourth):
   - `summary.md` — markdown-formatted summary of the conversation
   - `draft.txt` — plain text draft reply for Slack (contains skip reason if skipped)
   - `decision.txt` — either "respond" or "skip", based on whether the conversation matches the user's instruction filters
   - `memory.md` (optional) — brief report of memory changes, only written if the prompt has memory instructions
5. Spawns `claude --print --output-format text --allowedTools Write,Read` as a `Process`
6. Writes prompt to stdin, closes stdin
7. Waits for process to exit
8. Reads `summary.md`, `draft.txt`, `decision.txt`, and optionally `memory.md` from the output directory
9. Sets `skipped` flag based on `decision.txt` content (true if "skip")
10. Returns `AnalysisResult` with summary, draft, skipped flag, memory report, raw prompt, and raw stdout

**Memory management:** Memory is Claude-managed, not user-editable. All three methods (`analyze`, `rewrite`, `unskipRewrite`) derive the memory file path from `scheduleId` internally (no `memory:` parameter). Each prompt includes:
- A `PERSISTENT MEMORY` reference pointing Claude to `schedulers/{uuid}/memory.md` (if the file exists) so it can read context from previous sessions
- A `MEMORY MANAGEMENT` section instructing Claude to: (1) read the existing memory file if present, (2) create/update the memory file if the user's prompt asks for memorization, (3) write a brief report of changes to `claude_output/memory.md`
- If the prompt does NOT contain memory instructions, Claude leaves both files untouched

The user's prompt controls what gets memorized (e.g., "remember key decisions", "track PRs reviewed"). Claude decides what to persist based on those instructions.

**Skip decision:** The `analyze` prompt instructs Claude to evaluate whether the conversation requires the owner's attention based on the user's prompt/filter criteria. Claude writes "respond" or "skip" to `decision.txt`. If skipped, `draft.txt` contains the reason for skipping. The `rewrite` method always writes "respond" to `decision.txt` (rewrites are never skipped). The `unskipRewrite` method explicitly tells Claude to disregard any filter criteria and generate a draft.

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

**Important:** Uses `--print` mode (stateless, no conversation history in Claude). The `--allowedTools Write,Read` flag grants Claude the Write tool to create output files and the Read tool to read memory files from previous sessions. Each call is independent.

### SchedulerEngine (ObservableObject, @MainActor)

Manages the execution lifecycle of all schedules.

**Published state:**
- `countdowns: [UUID: TimeInterval]` — seconds until next execution per schedule
- `runningSchedules: Set<UUID>` — currently executing schedules
- `autoSendCountdowns: [UUID: Int]` — seconds until auto-send per schedule (observed by DraftView + ForcePopupView)
- `backgroundTasks: [UUID: BackgroundTaskInfo]` — schedules with Claude processing in background (rewrite or active reply)
- `skippedTicks: Set<UUID>` — schedules that skipped ticks while a draft was pending; triggers catch-up on draft resolution

**Timer system:**
- Each active schedule gets a 1-second repeating `Timer`
- On each tick, countdown decrements by 1
- When countdown reaches 0, `executeSchedule()` is called
- After execution, countdown resets to `schedule.intervalSeconds`

**Execution pipeline (`executeSchedule`):**
1. Guard: skip if schedule is already running (prevents concurrent execution)
2. **Skip-tick guard**: if the latest session has `finalAction == .pending` or a background task is running, mark `skippedTicks` and return immediately — don't fetch messages, don't advance `lastMessageTs`
3. Fetch new messages from Slack (uses `conversationsHistory` or `conversationsReplies` depending on schedule type)
4. Filter to only messages newer than `lastMessageTs`
5. On first fetch (`lastMessageTs` is nil), limit to `initialMessageCount` most recent messages
6. If no new messages → update `lastRun`, return
7. If all new messages are from owner → create `.skipped` session, advance `lastMessageTs`, return (skip Claude)
8. Merge `pendingMessages` with new messages for full context
9. Download images from messages to temp directory
10. Call `ClaudeService.analyze()` with all messages + image paths
11. Log the prompt sent and response received
12. If `result.skipped`: create `Session` with `.skipped` finalAction, nil draftReply, and `skipReason` from draft text; notify via `skipNotificationMode`
13. Otherwise: create a `Session` with messages, summary, draft, `.pending` finalAction
14. Update schedule: set `lastRun`, advance `lastMessageTs`, clear `pendingMessages`, append session
15. On error: mark schedule as `.failed`, stop timer

**Skip-tick mechanism:**
- When a draft is pending or a background task is running, ticks are skipped entirely (no Slack API calls, no `lastMessageTs` advancement)
- `skippedTicks: Set<UUID>` tracks which schedules had skipped ticks
- When the user resolves a draft (send/ignore/auto-send), `onDraftResolved(for:)` checks if ticks were skipped and immediately triggers a catch-up execution
- Since `lastMessageTs` was never advanced during skips, the catch-up execution naturally fetches ALL messages since the last successful run — no messages are missed
- Visual indicator shows "New messages waiting" in ScheduleDetailView and ForcePopupView when ticks are skipped

**Owner message handling:**
- Messages from the token owner are detected by comparing `message.user` to the stored `ownerUserId`
- If ALL new messages are from the owner, Claude is skipped but messages are saved to `pendingMessages`
- `pendingMessages` are included in the next Claude session (merged with new non-owner messages)
- `lastMessageTs` is advanced even for owner-only batches to prevent re-fetching

### ScheduleStore (ObservableObject)

File-based persistence for schedules.

**Storage:** `~/Library/Application Support/SmartSlack/schedulers/{uuid}/schedule.json`

Each schedule lives in its own directory alongside its Claude output and memory file:
```
schedulers/{uuid}/
├── schedule.json      # Schedule data
├── memory.md          # Per-schedule persistent context (Claude-managed, optional)
└── claude_output/     # Claude's output files (summary.md, draft.txt, decision.txt, memory.md)
```

Uses `JSONEncoder.slackEncoder` (snake_case keys, ISO8601 dates, pretty printed).

**Migration:** `migrateIfNeeded()` runs on init to move data from the old flat layout (`schedules/{uuid}.json` + `claude_output/{uuid}/`) to the new per-schedule directory structure. This happens automatically on first launch after the update.

**Deletion:** `deleteSchedule` removes the entire scheduler directory (`schedulers/{uuid}/`), which includes the schedule JSON, memory file, and Claude output in one operation.

**File watching:** Uses `DispatchSourceFileSystemObject` on the schedulers directory + a 5-second polling timer as fallback. Reloads all schedules when changes detected.

**Custom decoding:** `Schedule.init(from:)` handles backward compatibility — `pendingMessages` defaults to empty array if missing from JSON.

### MemoryStore (enum, static methods)

Per-schedule persistent context stored as plain markdown files. Follows the same pattern as `ClaudeService` (enum with static methods, no instance state).

**Storage:** `~/Library/Application Support/SmartSlack/schedulers/{uuid}/memory.md`

**Methods:**
- `read(for:)` → `String?` — reads memory.md for a schedule, returns nil if file doesn't exist
- `write(_:for:)` — writes text to memory.md (plain text, no JSON encoding)
- `delete(for:)` — removes memory.md for a schedule

**Note:** MemoryStore exists for potential future use but is not actively called by any views. Memory files are read and written directly by Claude via the Read and Write tools during analysis. The memory file path is derived from `Constants.memoryFile(for:)` and passed to Claude in the prompt.

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

### NotificationService (ObservableObject, @MainActor)

Manages notification delivery based on each schedule's `notificationMode`.

**Three modes:**
- **macosNotification** — Sends a `UNNotificationRequest` with schedule name as title and summary preview as body. Clicking the notification navigates to the schedule via `selectedScheduleIdFromNotification`.
- **forcePopup** — Sets `forcePopupScheduleId` which AppDelegate observes to present an always-on-top `NSPanel`. The panel cannot be closed via the close button (only via Send or Ignore). Plays a "Glass" system sound on appearance.
- **quiet** — No notification. Drafts are only visible via the sidebar indicator.

**Permission management:**
- `checkPermission()` queries `UNUserNotificationCenter` authorization status
- `requestPermission()` requests authorization with `.alert`, `.sound`, `.badge` options
- `openSystemPreferences()` deep-links to System Settings > Notifications

**Delegate methods:**
- `willPresent` returns `[.banner, .sound]` so notifications appear even when the app is frontmost
- `didReceive` extracts `scheduleId` from notification `userInfo`, sets `selectedScheduleIdFromNotification`, and activates the app

**Skipped session notifications:** `notifySkippedSession(schedule:session:)` uses `schedule.skipNotificationMode` (defaults to `.quiet`) instead of `schedule.notificationMode` to decide how to notify for skipped sessions. This allows users to configure skip notifications independently from regular draft notifications.

**Sidebar indicator:** `Schedule.hasUnresolvedDraft` checks if any session has `.pending` finalAction with a non-nil summary. This is displayed in `ScheduleRowView` regardless of notification mode. Skipped sessions use the schedule's `skipNotificationMode` (defaults to quiet).

**Menu bar badge:** AppDelegate shows an orange count of schedules with unresolved drafts alongside the existing green (active) and red (failed) counts.

### PromptStore (ObservableObject, @MainActor)

Manages prompt history, saved (starred) prompts, and auto-tagging via Claude.

**Models:**
- `PromptTag`: id, name, colorIndex (indexes into `UserColorStore.presetColors`)
- `SavedPrompt`: id, text, tags, isStarred, createdAt, updatedAt

**History vs Saved:**
- History prompts (unstarred) are limited to `maxHistoryCount` (configurable in settings, default 10). Oldest are trimmed on overflow.
- Starred prompts are permanent and do not count toward the limit.

**Auto-tagging:** When a prompt is created or edited, `ClaudeService.generateTags()` is called asynchronously. Claude receives the prompt text and all existing tags to maximize reuse. Returns 1-4 lowercase tags. Tags get random colors from the `UserColorStore.presetColors` palette.

**Storage:** `~/Library/Application Support/SmartSlack/prompts.json` for prompts, `prompt_settings.json` for settings.

**Integration points:**
- `PromptInputView` replaces raw TextEditor in `AddScheduleFromLinkView` and `EditScheduleView` — shows a "Use Saved" button to open `PromptPickerView`
- `ScheduleDetailView` header has a change-prompt button that opens `PromptPickerView`
- `SettingsView` has a "Manage Prompts" button opening `PromptManagerView` and configurable history limit
- Tags display uses `FlowLayout` (custom Layout) with colored capsule pills

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
- NotificationService (notificationService)
- PromptStore (promptStore)
- UserColorStore (userColorStore)
- KeyboardNavigationState (keyboardNav)
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

**Memory indicators:**
- **Header badge:** Purple "Memory: ..." badge in ScheduleDetailView header (similar to the orange filter badge), showing `schedule.memorySummary` — a one-line description of what the prompt will memorize
- **Session memory report:** "Memory Updated" section displayed after the summary in each session (purple background), showing `session.memoryReport` — Claude's brief report of what was saved/updated
- **History view:** Memory report shown alongside summary and draft in HistoryView

Memory is Claude-managed: there is no user-editable TextEditor for memory. The user controls memorization through prompt instructions (e.g., "remember key decisions"), and `ClaudeService.analyzePromptMemory(prompt:)` detects these instructions to populate the purple badge. Called alongside `analyzePromptFilter` on prompt changes (in `AppViewModel`, `EditScheduleView`, `AddScheduleFromLinkView`, and `MainView` prompt picker).

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

History, Log Viewer, and Settings open in separate `NSWindow` instances (created programmatically in MainView) rather than sheets or navigation destinations. Environment objects must be explicitly injected when creating these windows (they don't inherit from the main window hierarchy).

The Force Popup uses an `NSPanel` with `level = .floating` managed by AppDelegate. It observes `notificationService.forcePopupScheduleId` via Combine and cannot be dismissed via the close button (`windowShouldClose` returns `false`). Only Send or Ignore actions dismiss it by setting `forcePopupScheduleId = nil`.

### Keyboard Navigation

Vim-style keyboard navigation is implemented via `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed in AppDelegate. This intercepts all key-down events app-wide before they reach responders.

**Architecture:**
- `KeyboardNavigationState` (ObservableObject) acts as a command bus between the NSEvent handler and SwiftUI views
- The handler checks `NSApp.keyWindow?.firstResponder is NSTextView` to skip when a text field/editor is active
- Only bare keys are handled (no Cmd/Ctrl/Option modifiers, Shift allowed for `?`)
- Force popup panel key events are passed through unhandled

**Global shortcuts (when not in a text field):**
| Key | Action |
|-----|--------|
| `?` | Toggle keyboard cheatsheet overlay |
| `j` / `k` | Move down/up in schedule list |
| `h` / `l` | Cycle sidebar tabs left/right (wraps around) |
| `p` | Open prompt picker as sheet |
| `r` | Generate draft for skipped session (triggers unskip rewrite) |
| `Esc` | Dismiss cheatsheet |

**Prompt picker shortcuts (when prompt picker is open):**
| Key | Action |
|-----|--------|
| `j` / `k` | Move down/up in prompt list |
| `h` / `l` | Cycle tabs left/right (wraps around) |
| `Enter` | Select highlighted prompt |
| `e` | Edit highlighted prompt |
| `Esc` | Dismiss prompt picker |

Views respond to navigation signals via `.onChange` modifiers that observe the published properties on `KeyboardNavigationState`, perform the action, then nil out the property.

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
            ├─ Success + decision "respond" → create Session (.pending), notify, clear pendingMessages, reset countdown
            │
            ├─ Success + decision "skip" → create Session (.skipped, skipReason), notify via skipNotificationMode, clear pendingMessages, reset countdown
            │
            └─ Error → mark schedule as .failed, stop timer
```

### Draft Action Flow

```
User sees draft in ScheduleDetailView (DraftView buttons)
  │
  ├─ Send / Edit & Send
  │    ├─ Thread schedule → send directly to thread
  │    └─ Non-thread schedule → SendTargetOverlay
  │         ├─ "Send to #channel" → postMessage(threadTs: nil)
  │         └─ "Reply in thread" → pick message → postMessage(threadTs: msg.ts)
  │
  ├─ Edit & Send → opens EditSendOverlay (overlay dialog)
  │    └─ User edits draft text → Send (same target flow as above)
  │
  ├─ Rewrite → opens RewriteOverlay (overlay dialog)
  │    └─ User enters rewrite instructions → Claude.rewrite()
  │         → Move current draft to draftHistory
  │         → Set new draft from Claude response
  │
  ├─ Ignore → set finalAction = .ignored
  │
  └─ (Skipped session) → DraftView shows skip reason + "Generate Draft" button
       └─ Generate Draft → Claude.unskipRewrite()
            → Disregards filter criteria, generates draft
            → Session transitions from .skipped to .pending with new draft
```

### Auto-Send Flow

When `schedule.autoSend == true`, DraftView and ForcePopupView replace action buttons with a 10-second countdown.

**Timer is centralized in `SchedulerEngine`** to prevent duplicate sends when both DraftView and ForcePopupView are visible simultaneously. Both views observe `schedulerEngine.autoSendCountdowns[schedule.id]` (a `@Published` dictionary) instead of managing their own timers.

```
New session created with .pending finalAction + draftReply
  │
  ├─ autoSend OFF → show normal buttons (Send/Edit & Send/Rewrite/Ignore)
  │
  └─ autoSend ON → SchedulerEngine.startAutoSend(for: scheduleId)
       │                 └─ sets autoSendCountdowns[id] = 10, starts single Timer
       │
       ├─ Countdown reaches 0 → SchedulerEngine.performAutoSend(for:)
       │    ├─ Thread schedule → postMessage(threadTs: schedule.threadTs)
       │    └─ Non-thread schedule → postMessage(threadTs: nil) [sends to channel]
       │    → finalAction = .sent, sentMessage = draft
       │    → Dismisses force popup if visible (notificationService.forcePopupScheduleId = nil)
       │
       ├─ User toggles autoSend OFF → SchedulerEngine.cancelAutoSend(for:)
       │    → Cancel timer, remove countdown entry, show normal action buttons
       │
       └─ User clicks "Send Now" in popup → SchedulerEngine.cancelAutoSend + manual send
```

**Key behaviors:**
- Toggle persists on the Schedule model (survives app restart)
- Keyboard shortcuts `e`/`r`/`i` are suppressed when autoSend is active
- Both DraftView and ForcePopupView observe the same centralized countdown (no duplicate timers)
- SchedulerEngine auto-starts countdown after `executeSchedule()` if `schedule.autoSend && !result.skipped`
- When views appear, they only start countdown if one isn't already running (avoids resetting mid-countdown)
- Auto-send targets the channel directly (no SendTargetOverlay) for non-thread schedules
- Only applies to `.pending` sessions with a non-nil draftReply; skipped sessions are unaffected

### Background Processing Flow

Both RewriteOverlay and ActiveReplyView show a "Run in Background" button while Claude is processing. When clicked:

1. The overlay transfers the work to `SchedulerEngine.runRewriteInBackground()` or `runActiveReplyInBackground()`
2. The overlay dismisses immediately
3. `SchedulerEngine.backgroundTasks[scheduleId]` tracks the in-progress task
4. ScheduleDetailView shows a purple progress indicator near the draft area
5. When Claude finishes, the schedule is updated and the user is notified using the schedule's configured notification mode
6. `backgroundTasks` entry is removed

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
- `notificationMode` defaults to `.macosNotification`
- `skipNotificationMode` defaults to `.quiet`
- `memorySummary` defaults to `nil` if missing from JSON

`Session.init(from:)` also handles backward compatibility:
- `skipReason` defaults to `nil` if missing from JSON
- `memoryReport` defaults to `nil` if missing from JSON

This ensures old JSON files load without errors.

### Storage Layout

```
~/Library/Application Support/SmartSlack/
├── schedulers/
│   └── {uuid}/
│       ├── schedule.json      # Schedule data (JSON)
│       ├── memory.md          # Per-schedule persistent context (plain text)
│       └── claude_output/     # Claude's output files
│           ├── summary.md
│           ├── draft.txt
│           ├── decision.txt
│           └── memory.md      # Memory change report (optional, only if prompt has memory instructions)
├── logs/
│   └── {scheduleId}.log       # Per-schedule log files (NDJSON)
├── prompts.json               # Prompt history and saved prompts
├── prompt_settings.json       # Prompt store settings
└── user_colors.json           # User color assignments
```

**Legacy layout (auto-migrated):**
- `schedules/{uuid}.json` → `schedulers/{uuid}/schedule.json`
- `claude_output/{uuid}/` → `schedulers/{uuid}/claude_output/`
- Migration runs automatically via `ScheduleStore.migrateIfNeeded()` on first launch

### File Watching

`ScheduleStore` monitors the schedulers directory using:
1. `DispatchSourceFileSystemObject` — kernel-level file system event notification
2. 5-second polling timer — fallback for reliability

Both trigger `loadSchedules()` which re-reads all schedule.json files from each scheduler subdirectory.

---

## Key Implementation Notes

### Claude CLI Integration

- Path: `/opt/homebrew/bin/claude`
- Arguments: `["--print", "--output-format", "text", "--allowedTools", "Write,Read"]`
- Input: prompt written to stdin, then stdin closed
- Output: Claude writes `summary.md`, `draft.txt`, `decision.txt`, and optionally `memory.md` to `~/Library/Application Support/SmartSlack/schedulers/{scheduleId}/claude_output/`
- Mode: stateless (`--print`), no conversation history saved
- The `--allowedTools Write,Read` flag grants Claude the Write tool (to create output files) and the Read tool (to read the memory file from previous sessions)
- The `--file` flag is NOT used (requires session token). Images are referenced in prompt text only.
- User names are resolved before calling Claude — all `<@USERID>` mentions and message authors are replaced with display names

### Monitor Thread from Conversation

For non-thread schedules (channel, DM, group DM), each message in the conversation view shows a "Monitor Thread" button. Clicking it:

1. Constructs a Slack message link using `AppViewModel.slackMessageLink(channelId:messageTs:)` — requires `slackTeamUrl` from `auth.test`
2. Opens `AddScheduleFromLinkView` with the link pre-filled via `initialLink` parameter
3. Auto-resolves the link on appear, detecting it as a thread schedule
4. User configures name, interval, prompt, and creates the thread schedule

Link format: `https://{workspace}.slack.com/archives/{channelId}/p{tsWithoutDot}`

### Slack API Considerations

- All API calls need `Authorization: Bearer <token>`
- Private file downloads (images) also need the auth header
- Pagination: `conversations.list` uses cursor-based pagination
- Message timestamps (`ts`) are used as cursors for incremental fetching via `oldest` parameter
- DM channels have user IDs instead of names — resolved via `users.info`
- Workspace URL (`slackTeamUrl`) stored from `auth.test` response for constructing message links

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

1. Edit `ClaudeService.swift` — `analyze()` for monitoring, `rewrite()` for rewrites, `unskipRewrite()` for generating drafts on skipped sessions
2. The prompt structure: system context → owner context → persistent memory reference → messages → image references → user instructions → file write instructions → memory management instructions
3. Claude is instructed to write `summary.md` (markdown), `draft.txt` (plain text), `decision.txt` ("respond" or "skip"), and optionally `memory.md` (memory change report) to the schedule's output directory
4. Output paths are absolute paths passed in the prompt — Claude uses the Write tool to create them
5. The `analyze` prompt includes skip logic: Claude evaluates user filter criteria and writes "skip" to `decision.txt` if the conversation doesn't need attention; `draft.txt` then contains the skip reason
6. The `rewrite` prompt always writes "respond" to `decision.txt` (rewrites are never skipped)
7. The `unskipRewrite` prompt tells Claude to disregard filter criteria and generate a draft regardless
