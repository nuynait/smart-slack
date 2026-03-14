# SmartSlack

A macOS menu bar app that monitors Slack channels, threads, and DMs on configurable schedules. It uses [Claude Code](https://claude.ai/claude-code) CLI to analyze new messages and draft replies, letting you review, rewrite, or send them directly from the app.

## Features

- **Schedule-based monitoring** - Set up recurring checks on any Slack channel, thread, DM, or group DM with intervals from 5 seconds to 24 hours
- **AI-powered analysis** - Claude reads new messages and generates a summary + draft reply based on your custom prompt
- **Draft workflow** - Review drafts, rewrite with feedback, browse draft history, or ignore
- **Owner awareness** - Recognizes your own messages, skips Claude when only you posted, and drafts in your voice
- **Image support** - Downloads and previews image attachments from Slack messages
- **Two ways to create schedules** - Browse channels or paste a Slack message link to auto-detect the conversation type
- **Persistent color coding** - Each person in conversations gets a unique color, click to customize
- **Menu bar app** - Runs in the background with live badge counts for active and failed schedules
- **Full history** - Searchable, paginated history of all sessions with summaries, drafts, and actions taken
- **Logging** - Detailed logs of every fetch, Claude call, and action for debugging

## Screenshots

*Menu bar with schedule counts, conversation view with color-coded users, draft workflow with send/rewrite/ignore*

## Requirements

- macOS 14.0+
- [Claude Code CLI](https://claude.ai/claude-code) installed at `/opt/homebrew/bin/claude`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for building from source)
- A Slack User OAuth Token (`xoxp-...`)

## Setup

### 1. Clone and build

```bash
git clone https://github.com/nuynait/smart-slack.git
cd smart-slack
xcodegen generate
open SmartSlack.xcodeproj
```

Build and run from Xcode (Cmd+R).

### 2. Create a Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and create a new app
2. Under **OAuth & Permissions**, add these **User Token Scopes**:
   - `channels:history`, `channels:read`
   - `groups:history`, `groups:read`
   - `im:history`, `im:read`
   - `mpim:history`, `mpim:read`
   - `chat:write`
   - `users:read`
   - `search:read`
   - `files:read`
3. Install the app to your workspace
4. Copy the **User OAuth Token** (starts with `xoxp-`)

### 3. Connect

Launch SmartSlack, paste your token, and click **Connect**. The app validates against `auth.test` and stores the token securely in your macOS Keychain.

## Usage

### Creating a Schedule

Click `+` and paste a Slack message URL. The app auto-detects the channel, type, and thread. Just add a name, check interval, and prompt.

### Prompt Tips

The prompt tells Claude how to analyze messages and what kind of reply to draft. Examples:

- *"Summarize any support requests and draft a helpful response"*
- *"Watch for questions directed at me and draft concise answers"*
- *"Monitor for deployment issues and draft an acknowledgment"*

### Working with Drafts

When new messages arrive, Claude generates a summary and draft reply:

- **Send** - Posts the draft to Slack (appends "drafted with Claude Code")
- **Rewrite** - Give Claude feedback and get a new draft
- **Ignore** - Skip this session, wait for the next check

### Schedule Lifecycle

- **Active** - Timer running, checking for new messages
- **Completed** - Manually marked done, timer stopped
- **Failed** - Error occurred (bad API response, Claude failure), can re-activate

## Architecture

See [doc/design.md](doc/design.md) for detailed system design and implementation guide.

```
SmartSlack/
├── SmartSlackApp.swift          # App entry point
├── AppDelegate.swift            # Menu bar status item
├── Models/
│   ├── Schedule.swift           # Schedule, Session, DraftEntry
│   └── SlackModels.swift        # Slack API response types
├── Services/
│   ├── SlackService.swift       # Slack REST API client (actor)
│   ├── ClaudeService.swift      # Claude CLI subprocess
│   ├── SchedulerEngine.swift    # Per-schedule timers + execution
│   ├── ScheduleStore.swift      # JSON file persistence
│   ├── LogService.swift         # Event logging
│   ├── KeychainService.swift    # Secure token storage
│   └── UserColorStore.swift     # User color assignments
├── ViewModels/
│   └── AppViewModel.swift       # Root state manager
├── Views/                       # SwiftUI views
└── Utilities/
    ├── Constants.swift           # Paths, config
    └── Extensions.swift          # Colors, formatters, button styles
```

## Data Storage

All data is stored locally:

| Data | Location |
|------|----------|
| Schedules | `~/Library/Application Support/SmartSlack/schedules/*.json` |
| Logs | `~/Library/Application Support/SmartSlack/logs/*.log` |
| User colors | `~/Library/Application Support/SmartSlack/user_colors.json` |
| Starred channels | `~/Library/Application Support/SmartSlack/starred_channels.json` |
| Slack token | macOS Keychain |

## License

MIT
