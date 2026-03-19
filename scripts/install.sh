#!/bin/bash
# Installer for multivibebox
set -e

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${MVB_INSTALL_DIR:-/usr/local/bin}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Installing multivibebox...${NC}"

# Check dependencies
for cmd in docker jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}Error: $cmd is required but not installed.${NC}"
        exit 1
    fi
done

# Check Docker is running
if ! docker info &>/dev/null; then
    echo -e "${RED}Error: Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

# Install mvb to PATH via symlink (stays in sync with repo)
install_symlink() {
    local target="$1"
    if [ -w "$(dirname "$target")" ]; then
        ln -sf "$REPO_DIR/mvb" "$target"
    else
        echo -e "${YELLOW}Need sudo to symlink to $target${NC}"
        sudo ln -sf "$REPO_DIR/mvb" "$target"
    fi
    echo -e "  ${GREEN}✓${NC} Linked mvb → $target"
}

if [ -n "$MVB_INSTALL_DIR" ]; then
    # User explicitly chose an install dir
    install_symlink "$INSTALL_DIR/mvb"
elif [ -w "$INSTALL_DIR" ] || sudo -n true 2>/dev/null; then
    install_symlink "$INSTALL_DIR/mvb"
else
    # Fall back to ~/.local/bin (no sudo needed)
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
    install_symlink "$INSTALL_DIR/mvb"
    # Check if ~/.local/bin is in PATH
    if ! echo "$PATH" | tr ':' '\n' | grep -q "^$INSTALL_DIR$"; then
        echo -e "  ${YELLOW}→ Add this to your shell profile (~/.zshrc or ~/.bashrc):${NC}"
        echo -e "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo -e "  ${YELLOW}  Then restart your shell or run: source ~/.zshrc${NC}"
    fi
fi

# Create user config directory
mkdir -p "$HOME/.mvb"
echo "$REPO_DIR" > "$HOME/.mvb/.repo-path"
echo -e "  ${GREEN}✓${NC} Created ~/.mvb/"

# Copy example config if no config exists
if [ ! -f "$REPO_DIR/config/.env" ]; then
    cp "$REPO_DIR/config/.env.example" "$REPO_DIR/config/.env"
    echo -e "  ${GREEN}✓${NC} Created config/.env from template"
    echo -e "  ${YELLOW}→ Edit config/.env to add your API keys${NC}"
fi

# Create notify directory
mkdir -p "$REPO_DIR/notify"

# Build Docker image
echo ""
echo -e "${GREEN}Building Docker image...${NC}"
cd "$REPO_DIR"
MVB_WORKSPACE_VOLUME=mvb-default docker compose build

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit config/.env to add your ANTHROPIC_API_KEY"
echo "  2. Run: mvb start myproject --path ~/Projects/myproject"
