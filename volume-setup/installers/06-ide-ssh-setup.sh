#!/bin/bash
# IDE and SSH Setup - Persistent runtime state and SSH configuration
# Runs in builder container during volume setup

set -euo pipefail
source $(dirname "$0")/../lib/common.sh

# Provide safe defaults if not set by outer environment
: "${DEPS_ROOT:=/workspace/deps}"
: "${MARKER_DIR:=${DEPS_ROOT}/.installed}"

# Ensure volume is mounted and base deps dir exists
check_volume_mounted

log_section "IDE AND SSH SETUP"

# Check if already installed
if [ -f "$DEPS_ROOT/.installed/ide-ssh-setup" ]; then
    log_info "IDE and SSH setup already completed"
    exit 0
fi

log_info "Creating IDE runtime directories..."

# Create persistent runtime directories for IDEs
mkdir -p "$DEPS_ROOT/runtime/cursor-server"
mkdir -p "$DEPS_ROOT/runtime/cursor-server/data/User"
mkdir -p "$DEPS_ROOT/runtime/cursor-home"
mkdir -p "$DEPS_ROOT/runtime/vscode-server"
mkdir -p "$DEPS_ROOT/runtime/vscode-server/data/User"

# XDG base directories for persistent application state
mkdir -p "$DEPS_ROOT/runtime/xdg/data"
mkdir -p "$DEPS_ROOT/runtime/xdg/config"
mkdir -p "$DEPS_ROOT/runtime/xdg/state"
mkdir -p "$DEPS_ROOT/runtime/xdg/cache"

# Common tool caches
mkdir -p "$DEPS_ROOT/runtime/npm-cache"
mkdir -p "$DEPS_ROOT/runtime/pip-cache"
mkdir -p "$DEPS_ROOT/runtime/yarn-cache"

# Package manager installation directories (for global installs)
mkdir -p "$DEPS_ROOT/runtime/npm-global/bin"
mkdir -p "$DEPS_ROOT/runtime/pip-user/bin"

# Tailscale state directory
mkdir -p "$DEPS_ROOT/runtime/tailscale"

log_success "Runtime directories created"

log_info "Configuring IDE default settings..."

# Create default settings for VSCode and Cursor to use zsh as default terminal
cat > "$DEPS_ROOT/runtime/vscode-server/data/User/settings.json" << 'EOF'
{
  "terminal.integrated.defaultProfile.linux": "zsh",
  "terminal.integrated.profiles.linux": {
    "zsh": {
      "path": "/usr/bin/zsh"
    },
    "bash": {
      "path": "/usr/bin/bash"
    }
  }
}
EOF

# Copy same settings for Cursor
cp "$DEPS_ROOT/runtime/vscode-server/data/User/settings.json" \
   "$DEPS_ROOT/runtime/cursor-server/data/User/settings.json"

log_success "IDE default settings configured"

log_info "Setting up SSH configuration..."

# Enforce secure default permissions for any new files/keys
umask 077

# Create SSH directories in workspace root
mkdir -p /workspace/.ssh
chmod 700 /workspace/.ssh 2>/dev/null || true

# Copy authorized_keys if it exists in the setup directory
if [ -f /opt/volume-setup/authorized_keys ]; then
    log_info "Installing authorized_keys..."
    cp /opt/volume-setup/authorized_keys /workspace/.ssh/authorized_keys
    chmod 600 /workspace/.ssh/authorized_keys
    log_success "SSH keys installed"
elif [ -f /opt/volume-setup/docker/authorized_keys ]; then
    # Also check in docker subdirectory for backwards compatibility
    log_info "Installing authorized_keys from docker directory..."
    cp /opt/volume-setup/docker/authorized_keys /workspace/.ssh/authorized_keys
    chmod 600 /workspace/.ssh/authorized_keys
    log_success "SSH keys installed"
else
    log_warning "No authorized_keys file found - SSH will require manual key setup"
fi

# Generate persistent SSH host keys if they don't exist
if [ ! -f /workspace/.ssh/ssh_host_rsa_key ]; then
    log_info "Generating SSH host keys..."
    ssh-keygen -t rsa -f /workspace/.ssh/ssh_host_rsa_key -N "" -q
    ssh-keygen -t ed25519 -f /workspace/.ssh/ssh_host_ed25519_key -N "" -q
    ssh-keygen -t ecdsa -f /workspace/.ssh/ssh_host_ecdsa_key -N "" -q
    log_success "SSH host keys generated"
else
    log_info "SSH host keys already exist"
fi

# Create environment configuration for IDE paths
# Update env.sh idempotently (replace marked block)
touch "$DEPS_ROOT/env.sh"
sed -i '/# >>> IDE_RUNTIME_ENV/,/# <<< IDE_RUNTIME_ENV/d' "$DEPS_ROOT/env.sh" || true
cat >> "$DEPS_ROOT/env.sh" << 'EOF'
# >>> IDE_RUNTIME_ENV
# IDE and runtime environment
export XDG_DATA_HOME="/workspace/deps/runtime/xdg/data"
export XDG_CONFIG_HOME="/workspace/deps/runtime/xdg/config"
export XDG_STATE_HOME="/workspace/deps/runtime/xdg/state"
export XDG_CACHE_HOME="/workspace/deps/runtime/xdg/cache"
export VSCODE_AGENT_FOLDER="/workspace/deps/runtime/vscode-server"
export CURSOR_AGENT_FOLDER="/workspace/deps/runtime/cursor-server"

# Package manager caches
export NPM_CONFIG_CACHE="/workspace/deps/runtime/npm-cache"
export PIP_CACHE_DIR="/workspace/deps/runtime/pip-cache"
export YARN_CACHE_FOLDER="/workspace/deps/runtime/yarn-cache"

# Package manager installation directories
export NPM_CONFIG_PREFIX="/workspace/deps/runtime/npm-global"
export PYTHONUSERBASE="/workspace/deps/runtime/pip-user"

# Update PATH to include package manager bins
export PATH="/workspace/deps/runtime/npm-global/bin:/workspace/deps/runtime/pip-user/bin:${PATH}"
# <<< IDE_RUNTIME_ENV
EOF

# SSH keys need root ownership for root SSH access in runtime container
# The runtime container runs SSH as root, so authorized_keys must be owned by root
# Note: This may fail on network volumes - that's OK, they'll work anyway
chown -R root:root /workspace/.ssh 2>/dev/null || true
chmod 700 /workspace/.ssh 2>/dev/null || true
chmod 600 /workspace/.ssh/authorized_keys 2>/dev/null || true
chmod 600 /workspace/.ssh/ssh_host_*_key 2>/dev/null || true
chmod 644 /workspace/.ssh/ssh_host_*_key.pub 2>/dev/null || true

# Mark as installed
mark_installed "ide-ssh-setup"

log_success "IDE and SSH setup complete"