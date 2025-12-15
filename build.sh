#!/bin/bash
set -euo pipefail

# Get architecture from argument (default: x86_64)
ARCH=${1:-x86_64}

echo "Building TreeSitter parsers for architecture: $ARCH"

# Use archive.debian.org for Debian Stretch
echo 'deb http://archive.debian.org/debian stretch main' > /etc/apt/sources.list
echo 'deb http://archive.debian.org/debian-security stretch/updates main' >> /etc/apt/sources.list
apt-get update -y
apt-get install -y build-essential git curl wget ca-certificates coreutils

# Clone nvim-treesitter directly to pack/start (no packer needed)
mkdir -p /root/.local/share/nvim/site/pack/treesitter/start
# Now the default branch of nvim-treesitter is "main", but currently this script is not compatible with latest one. So we still use backward-compatible "master" branch.
git clone --depth 1 --branch master https://github.com/nvim-treesitter/nvim-treesitter /root/.local/share/nvim/site/pack/treesitter/start/nvim-treesitter

# Download and extract Neovim binary from statiolake/neovim-binaries
LATEST_RELEASE=$(curl -s https://api.github.com/repos/statiolake/neovim-binaries/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": "\([^"]*\)".*/\1/')
echo "Downloading Neovim $LATEST_RELEASE for $ARCH"

if ! wget -O nvim.tar.gz "https://github.com/statiolake/neovim-binaries/releases/download/${LATEST_RELEASE}/nvim-linux-$ARCH.tar.gz"; then
  echo "Failed to download Neovim binary"
  exit 1
fi

# Extract Neovim
if ! tar -xzf nvim.tar.gz; then
  echo "Failed to extract Neovim"
  exit 1
fi

# Find the actual directory name (might not match exactly)
NVIM_DIR=$(find . -maxdepth 1 -name 'nvim-linux*' -type d | head -1)
if [ -z "$NVIM_DIR" ]; then
  echo "Neovim directory not found after extraction"
  ls -la
  exit 1
fi

export PATH="$(pwd)/$NVIM_DIR/bin:$PATH"

# Verify Neovim installation
if ! nvim --version; then
  echo "Neovim not working"
  exit 1
fi

# Create init.lua for TreeSitter configuration
cat > /tmp/treesitter-init.lua << 'EOF'
-- TreeSitter configuration for bulk installation
require'nvim-treesitter.configs'.setup {
  ensure_installed = "all",
  sync_install = true,
}
EOF

# Install all parsers using the configuration
echo "Installing all TreeSitter parsers..."
timeout 720 nvim --headless -u /tmp/treesitter-init.lua -c "qa"
exit_code=$?

if [ $exit_code -eq 124 ]; then
  echo "ERROR: TreeSitter installation timed out (12 minutes exceeded)"
  exit 1
elif [ $exit_code -ne 0 ]; then
  echo "ERROR: TreeSitter installation failed with exit code $exit_code"
  exit 1
fi

# Show results
echo '=== TreeSitter parsers installed ==='
PARSER_DIR=/root/.local/share/nvim/site/pack/treesitter/start/nvim-treesitter/parser
if [ -d "$PARSER_DIR" ]; then
  echo "Parser count: $(ls $PARSER_DIR | wc -l)"
  echo "First 10 parsers:"
  ls $PARSER_DIR | head -10
else
  echo 'ERROR: No parsers directory found'
  exit 1
fi

# Copy parsers to output directory for GitHub Actions
if [ -d "/output" ]; then
  echo "Copying parsers to output directory..."
  cp -r "$PARSER_DIR" /output/
fi

echo "Build completed successfully for $ARCH"
