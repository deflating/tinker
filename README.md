# Tinker

A native macOS desktop app that wraps the Claude Code CLI in a beautiful SwiftUI interface.

Tinker brings Claude Code to your Mac as a native app — real-time streaming, tool visualization, session management, and git integration.

## Features

### Core Interface
- **Native SwiftUI app** — Built with Xcode for a smooth, native macOS experience
- **Real-time streaming** — Watch Claude's responses arrive in real-time with full markdown rendering
- **Tool use visualization** — See file edits, searches, and bash commands displayed in a clean, organized UI
- **Agent/subagent task display** — Track multi-step reasoning and agent-based workflows

### Session Management
- **Multiple conversations** — Keep multiple Claude Code sessions open simultaneously
- **Session resumption** — Resume previous conversations and pick up where you left off
- **Customizable settings** — Choose your model, permission mode, and working directory per session

### Git & Development
- **Git branch display** — See your current branch and repository status at a glance
- **Worktree support** — Seamless integration with git worktrees
- **MCP tool support** — Clean, categorized display of Model Context Protocol tools

### Customization
- **System prompt** — Override or append to the system prompt for every session
- **Transcript logging** — Lean, searchable markdown transcripts of every session

## Requirements

- macOS 15.0 or later
- Claude Code CLI installed: `npm install -g @anthropic-ai/claude-code`
- Anthropic Max subscription (or Claude API access)
- Xcode 16 or later (to build from source)

## Getting Started

### Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/deflating/tinker.git
   cd tinker
   ```

2. Open the project in Xcode:
   ```bash
   open Familiar.xcodeproj
   ```

3. Build and run:
   - Press Cmd+R to build and launch the app
   - Or select Product > Run from the menu

The app will launch and guide you through initial setup on first run.

## Configuration

Tinker stores session data in `~/.tinker/`. Settings are accessible via the gear icon or Cmd+,.

## Project Status

Tinker is under active development. Features and APIs may change. Report issues and suggestions on GitHub.

## License

Built by Matt Kennelly (@deflating on GitHub).
