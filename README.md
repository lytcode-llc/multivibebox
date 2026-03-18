# Multivibebox

A Docker-based development environment for macOS that runs multiple CLI coding agents simultaneously in tmux panes, with audio notifications when any agent responds. Starts with Claude Code but extensible to any CLI agent (Aider, Codex, etc.).

## Architecture

```
┌─── macOS Host ───────────────────────────────────────────┐
│                                                           │
│  mvb (launcher script)                                    │
│    ├── docker compose up                                  │
│    └── host-watcher.sh (monitors notify/, plays sounds)   │
│                                                           │
│  ┌─── Docker Container ──────────────────────────────┐    │
│  │  tmux session "mvb"                               │    │
│  │  ┌──────────────┬──────────────┐                  │    │
│  │  │ claude       │ agent-2      │                  │    │
│  │  │ (pane 0)     │ (pane 1)     │                  │    │
│  │  ├──────────────┴──────────────┤                  │    │
│  │  │ agent-3 / status (pane 2)   │                  │    │
│  │  └─────────────────────────────┘                  │    │
│  │                                                   │    │
│  │  pane-monitor.sh → writes to /notify              │    │
│  │                                                   │    │
│  │  Volumes:                                         │    │
│  │    /workspace ← bind mount OR named volume        │    │
│  │    /notify   ← bind mount (notification bridge)   │    │
│  │    /config   ← bind mount (API keys, agent defs)  │    │
│  └───────────────────────────────────────────────────┘    │
└───────────────────────────────────────────────────────────┘
```

## Prerequisites

- **macOS** (audio notifications use `afplay`)
- **Docker Desktop** installed and running
- **jq** (`brew install jq`)
- An **Anthropic API key** (for Claude Code)

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/<user>/multivibebox.git
cd multivibebox

# 2. Install (copies mvb to PATH, builds Docker image)
make install

# 3. Add your API key
mvb config
# → Set ANTHROPIC_API_KEY=sk-ant-...

# 4. Start a project with a local folder
mvb start myproject --path ~/Projects/myproject

# 5. (Optional) Open another terminal and attach to a specific agent
mvb attach claude
```

## Usage

### Start a project

```bash
# With a local folder (bind mount — edit in your IDE simultaneously)
mvb start myproject --path ~/Projects/myproject

# Standalone (Docker volume)
mvb start myproject

# Multiple agents
mvb start myproject --path ~/Projects/myproject --agents claude,aider

# Shared mode (all agents in same directory, no worktrees)
mvb start myproject --path ~/Projects/myproject --shared
```

### Other commands

```bash
mvb stop                     # Stop container + host watcher
mvb list                     # List all projects
mvb attach                   # Attach to full tmux session
mvb attach claude            # Attach to a specific agent's pane
mvb merge                    # Interactive merge of agent branches
mvb open claude              # Open agent's worktree in VS Code
mvb open claude src/main.py  # Open a specific file in VS Code
mvb config                   # Edit .env in $EDITOR
mvb destroy myproject        # Remove project and its volume
```

### Agent isolation modes

- **Worktree mode** (default for git repos): Each agent gets its own `git worktree` and branch (`agent/<agent-name>`). Use `mvb merge` to reconcile.
- **Shared mode** (`--shared`): All agents work in the same directory. Good for collaborative workflows.

## Audio Notifications

When an agent produces output, you'll hear a macOS system sound. Each agent can have its own sound. Notifications are debounced (10s cooldown per agent) to avoid noise during streaming responses.

The notification bridge works by:
1. **In-container**: `pane-monitor.sh` polls tmux panes every 2s, detects output changes, writes event files to `/notify/`
2. **On host**: `host-watcher.sh` watches the notify directory and plays sounds via `afplay`

## Adding a Custom Agent

1. Create a config file in `config/agents/`:

```bash
# config/agents/myagent.conf
AGENT_NAME="myagent"
AGENT_CMD="myagent-cli"
AGENT_ARGS="--some-flag"
AGENT_INSTALL="pip3 install myagent-cli"
NOTIFY_SOUND="Ping"
```

2. If the agent needs extra system packages, add them to the Dockerfile's agent install section.

3. Rebuild: `make build`

4. Use it: `mvb start myproject --agents claude,myagent`

### Available macOS sounds

Glass, Ping, Submarine, Tink, Pop, Purr, Hero, Blow, Bottle, Frog, Funk, Morse, Sosumi

## Configuration Reference

Edit `config/.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | — | Required for Claude Code |
| `OPENAI_API_KEY` | — | For OpenAI-based agents |
| `MVB_AGENTS` | `claude` | Comma-separated agent list |
| `MVB_LAYOUT` | `tiled` | tmux layout (tiled, even-horizontal, even-vertical, main-horizontal, main-vertical) |
| `MVB_MAX_PANES` | `6` | Maximum number of agent panes |
| `MVB_NOTIFY_COOLDOWN` | `10` | Seconds between notification sounds per agent |

## Troubleshooting

### Docker not running
```
Error: Docker is not running. Please start Docker Desktop.
```
Open Docker Desktop and wait for it to start.

### No sound on notifications
- Check that `notify/` directory exists and is writable
- Verify the host watcher is running: `ps aux | grep host-watcher`
- Check macOS sound output is not muted

### Container can't find API key
- Make sure `config/.env` exists and has your key set
- Re-run `mvb config` to verify

### tmux session not attaching
- If the container is running but attach fails, try: `docker exec -it mvb-<project> tmux attach-session -t mvb`

## License

MIT
