# Familiar

A native macOS desktop app that wraps the Claude Code CLI in a beautiful SwiftUI interface.

Familiar brings Claude directly to your Mac with a seamless, native experience — complete with real-time streaming, tool visualization, session management, and a powerful memory system for context persistence.

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

### Context & Memory
- **Seed file system** — Inject your identity, preferences, and context into every session via customizable system prompts
- **Memory daemon** — Automatic session notes and rolling episodic memory powered by Claude Haiku
- **Transcript logging** — Lean, searchable markdown transcripts of every session for future reference

## Requirements

- macOS 15.0 or later
- Claude Code CLI installed: `npm install -g @anthropic-ai/claude-code`
- Anthropic Max subscription (or Claude API access)
- Xcode 16 or later (to build from source)

## Getting Started

### Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/deflating/familiar.git
   cd familiar
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

Familiar stores configuration and session data in `~/.familiar/`. Key directories:

- **seeds/** — System prompt seed files for context injection
- **sessions/** — Session data and transcripts
- **memory/** — Episodic memory and notes from the memory daemon

## Project Status

Familiar is under active development. Features and APIs may change. Report issues and suggestions on GitHub.

## License

Built by Matt Kennelly (@deflating on GitHub).
