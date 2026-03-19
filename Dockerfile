FROM node:22-bookworm

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    tmux \
    git \
    curl \
    jq \
    vim \
    ripgrep \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# --- Extensible agent install section ---
# Aider (uncomment or add in agent config)
# RUN pip3 install --break-system-packages aider-chat

# Codex (uncomment or add in agent config)
# RUN npm install -g @openai/codex
# --- End agent installs ---

# Create non-root user with Claude Code config directory
RUN useradd -m -s /bin/bash vibe && \
    mkdir -p /workspace /notify /config /home/vibe/.claude && \
    chown -R vibe:vibe /workspace /notify /config /home/vibe/.claude

# Copy scripts and config
COPY --chown=vibe:vibe scripts/ /opt/mvb/scripts/
COPY --chown=vibe:vibe config/tmux.conf /opt/mvb/config/tmux.conf
COPY --chown=vibe:vibe config/agents/ /opt/mvb/config/agents/

RUN chmod +x /opt/mvb/scripts/*.sh

USER vibe
WORKDIR /workspace

ENTRYPOINT ["/opt/mvb/scripts/entrypoint.sh"]
