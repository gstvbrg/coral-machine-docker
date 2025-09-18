#!/bin/bash
# Final startup script for RunPod with persistent scripts integration

set -e

# Logging helpers
log_info() { echo "[INFO] $*"; }
log_env() { echo "[ENV] $*"; }
log_ssh() { echo "[SSH] $*"; }
log_ts() { echo "[TS] $*"; }
log_ready() { echo "[READY] $*"; }
log_warn() { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
log_check() { echo "  ✓ $*"; }
log_miss() { echo "  ✗ $*"; }

log_info "Starting Coral Machine Development Environment (RunPod)"

# Ensure ccache directory exists with correct permissions
if [ ! -d "/workspace/.ccache" ]; then
    mkdir -p /workspace/.ccache
    log_info "Created ccache directory"
fi
chmod -R 755 /workspace/.ccache 2>/dev/null || true

# Ensure scripts directory exists and has correct permissions
if [ -d "/workspace/deps/scripts" ]; then
    chmod +x /workspace/deps/scripts/*.sh 2>/dev/null || true
    log_info "Scripts directory ready"
else
    log_warn "Scripts directory not found at /workspace/deps/scripts"
    log_warn "Action: Run setup first or check volume mount"
fi

# Detect GPU architecture first
if [ -f "/workspace/deps/scripts/detect-gpu-arch.sh" ]; then
    log_info "Detecting GPU architecture..."
    source /workspace/deps/scripts/detect-gpu-arch.sh
    if detect_gpu_architecture; then
        # Write GPU vars to env.sh if detection succeeded
        write_gpu_env "/workspace/deps/env.sh"
        log_info "GPU: ${GPU_NAME} detected (${GPU_ARCH_FLAG})"
    else
        log_warn "GPU detection failed - will use multi-architecture builds"
    fi
fi

# Load environment (includes GPU vars if detected)
if [ -f "/workspace/deps/env.sh" ]; then
    source /workspace/deps/env.sh
    log_env "Environment loaded from /workspace/deps/env.sh"

    # Quick validation
    which nvc++ &>/dev/null && log_check "nvc++ compiler" || log_miss "nvc++ compiler - run 'make install-compilers'"
    [ -f "/workspace/deps/lib/libpalabos.a" ] && log_check "Palabos library" || log_miss "Palabos library - run 'make install-libraries'"
    which pvserver &>/dev/null && log_check "ParaView server" || log_miss "ParaView - run 'make install-viz'"

    # Show GPU architecture if detected
    if [ -n "${GPU_ARCH_NAME:-}" ]; then
        log_check "GPU arch: ${GPU_ARCH_NAME} (${GPU_ARCH_FLAG})"
    fi
else
    log_error "Environment not initialized at /workspace/deps/env.sh"
    log_error "Action: Run 'make setup' from volume-setup directory"
fi


# Persist Cursor/VSCode servers and XDG dirs by symlinking into the volume
PERSIST_ROOT="/workspace/deps/runtime"
mkdir -p "$PERSIST_ROOT/cursor-server" \
         "$PERSIST_ROOT/cursor-home" \
         "$PERSIST_ROOT/vscode-server" \
         "$PERSIST_ROOT/xdg/data" \
         "$PERSIST_ROOT/xdg/config" \
         "$PERSIST_ROOT/xdg/state" \
         "$PERSIST_ROOT/xdg/cache" \
         "$PERSIST_ROOT/npm-cache" \
         "$PERSIST_ROOT/pip-cache" \
         "$PERSIST_ROOT/yarn-cache"

# Helper to replace a path with a symlink to persistent target
persist_link() {
    local src_path="$1"
    local dst_path="$2"
    local parent_dir
    parent_dir="$(dirname "$src_path")"
    mkdir -p "$parent_dir" 2>/dev/null || true
    if [ -L "$src_path" ]; then
        return 0
    fi
    if [ -d "$src_path" ] || [ -f "$src_path" ]; then
        rm -rf "$src_path"
    fi
    ln -s "$dst_path" "$src_path" || log_warn "Failed to link $src_path -> $dst_path"
}

# Cursor server home and agent cache
persist_link "/root/.cursor-server" "$PERSIST_ROOT/cursor-server"
persist_link "/root/.cursor" "$PERSIST_ROOT/cursor-home"

# VSCode remote server (Cursor uses similar paths)
persist_link "/root/.vscode-server" "$PERSIST_ROOT/vscode-server"

# Check if Cursor server is persisted
if [ "$(ls -A "$PERSIST_ROOT/cursor-server")" ]; then
    log_info "Cursor server is persisted from volume - fast startup enabled"
else
    log_info "Cursor server will be installed to persistent volume on first connect"
fi

# Proactively clean up any stale Cursor processes/tokens from previous sessions
# This avoids reusing unhealthy multiplex/code servers that can delay reconnection
if pgrep -f 'cursor-remote|cursor-server' >/dev/null 2>&1; then
    log_info "Stopping stale Cursor processes (cursor-remote/cursor-server)"
    pkill -f 'cursor-remote|cursor-server' >/dev/null 2>&1 || true
fi
rm -f /tmp/cursor-remote-*.token.* /tmp/cursor-remote-*.log.* >/dev/null 2>&1 || true

# XDG base directories
# Ensure parent directories exist for XDG symlinks
mkdir -p /root/.local

persist_link "/root/.local/share" "$PERSIST_ROOT/xdg/data"
persist_link "/root/.config" "$PERSIST_ROOT/xdg/config"
persist_link "/root/.local/state" "$PERSIST_ROOT/xdg/state"
persist_link "/root/.cache" "$PERSIST_ROOT/xdg/cache"

# Common language/tool caches
persist_link "/root/.npm" "$PERSIST_ROOT/npm-cache"
persist_link "/root/.cache/pip" "$PERSIST_ROOT/pip-cache"
persist_link "/root/.yarn" "$PERSIST_ROOT/yarn-cache"

# Setup persistent aliases
if [ -f "/workspace/deps/scripts/setup-aliases.sh" ]; then
    if ! grep -q "setup-aliases.sh" ~/.bashrc 2>/dev/null; then
        echo "" >> ~/.bashrc
        echo "# Coral Machine utilities" >> ~/.bashrc
        echo "[ -f /workspace/deps/scripts/setup-aliases.sh ] && source /workspace/deps/scripts/setup-aliases.sh" >> ~/.bashrc
        log_info "Added aliases to ~/.bashrc (paraview, pv, coral-help)"
    fi
    source /workspace/deps/scripts/setup-aliases.sh
fi

# Use custom MOTD from volume if it exists
if [ -f "/workspace/deps/runtime/motd" ]; then
    cp /workspace/deps/runtime/motd /etc/motd
    log_info "Custom MOTD loaded from volume"
fi

# SSH Server Setup
if ! pgrep -x sshd > /dev/null; then
    log_ssh "Starting SSH server..."

    # Create persistent SSH directory and runtime key location
    mkdir -p /workspace/.ssh /etc/ssh
    chmod 700 /workspace/.ssh 2>/dev/null || true

    # Link persistent SSH host keys from volume if they exist
    if [ -f /workspace/.ssh/ssh_host_ed25519_key ]; then
        # Use symlinks to persistent keys (created during volume setup)
        for key_type in rsa ed25519 ecdsa; do
            if [ -f "/workspace/.ssh/ssh_host_${key_type}_key" ]; then
                ln -sf "/workspace/.ssh/ssh_host_${key_type}_key" "/etc/ssh/ssh_host_${key_type}_key"
                ln -sf "/workspace/.ssh/ssh_host_${key_type}_key.pub" "/etc/ssh/ssh_host_${key_type}_key.pub"
                chmod 600 "/etc/ssh/ssh_host_${key_type}_key" 2>/dev/null || true
                chmod 644 "/etc/ssh/ssh_host_${key_type}_key.pub" 2>/dev/null || true
            fi
        done
        log_ssh "Using persistent host keys from /workspace/.ssh/"
    else
        # Generate temporary keys if volume setup hasn't run yet
        log_warn "No persistent SSH host keys found - generating temporary keys"
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" >/dev/null 2>&1
        ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N "" >/dev/null 2>&1
        ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N "" >/dev/null 2>&1
        log_warn "Run volume setup to create persistent host keys"
    fi

    # Set permissions on authorized_keys if it exists
    [ -f /workspace/.ssh/authorized_keys ] && chmod 600 /workspace/.ssh/authorized_keys 2>/dev/null || true
    
    # Create minimal sshd_config
    cat > /tmp/sshd_config << 'EOF'
Port 22
Port 2222
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
PermitRootLogin yes
PubkeyAuthentication yes
AuthorizedKeysFile /workspace/.ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
StrictModes no
ClientAliveInterval 60
ClientAliveCountMax 3
UseDNS no
Subsystem sftp /usr/lib/openssh/sftp-server
MaxStartups 10:30:100
TCPKeepAlive yes
EOF
    
    # Check if authorized_keys exists from volume setup
    if [ -f /workspace/.ssh/authorized_keys ]; then
        KEY_COUNT=$(grep -c '^ssh-' /workspace/.ssh/authorized_keys 2>/dev/null || echo 0)
        log_ssh "Authorized keys: $KEY_COUNT found in /workspace/.ssh/authorized_keys"
    else
        touch /workspace/.ssh/authorized_keys
        chmod 600 /workspace/.ssh/authorized_keys
        log_warn "No SSH keys configured"
        log_warn "Action: echo 'ssh-ed25519 YOUR_KEY' >> /workspace/.ssh/authorized_keys"
    fi
    
    # Preflight and start; fallback to copying keys if needed
    PRE_ERR="$([ -x /usr/sbin/sshd ] && /usr/sbin/sshd -t -f /tmp/sshd_config 2>&1 || true)"
    if [ -z "$PRE_ERR" ]; then
        log_ssh "Using symlinked host keys"
        if /usr/sbin/sshd -f /tmp/sshd_config 2>/tmp/sshd_error.log; then
            log_ssh "Listening on ports 22 and 2222 (key auth only)"
        else
            log_error "SSH failed to start. Check: tail -20 /tmp/sshd_error.log"
        fi
    else
        if echo "$PRE_ERR" | grep -qi 'permission'; then
            log_warn "SSHD preflight failed due to permission issues; copying host keys into /etc/ssh"
        else
            log_warn "SSHD preflight failed; copying host keys (reason: $(echo "$PRE_ERR" | head -n1))"
        fi
        for key_type in rsa ed25519 ecdsa; do
            if [ -f "/workspace/.ssh/ssh_host_${key_type}_key" ] && [ -f "/workspace/.ssh/ssh_host_${key_type}_key.pub" ]; then
                install -m 600 -p "/workspace/.ssh/ssh_host_${key_type}_key"     "/etc/ssh/ssh_host_${key_type}_key"
                install -m 644 -p "/workspace/.ssh/ssh_host_${key_type}_key.pub" "/etc/ssh/ssh_host_${key_type}_key.pub"
            fi
        done

        if /usr/sbin/sshd -t -f /tmp/sshd_config 2>/tmp/sshd_error.log && /usr/sbin/sshd -f /tmp/sshd_config 2>/tmp/sshd_error.log; then
            log_ssh "Listening on ports 22 and 2222 (copied host keys)"
        else
            log_error "SSH failed to start. Check: tail -20 /tmp/sshd_error.log"
        fi
    fi
else
    log_ssh "Already running (ports 22 and 2222)"
fi

# Tailscale Setup
if command -v tailscaled >/dev/null 2>&1; then
    TS_DIR="/workspace/deps/runtime/tailscale"
    mkdir -p "$TS_DIR" /run/tailscale
    TS_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
    [ -n "$TS_AUTHKEY" ] || { [ -f "$TS_DIR/authkey" ] && TS_AUTHKEY="$(head -n1 "$TS_DIR/authkey" | tr -d ' \r\n')"; }
    TS_HOSTNAME="${TAILSCALE_HOSTNAME:-coral-machine}"
    
    # Detect auth source
    AUTH_SOURCE="none"
    [ -n "${TAILSCALE_AUTHKEY:-}" ] && AUTH_SOURCE="env"
    [ -f "$TS_DIR/authkey" ] && [ -z "${TAILSCALE_AUTHKEY:-}" ] && AUTH_SOURCE="file"

    # Start tailscaled with appropriate mode
    TS_MODE="kernel"
    if [ -e /dev/net/tun ]; then
        nohup tailscaled --state="$TS_DIR/tailscaled.state" \
            --socket=/run/tailscale/tailscaled.sock >> "$TS_DIR/tailscaled.log" 2>&1 &
    else
        TS_MODE="userspace"
        nohup tailscaled --tun=userspace-networking --state="$TS_DIR/tailscaled.state" \
            --socket=/run/tailscale/tailscaled.sock >> "$TS_DIR/tailscaled.log" 2>&1 &
    fi

    # Wait for daemon with longer timeout and better feedback
    DAEMON_READY=false
    log_ts "Waiting for daemon to start..."
    for i in {1..30}; do 
        if tailscale status --json >/dev/null 2>&1; then
            DAEMON_READY=true
            break
        fi
        sleep 1
    done

    if [ "$DAEMON_READY" = false ]; then
        log_error "Tailscale daemon failed to start after 30 seconds"
        
        # Auto-cleanup stalled daemon and state (preserves authkey)
        log_warn "Cleaning up stalled Tailscale daemon..."
        
        # 1. Force kill any hung tailscaled process
        if pgrep -x tailscaled >/dev/null; then
            pkill -9 tailscaled 2>/dev/null || true
            sleep 1  # Give it a moment to die
            log_ts "Killed stalled daemon process"
        fi
        
        # 2. Remove state files that cause stalls (but preserve authkey!)
        rm -f "$TS_DIR/tailscaled.state" "$TS_DIR/tailscaled.state.tmp" "$TS_DIR"/*.lock
        rm -f /run/tailscale/tailscaled.sock
        log_ts "Removed stale state files"
        
        # 3. Archive the failed log for debugging (don't delete it)
        if [ -f "$TS_DIR/tailscaled.log" ]; then
            mv "$TS_DIR/tailscaled.log" "$TS_DIR/tailscaled.log.failed.$(date +%Y%m%d_%H%M%S)"
            log_ts "Archived failed log for debugging"
        fi
        
        log_info "Cleanup complete. State reset for clean restart (authkey preserved)"
        # Continue without Tailscale instead of hanging
    else
        # Check actual backend state robustly (jq preferred, grep fallback)
        if command -v jq >/dev/null 2>&1; then
            BACKEND_STATE="$(timeout 5 tailscale status --json 2>/dev/null | jq -r '.BackendState // "unknown"')"
        else
            BACKEND_STATE="unknown"
            if timeout 5 tailscale status --json 2>/dev/null | grep -q '"BackendState":"NeedsLogin"'; then
                BACKEND_STATE="NeedsLogin"
            elif timeout 5 tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
                BACKEND_STATE="Running"
            fi
        fi

        if [ "$BACKEND_STATE" = "NeedsLogin" ]; then
            # Only attempt login if we have an authkey
            if [ -n "$TS_AUTHKEY" ]; then
                log_ts "Authenticating with provided key (source: $AUTH_SOURCE)..."
                if timeout 30 tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" >/dev/null 2>&1; then
                    log_ts "Authentication successful"
                    BACKEND_STATE="Running"  # Update state for later checks
                else
                    log_error "Authentication failed. Check: tail -20 $TS_DIR/tailscaled.log"
                    log_warn "Tailscale will continue trying in background"
                fi
            else
                log_warn "Tailscale needs authentication"
                log_warn "Action: Set TAILSCALE_AUTHKEY env var or echo 'tskey-auth-...' > $TS_DIR/authkey"
                log_warn "Then restart the container to authenticate"
            fi
        elif [ "$BACKEND_STATE" = "Running" ]; then
            # Already authenticated, just update hostname if needed
            log_ts "Already authenticated, updating hostname..."
            timeout 10 tailscale up --hostname="$TS_HOSTNAME" >/dev/null 2>&1 || true
        else
            log_warn "Unknown Tailscale state, skipping configuration"
        fi
    fi

    # Enable Tailscale SSH and serve (only if fully authenticated and running)
    if [ "$BACKEND_STATE" = "Running" ]; then
        # Enable Tailscale SSH
        if timeout 5 tailscale set --ssh >/dev/null 2>&1; then
            log_ts "Tailscale SSH enabled"
        fi

        # If userspace mode, expose SSH over tailnet
        SERVE_STATUS=""
        if [ "$TS_MODE" = "userspace" ]; then
            if timeout 5 tailscale serve tcp:2222 127.0.0.1:2222 >/dev/null 2>&1; then
                SERVE_STATUS=", serving :2222→localhost:2222"
                log_ts "Tailscale serve configured for port 2222"
            fi
        fi

        # Report final status
        if timeout 5 tailscale status >/dev/null 2>&1; then
            TS_IP="$(timeout 5 tailscale ip -4 2>/dev/null | head -n1)"
            log_ts "Connected: $TS_HOSTNAME @ $TS_IP (mode: $TS_MODE$SERVE_STATUS)"
        else
            log_error "Tailscale status check failed"
            log_error "Debug: tail -20 $TS_DIR/tailscaled.log"
        fi
    elif [ "$DAEMON_READY" = true ]; then
        # Daemon is ready but not authenticated
        log_ts "Daemon running but not authenticated (state: ${BACKEND_STATE:-unknown})"
        log_ts "SSH/serve features will be enabled after authentication"
    fi
else
    log_ts "Not installed"
fi

# Final status summary
echo ""
log_ready "Coral Machine Development Environment"
echo "========================================="

# Connection recipes based on what's actually available
if pgrep -x sshd >/dev/null; then
    POD_IP="${RUNPOD_POD_IP:-$(hostname -I | awk '{print $1}')}"
    echo "SSH Connections:"
    echo "  Direct:    ssh root@$POD_IP -p 2222"
    echo "  + ParaView: ssh root@$POD_IP -p 2222 -L 11111:localhost:11111"
    
    if [ -f /workspace/.ssh/authorized_keys ] && [ $(grep -c '^ssh-' /workspace/.ssh/authorized_keys 2>/dev/null || echo 0) -eq 0 ]; then
        echo "  ⚠️ No keys: echo 'YOUR_SSH_KEY' >> /workspace/.ssh/authorized_keys"
    fi
fi

if command -v tailscale >/dev/null 2>&1 && timeout 5 tailscale status >/dev/null 2>&1; then
    TS_IP="$(timeout 5 tailscale ip -4 2>/dev/null | head -n1)"
    echo ""
    echo "Tailscale SSH:"
    echo "  Terminal:  ssh root@$TS_IP"
    if [ "$TS_MODE" = "userspace" ]; then
        echo "  Cursor:    ssh root@$TS_IP -p 2222"
    fi
fi

if [ -n "${RUNPOD_POD_ID:-}" ]; then
    echo ""
    echo "RunPod SSH:"
    echo "  Default:   ssh root@${RUNPOD_POD_ID}.ssh.runpod.io"
fi

echo ""
echo "Quick Commands:"
echo "  paraview   - Start ParaView server"
echo "  pv status  - Check ParaView status"
echo "  coral-help - Show all commands"
echo "========================================="

# Keep container running
tail -f /dev/null