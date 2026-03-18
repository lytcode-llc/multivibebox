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

# Install mvb to PATH
if [ -w "$INSTALL_DIR" ]; then
    cp "$REPO_DIR/mvb" "$INSTALL_DIR/mvb"
    chmod +x "$INSTALL_DIR/mvb"
else
    echo -e "${YELLOW}Need sudo to install to $INSTALL_DIR${NC}"
    sudo cp "$REPO_DIR/mvb" "$INSTALL_DIR/mvb"
    sudo chmod +x "$INSTALL_DIR/mvb"
fi
echo -e "  ${GREEN}✓${NC} Installed mvb to $INSTALL_DIR/mvb"

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
docker compose build

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit config/.env to add your ANTHROPIC_API_KEY"
echo "  2. Run: mvb start myproject --path ~/Projects/myproject"
