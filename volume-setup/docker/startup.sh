#!/bin/bash
# Startup script for Coral Machine runtime container
# Simpler than the original - just starts SSH and validates environment

set -e

echo "🚀 Starting Coral Machine Development Environment"

# Link SSH keys from volume if they exist
echo "🔐 Setting up SSH keys..."
if [ -f "/workspace/.ssh/authorized_keys" ]; then
    ln -sf /workspace/.ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    echo "✅ SSH authorized_keys linked from volume"
fi

# Link persistent SSH host keys from volume if they exist
if [ -f "/workspace/.ssh/ssh_host_rsa_key" ]; then
    for key_type in rsa ed25519 ecdsa; do
        if [ -f "/workspace/.ssh/ssh_host_${key_type}_key" ]; then
            ln -sf "/workspace/.ssh/ssh_host_${key_type}_key" "/etc/ssh/ssh_host_${key_type}_key"
            ln -sf "/workspace/.ssh/ssh_host_${key_type}_key.pub" "/etc/ssh/ssh_host_${key_type}_key.pub"
            chmod 600 "/etc/ssh/ssh_host_${key_type}_key"
            chmod 644 "/etc/ssh/ssh_host_${key_type}_key.pub"
        fi
    done
    echo "✅ SSH host keys linked from volume (persistent identity)"
else
    echo "⚠️ No persistent SSH host keys found, using container defaults"
fi

# Configure SSH to use workspace authorized_keys directly
echo "🔧 Configuring SSH daemon..."
mkdir -p /etc/ssh/sshd_config.d/
cat > /etc/ssh/sshd_config.d/99-coral.conf << 'EOF'
# Use workspace authorized_keys directly
AuthorizedKeysFile /workspace/.ssh/authorized_keys
# Disable strict mode to allow symlinked keys and non-standard ownership
StrictModes no
# Keep connection alive
ClientAliveInterval 60
ClientAliveCountMax 3
EOF

# Ensure correct ownership (in case volume setup used wrong owner)
if [ -f "/workspace/.ssh/authorized_keys" ]; then
    chown root:root /workspace/.ssh/authorized_keys 2>/dev/null || true
    chmod 600 /workspace/.ssh/authorized_keys 2>/dev/null || true
fi

# Use custom MOTD from volume if it exists
if [ -f "/workspace/deps/runtime/motd" ]; then
    cp /workspace/deps/runtime/motd /etc/motd
    echo "✅ Custom MOTD loaded from volume"
fi

# Start SSH daemon (no sudo needed as root)
echo "📡 Starting SSH daemon..."
service ssh start

if [ $? -eq 0 ]; then
    echo "✅ SSH daemon started successfully"
else
    echo "❌ Failed to start SSH daemon"
    exit 1
fi

# Ensure ccache directory exists (running as root now)
echo "🔧 Setting up ccache directory..."
if [ ! -d "/workspace/.ccache" ]; then
    mkdir -p /workspace/.ccache
    echo "✅ ccache directory created"
else
    echo "✅ ccache directory exists"
fi
chmod -R 755 /workspace/.ccache

# Check if volume is initialized
if [ -f "/workspace/deps/.setup-complete" ]; then
    echo "✅ Volume initialized: $(cat /workspace/deps/.setup-complete)"

    # Detect GPU architecture and update environment
    if [ -f "/workspace/deps/scripts/detect-gpu-arch.sh" ]; then
        echo "🎯 Detecting GPU architecture..."
        source /workspace/deps/scripts/detect-gpu-arch.sh
        if detect_gpu_architecture; then
            # Write GPU vars to env.sh if detection succeeded
            write_gpu_env "/workspace/deps/env.sh"
        else
            echo "⚠️ GPU detection failed - will use multi-architecture builds"
        fi
    fi

    # Source environment (includes GPU vars if detected)
    if [ -f "/workspace/deps/env.sh" ]; then
        source /workspace/deps/env.sh
        echo "✅ Environment loaded from volume"

        # Quick validation
        echo "📋 Available tools:"
        which nvc++ 2>/dev/null && echo "  ✓ nvc++ compiler" || echo "  ⚠️ nvc++ not found"
        which nvcc 2>/dev/null && echo "  ✓ CUDA compiler" || echo "  ⚠️ nvcc not found"
        which pvserver 2>/dev/null && echo "  ✓ ParaView server" || echo "  ⚠️ pvserver not found"
        [ -f "/workspace/deps/lib/libpalabos.a" ] && echo "  ✓ Palabos library" || echo "  ⚠️ Palabos not found"

        # Show GPU architecture if detected
        if [ -n "${GPU_ARCH_NAME:-}" ]; then
            echo "  ✓ GPU: ${GPU_NAME} (${GPU_ARCH_FLAG})"
        fi
    else
        echo "⚠️ Environment file not found at /workspace/deps/env.sh"
    fi
else
    echo "⚠️ Volume not initialized. Run setup first:"
    echo "   docker-compose --profile setup run setup"
fi

# Update /etc/environment for SSH sessions (no sudo needed as root)
if [ -f "/workspace/deps/env.sh" ]; then
    echo "📝 Updating SSH environment..."
    # Extract key variables and write to /etc/environment (including GPU vars)
    bash -c 'source /workspace/deps/env.sh && env | grep -E "^(PATH|LD_LIBRARY_PATH|CMAKE_PREFIX_PATH|CUDA_HOME|NVHPC_ROOT|CUDA_COMPUTE_CAPABILITY|CUDA_ARCH_FLAG|CUDA_ARCH_SM|NVHPC_GPU_FLAG|CMAKE_CUDA_ARCHITECTURES|GPU_ARCH_NAME|GPU_NAME)=" > /etc/environment'
fi

echo ""
echo "========================================="
echo "Development environment ready!"
echo "SSH: ssh root@localhost -p 2222"
echo "========================================="

# Keep container running
tail -f /dev/null