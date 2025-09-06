#!/bin/bash
# Startup script for Coral Machine runtime container
# Simpler than the original - just starts SSH and validates environment

set -e

echo "🚀 Starting Coral Machine Development Environment"

# Start SSH daemon
echo "📡 Starting SSH daemon..."
sudo service ssh start

if [ $? -eq 0 ]; then
    echo "✅ SSH daemon started successfully"
else
    echo "❌ Failed to start SSH daemon"
    exit 1
fi

# Check if volume is initialized
if [ -f "/workspace/deps/.setup-complete" ]; then
    echo "✅ Volume initialized: $(cat /workspace/deps/.setup-complete)"
    
    # Source environment
    if [ -f "/workspace/deps/env.sh" ]; then
        source /workspace/deps/env.sh
        echo "✅ Environment loaded from volume"
        
        # Quick validation
        echo "📋 Available tools:"
        which nvc++ 2>/dev/null && echo "  ✓ nvc++ compiler" || echo "  ⚠️ nvc++ not found"
        which nvcc 2>/dev/null && echo "  ✓ CUDA compiler" || echo "  ⚠️ nvcc not found"
        which pvserver 2>/dev/null && echo "  ✓ ParaView server" || echo "  ⚠️ pvserver not found"
        [ -f "/workspace/deps/lib/libpalabos.a" ] && echo "  ✓ Palabos library" || echo "  ⚠️ Palabos not found"
    else
        echo "⚠️ Environment file not found at /workspace/deps/env.sh"
    fi
else
    echo "⚠️ Volume not initialized. Run setup first:"
    echo "   docker-compose --profile setup run setup"
fi

# Update /etc/environment for SSH sessions
if [ -f "/workspace/deps/env.sh" ]; then
    echo "📝 Updating SSH environment..."
    # Extract key variables and write to /etc/environment
    sudo bash -c 'source /workspace/deps/env.sh && env | grep -E "^(PATH|LD_LIBRARY_PATH|CMAKE_PREFIX_PATH|CUDA_HOME|NVHPC_ROOT)=" > /etc/environment'
fi

echo ""
echo "========================================="
echo "Development environment ready!"
echo "SSH: ssh ${USER}@localhost -p 2222"
echo "========================================="

# Keep container running
tail -f /dev/null