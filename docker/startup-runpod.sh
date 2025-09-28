#!/bin/bash
# Startup script for RunPod with persistent script integration

set -e

# Set locale for UTF-8 encoding
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export LANGUAGE=en_US:en

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


# Unified persistence for Cursor/VSCode and their ecosystem dependencies
PERSIST_ROOT="/workspace/deps/runtime"

# Create persistent directories (apps will create subdirs as needed)
mkdir -p "$PERSIST_ROOT"/{cursor-server,vscode-server,cursor-home}
mkdir -p "$PERSIST_ROOT"/{config,data,state,cache}
mkdir -p "$PERSIST_ROOT"/{npm,pip,yarn}
mkdir -p "$PERSIST_ROOT"/{npm-global,pip-user}

# Ensure parent directories exist
mkdir -p /root/.local /root/.cache

# Safe symlink approach - atomic operations
# Cursor/VSCode servers
ln -sfn "$PERSIST_ROOT/cursor-server" /root/.cursor-server
ln -sfn "$PERSIST_ROOT/vscode-server" /root/.vscode-server
ln -sfn "$PERSIST_ROOT/cursor-home" /root/.cursor

# XDG directories (essential for extension state)
ln -sfn "$PERSIST_ROOT/config" /root/.config
ln -sfn "$PERSIST_ROOT/data" /root/.local/share
ln -sfn "$PERSIST_ROOT/state" /root/.local/state
ln -sfn "$PERSIST_ROOT/cache" /root/.cache

# Package manager caches (used by extensions)
ln -sfn "$PERSIST_ROOT/npm" /root/.npm
ln -sfn "$PERSIST_ROOT/pip" /root/.cache/pip
ln -sfn "$PERSIST_ROOT/yarn" /root/.yarn

log_info "Unified persistence: Cursor/VSCode + XDG + package caches → persistent volume"


# Check if Cursor server is persisted
if [ "$(ls -A "$PERSIST_ROOT/cursor-server")" ]; then
    log_info "Cursor server is persisted from volume - fast startup enabled"
else
    log_info "Cursor server will be installed to persistent volume on first connect"
fi

# Clean up old temporary files
rm -f /tmp/cursor-remote-*.token.* /tmp/cursor-remote-*.log.* >/dev/null 2>&1 || true


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

    # Copy persistent SSH host keys from volume if they exist
    if [ -f /workspace/.ssh/ssh_host_ed25519_key ]; then
        # Copy keys instead of symlink for SSHD compatibility
        for key_type in rsa ed25519 ecdsa; do
            if [ -f "/workspace/.ssh/ssh_host_${key_type}_key" ] && [ -f "/workspace/.ssh/ssh_host_${key_type}_key.pub" ]; then
                cp "/workspace/.ssh/ssh_host_${key_type}_key" "/etc/ssh/ssh_host_${key_type}_key"
                cp "/workspace/.ssh/ssh_host_${key_type}_key.pub" "/etc/ssh/ssh_host_${key_type}_key.pub"
                chmod 600 "/etc/ssh/ssh_host_${key_type}_key"
                chmod 644 "/etc/ssh/ssh_host_${key_type}_key.pub"
            fi
        done
        log_ssh "Copied persistent host keys from /workspace/.ssh/ to /etc/ssh/"
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
        log_error "SSHD configuration validation failed: $(echo "$PRE_ERR" | head -n1)"
        log_error "SSH setup cannot continue. Check: tail -20 /tmp/sshd_error.log"
        log_error "Host keys are symlinked - this may be a permission or system issue"
    fi
else
    log_ssh "Already running (ports 22 and 2222)"
fi

# Tailscale helper functions
validate_auth_key() {
    local key="$1"
    [ -n "$key" ] && echo "$key" | grep -Eq '^tskey-(auth|tag)-[A-Za-z0-9_-]+$'
}

sanitize_auth_key() {
    printf %s "$1" | tr -d '\r\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/^"//; s/"$//'
}

