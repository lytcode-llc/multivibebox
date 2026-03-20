FROM debian:bookworm-slim

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
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user with fixed uid/gid for volume permission consistency
RUN groupadd -g 1001 vibe && useradd -m -s /bin/bash -u 1001 -g 1001 vibe && \
    mkdir -p /workspace /notify /open /config /home/vibe/.claude && \
    chown -R vibe:vibe /workspace /notify /open /config /home/vibe/.claude

# Install Claude Code as vibe user via native installer
# WORKDIR /tmp avoids filesystem scan hang when installing in Docker
USER vibe
WORKDIR /tmp
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/vibe/.local/bin:${PATH}"

# --- Extensible agent install section ---
# Aider (uncomment or add in agent config)
# RUN pip3 install --break-system-packages aider-chat

# Codex (uncomment or add in agent config)
# RUN npm install -g @openai/codex
# --- End agent installs ---

# Copy scripts and config (need root for ownership)
USER root
COPY --chown=vibe:vibe scripts/ /opt/mvb/scripts/
COPY --chown=vibe:vibe config/tmux.conf /opt/mvb/config/tmux.conf
COPY --chown=vibe:vibe config/agents/ /opt/mvb/config/agents/
RUN chmod +x /opt/mvb/scripts/*.sh && \
    ln -s /opt/mvb/scripts/mvb-open.sh /usr/local/bin/mvb-open

USER vibe
WORKDIR /workspace

ENTRYPOINT ["/opt/mvb/scripts/entrypoint.sh"]
