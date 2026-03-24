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
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20 from NodeSource (Debian bookworm ships Node 18, too old for gemini-cli)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user with fixed uid/gid for volume permission consistency
RUN groupadd -g 1001 vibe && useradd -m -s /bin/bash -u 1001 -g 1001 vibe && \
    mkdir -p /workspace /notify /open /config /home/vibe/.claude /home/vibe/.ssh && \
    chown -R vibe:vibe /workspace /notify /open /config /home/vibe/.claude /home/vibe/.ssh

# Configure npm global prefix to a vibe-owned directory so npm install -g works without sudo
RUN mkdir -p /opt/npm-global/bin \
    && chown -R vibe:vibe /opt/npm-global
ENV NPM_CONFIG_PREFIX=/opt/npm-global
ENV PATH="/opt/npm-global/bin:$PATH"

# Pre-populate SSH known_hosts so git clone doesn't prompt for host verification
RUN ssh-keyscan -t ed25519,rsa github.com gitlab.com bitbucket.org ssh.dev.azure.com vs-ssh.visualstudio.com >> /home/vibe/.ssh/known_hosts 2>/dev/null && \
    chown vibe:vibe /home/vibe/.ssh/known_hosts

# Install Claude Code as vibe user via native installer
# WORKDIR /tmp avoids filesystem scan hang when installing in Docker
USER vibe
WORKDIR /tmp
RUN curl -fsSL https://claude.ai/install.sh | bash

# --- Extensible agent install section ---
# Aider (uncomment or add in agent config)
# RUN pip3 install --break-system-packages aider-chat

# Codex (uncomment or add in agent config)
# RUN npm install -g @openai/codex
# --- End agent installs ---

# Copy agent binaries to system path so they survive home volume mount
# Save home skeleton for first-run initialization
USER root
RUN cp /home/vibe/.local/bin/claude /usr/local/bin/claude && \
    mkdir -p /opt/mvb/skel && \
    cp -a /home/vibe/. /opt/mvb/skel/
ENV PATH="/home/vibe/.local/bin:/usr/local/bin:${PATH}"

# Copy scripts and config
COPY --chown=vibe:vibe scripts/ /opt/mvb/scripts/
COPY --chown=vibe:vibe config/tmux.conf /opt/mvb/config/tmux.conf
COPY --chown=vibe:vibe config/agents/ /opt/mvb/config/agents/
RUN chmod +x /opt/mvb/scripts/*.sh && \
    ln -s /opt/mvb/scripts/mvb-open.sh /usr/local/bin/mvb-open

USER vibe
WORKDIR /workspace

ENTRYPOINT ["/opt/mvb/scripts/entrypoint.sh"]