get_backend_state() {
    local status_json=""

    if command -v jq >/dev/null 2>&1; then
        if status_json="$(timeout 5 tailscale status --json 2>/dev/null)"; then
            jq -r '.BackendState // "unknown"' <<<"$status_json"
        else
            echo "unknown"
        fi
    else
        status_json="$(timeout 5 tailscale status --json 2>/dev/null || true)"

        if printf '%s' "$status_json" | grep -q '"BackendState":"Running"'; then
            echo "Running"
        elif printf '%s' "$status_json" | grep -q '"BackendState":"NeedsLogin"'; then
            echo "NeedsLogin"
        else
            echo "unknown"
        fi
    fi
}

start_tailscale_daemon() {
    local ts_dir="$1"
    local mode="$2"

    if [ "$mode" = "userspace" ]; then
        nohup tailscaled --tun=userspace-networking --state="$ts_dir/tailscaled.state" \
            --socket=/run/tailscale/tailscaled.sock >> "$ts_dir/tailscaled.log" 2>&1 &
    else
        nohup tailscaled --state="$ts_dir/tailscaled.state" \
            --socket=/run/tailscale/tailscaled.sock >> "$ts_dir/tailscaled.log" 2>&1 &
    fi
}

cleanup_tailscale_state() {
    local ts_dir="$1"
    local force_reset="${TAILSCALE_FORCE_STATE_RESET:-false}"

    # Kill stalled daemon
    if pgrep -x tailscaled >/dev/null; then
        pkill -9 tailscaled 2>/dev/null || true
        sleep 1
        log_ts "Killed stalled daemon process"
    fi

    # Clean state based on reset policy
    if [ "$force_reset" = "true" ]; then
        rm -f "$ts_dir/tailscaled.state" "$ts_dir/tailscaled.state.tmp" "$ts_dir"/*.lock
        rm -f /run/tailscale/tailscaled.sock
        log_ts "Removed stale state files (forced reset enabled)"
    else
        rm -f /run/tailscale/tailscaled.sock "$ts_dir"/*.lock 2>/dev/null || true
        log_ts "Preserved tailscaled.state; only cleaned locks/socket"
    fi
}

# Quick daemon readiness check (5s max, then continue)
wait_for_daemon() {
    for i in {1..10}; do
        tailscale status --json >/dev/null 2>&1 && return 0
        sleep 0.5
    done
    return 1  # Continue anyway
}

# Enable optional Tailscale features once connected
enable_tailscale_features() {
    local ts_mode="$1"
    # Enable Tailscale SSH (best-effort)
    timeout 5 tailscale set --ssh >/dev/null 2>&1 && log_ts "Tailscale SSH enabled"
    # Configure serve mapping in userspace mode (best-effort)
    if [ "$ts_mode" = "userspace" ] && timeout 5 tailscale serve --bg --tcp 2222 127.0.0.1:2222 >/dev/null 2>&1; then
        log_ts "Tailscale serve configured for port 2222"
    fi
}

# Background watcher: report state transitions and exit when Running
watch_tailscale_state() {
    local ts_mode="$1"
    local prev_state="unknown"
    local -a delays=(0.5 1 2 4 8 10 10 10)
    local delay_idx=0
    local start_time=$SECONDS

    while [ $((SECONDS - start_time)) -lt 120 ]; do
        # Prefer concrete connectivity signal
        local ip=""
        ip="$(timeout 2 tailscale ip -4 2>/dev/null | head -n1 || true)"
        local state="unknown"

        if [ -n "$ip" ]; then
            state="Running"
        else
            state="$(get_backend_state)"
        fi

        if [ "$state" != "$prev_state" ]; then
            if [ "$state" = "Running" ]; then
                log_ts "Connected: ${TS_HOSTNAME:-unknown} @ ${ip:-unknown}"
                enable_tailscale_features "$ts_mode"
                return 0
            else
                log_ts "State: $state"
            fi
            prev_state="$state"
        fi

        # Simple backoff with predefined delays
        sleep "${delays[$delay_idx]:-10}"
        [ $delay_idx -lt $((${#delays[@]} - 1)) ] && delay_idx=$((delay_idx + 1))
    done

    log_warn "Tailscale setup timeout (continuing in background)"
    return 1
}

# Tailscale Setup
if command -v tailscaled >/dev/null 2>&1; then
    TS_DIR="/workspace/deps/runtime/tailscale"
    mkdir -p "$TS_DIR" /run/tailscale

    cleanup_tailscale_state "$TS_DIR"

    # Get and validate auth key (env takes precedence)
    TS_AUTHKEY=""
    AUTH_SOURCE="none"

    if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
        TS_AUTHKEY_CLEAN="$(sanitize_auth_key "$TAILSCALE_AUTHKEY")"
        if validate_auth_key "$TS_AUTHKEY_CLEAN"; then
            TS_AUTHKEY="$TS_AUTHKEY_CLEAN"
            AUTH_SOURCE="env"
        else
            log_warn "TAILSCALE_AUTHKEY env present but invalid format; ignoring"
        fi
    elif [ -f "$TS_DIR/authkey" ]; then
        TS_AUTHKEY_CLEAN="$(sanitize_auth_key "$(head -n1 "$TS_DIR/authkey" 2>/dev/null)")"
        if validate_auth_key "$TS_AUTHKEY_CLEAN"; then
            TS_AUTHKEY="$TS_AUTHKEY_CLEAN"
            AUTH_SOURCE="file"
            chmod 600 "$TS_DIR/authkey" 2>/dev/null || true
        else
            log_warn "Tailscale authkey file present but invalid format; ignoring"
        fi
    fi

    # Generate stable hostname
    if [ -n "${TAILSCALE_HOSTNAME:-}" ]; then
        TS_HOSTNAME="${TAILSCALE_HOSTNAME}"
    elif [ -n "${RUNPOD_POD_ID:-}" ]; then
        TS_HOSTNAME="coral-machine-${RUNPOD_POD_ID:0:8}"
    else
        if [ -f "$TS_DIR/node-id" ]; then
            NODE_ID="$(head -c 8 "$TS_DIR/node-id" 2>/dev/null)"
        else
            NODE_ID="$(tr -dc 'a-f0-9' </dev/urandom | head -c8)"
            echo "$NODE_ID" > "$TS_DIR/node-id" 2>/dev/null || true
        fi
        TS_HOSTNAME="coral-machine-${NODE_ID}"
    fi

    # Start daemon
    TS_MODE="kernel"
    [ ! -e /dev/net/tun ] && TS_MODE="userspace"
    start_tailscale_daemon "$TS_DIR" "$TS_MODE"

    # Quick daemon readiness check
    if wait_for_daemon; then
        log_ts "Daemon ready"
    else
        log_warn "Daemon slow to start (continuing anyway)"
    fi
    # Always use watcher (handles all cases including already connected)
    watch_tailscale_state "$TS_MODE" &

    # Start auth if needed
    BACKEND_STATE="$(get_backend_state)"
    if [ "$BACKEND_STATE" != "Running" ] && [ -n "$TS_AUTHKEY" ]; then
        log_ts "Initiating authentication (source: $AUTH_SOURCE)..."
        tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" >/dev/null 2>&1 &
    elif [ "$BACKEND_STATE" = "Running" ]; then
        log_ts "Already authenticated, updating hostname..."
        timeout 10 tailscale up --hostname="$TS_HOSTNAME" >/dev/null 2>&1 || true
    elif [ -z "$TS_AUTHKEY" ]; then
        log_warn "No auth key provided"
        log_warn "Set TAILSCALE_AUTHKEY or echo 'tskey-...' > $TS_DIR/authkey"
    fi
else
    log_ts "Not installed"
fi

# Collect status variables for summary
SSH_RUNNING=$(pgrep -x sshd >/dev/null && echo "true" || echo "false")
SSHKEY_COUNT=0
if [ -f /workspace/.ssh/authorized_keys ]; then
    SSHKEY_COUNT=$(grep -c '^ssh-' /workspace/.ssh/authorized_keys 2>/dev/null || echo 0)
fi

# Development environment status
COMPILER_STATUS=$(which nvc++ &>/dev/null && echo "✓" || echo "✗")
PALABOS_STATUS=$([ -f "/workspace/deps/lib/libpalabos.a" ] && echo "✓" || echo "✗")
PARAVIEW_STATUS=$(which pvserver &>/dev/null && echo "✓" || echo "✗")
ENV_INITIALIZED=$([ -f "/workspace/deps/env.sh" ] && echo "✓" || echo "✗")

# GPU status
GPU_STATUS="not detected"
if [ -n "${GPU_ARCH_NAME:-}" ]; then
    GPU_STATUS="${GPU_ARCH_NAME} (${GPU_ARCH_FLAG})"
fi

# Tailscale status (only if installed)
TS_AVAILABLE="false"
TS_CONNECTED="false"
TS_IP_ADDR=""
TS_HOSTNAME_SAFE=""
TS_MODE_SAFE=""
if command -v tailscale >/dev/null 2>&1; then
    TS_AVAILABLE="true"
    # Check actual connectivity
    if timeout 5 tailscale ip -4 >/dev/null 2>&1; then
        TS_CONNECTED="true"
    fi

    if [ "$TS_CONNECTED" = "true" ]; then
        TS_IP_ADDR="$(timeout 5 tailscale ip -4 2>/dev/null | head -n1)"
        TS_HOSTNAME_SAFE="${TS_HOSTNAME:-unknown}"
        TS_MODE_SAFE="${TS_MODE:-kernel}"
    fi
fi

# Cursor/VSCode persistence status
CURSOR_PERSISTED="✗"
if [ "$(ls -A "$PERSIST_ROOT/cursor-server" 2>/dev/null)" ]; then
    CURSOR_PERSISTED="✓"
fi

# Final status summary
echo ""
log_ready "Coral Machine Development Environment"
echo "========================================="

# Environment Status
echo ""
echo "Environment Status:"
echo "  Workspace:   $ENV_INITIALIZED /workspace/deps/env.sh"
echo "  GPU:         $GPU_STATUS"
echo "  Compiler:    $COMPILER_STATUS nvc++ (HPC SDK)"
echo "  Palabos:     $PALABOS_STATUS physics library"
echo "  ParaView:    $PARAVIEW_STATUS visualization server"
echo "  Persistence: $CURSOR_PERSISTED Cursor/VSCode data"

# SSH Key Status (applies to all SSH methods)
echo ""
if [ "$SSHKEY_COUNT" -eq 0 ]; then
    echo "⚠️  SSH Keys: No keys configured"
    echo "   Action: echo 'ssh-ed25519 YOUR_KEY' >> /workspace/.ssh/authorized_keys"
else
    echo "✓  SSH Keys: $SSHKEY_COUNT authorized key(s) configured"
fi

# Connection Methods
echo ""
echo "Connection Methods:"

# Direct SSH (always show if SSH is running)
if [ "$SSH_RUNNING" = "true" ]; then
    POD_IP="${RUNPOD_POD_IP:-$(hostname -I | awk '{print $1}')}"
    echo ""
    echo "  Direct SSH (ports 22, 2222):"
    echo "    Terminal:  ssh root@$POD_IP -p 2222"
    echo "    + ParaView: ssh root@$POD_IP -p 2222 -L 11111:localhost:11111"
fi

# Tailscale SSH (only if connected)
if [ "$TS_CONNECTED" = "true" ]; then
    echo ""
    echo "  Tailscale SSH (zero-config):"
    echo "    Terminal:  ssh root@$TS_IP_ADDR"
    echo "    MagicDNS:  ssh root@$TS_HOSTNAME_SAFE"
    if [ "$TS_MODE_SAFE" = "userspace" ]; then
        echo "    Cursor:    ssh root@$TS_IP_ADDR -p 2222"
        echo "    MagicDNS:  ssh root@$TS_HOSTNAME_SAFE -p 2222"
    fi
elif [ "$TS_AVAILABLE" = "true" ]; then
    echo ""
    echo "  Tailscale: Available but not connected"
    echo "    Action: Set TAILSCALE_AUTHKEY or configure auth key"
fi

# RunPod SSH (if available)
if [ -n "${RUNPOD_POD_ID:-}" ]; then
    echo ""
    echo "  RunPod SSH (platform native):"
    echo "    Default:   ssh root@${RUNPOD_POD_ID}.ssh.runpod.io"
fi

# Show warning if no SSH methods are available
if [ "$SSH_RUNNING" = "false" ] && [ "$TS_CONNECTED" = "false" ] && [ -z "${RUNPOD_POD_ID:-}" ]; then
    echo ""
    echo "  ⚠️  No SSH connections available"
fi

echo ""
echo "Quick Commands:"
echo "  paraview       - Start ParaView server (port 11111)"
echo "  pv status      - Check ParaView server status"
echo "  coral-help     - Show all available commands"
echo "  make setup     - Initialize development environment"
echo "========================================="

# Keep container running
tail -f /dev/null
