#!/usr/bin/env bash
# Startup script for volume-based Coral Machine development container
# RESILIENT: Container stays alive even if services fail
# Key change: Removed 'set -e' which was killing container on any error
set -uo pipefail

echo "🚀 Starting Coral Machine Development Environment (Volume Mode)"

# ---------- Config via env (with defaults) ----------
: "${START_PVSERVER:=true}"
: "${PV_BACKEND:=egl}"             # egl | xvfb | none
: "${PV_SERVER_PORT:=11111}"
: "${MPI_PROCESSES:=1}"
: "${PV_FORCE_OFFSCREEN:=true}"
: "${AUTO_CLONE:=false}"
: "${AUTO_BUILD:=false}"
: "${CORAL_REPO_URL:=}"
: "${REPO_BRANCH:=main}"
: "${SRC_DIR:=/workspace/source}"

# ========== CRITICAL: Start SSH First ==========
echo "📡 Starting SSH daemon..."
ssh-keygen -A >/dev/null 2>&1 || true
if ! pgrep -x sshd >/dev/null; then
  if /usr/sbin/sshd; then
    echo "✅ SSH daemon started successfully"
  else
    echo "⚠️  SSH daemon failed to start - container will continue"
  fi
else
  echo "✅ SSH daemon already running"
fi

# ========== Volume Initialization Check ==========
if [ ! -f "/workspace/deps/.initialized" ]; then
    echo "⚠️  WARNING: Volume not initialized!"
    echo ""
    echo "The /workspace/deps volume appears to be empty or not properly initialized."
    echo "Please run the setup container first to populate the volume:"
    echo ""
    echo "  docker-compose --profile setup run setup"
    echo ""
    echo "Continuing with limited functionality..."
    VOLUME_READY=false
else
    echo "✅ Volume initialized: $(cat /workspace/deps/.initialized)"
    VOLUME_READY=true
    
    # Verify key components
    if [ -x "/workspace/deps/paraview/bin/pvserver" ]; then
        echo "✓ ParaView server found"
    else
        echo "⚠️  ParaView server not found in volume"
    fi
    
    if [ -f "/workspace/deps/palabos-hybrid/lib/libpalabos.a" ]; then
        echo "✓ Palabos-hybrid library found"
    else
        echo "⚠️  Palabos-hybrid not found in volume"
    fi
    
    if [ -d "/workspace/deps/nvidia-hpc" ]; then
        echo "✓ NVIDIA HPC SDK found"
        which nvc++ >/dev/null 2>&1 && echo "✓ nvc++ compiler available" || echo "⚠️  nvc++ not in PATH"
    else
        echo "⚠️  NVIDIA HPC SDK not found in volume"
    fi
fi

# ========== Load Environment from Volume ==========
if [ -f "/workspace/deps/env.sh" ]; then
    echo "✅ Loading environment from volume"
    source /workspace/deps/env.sh
    
    # Update /etc/environment for SSH sessions
    cat > /etc/environment << EOF
PATH="${PATH}"
LD_LIBRARY_PATH="${LD_LIBRARY_PATH}"
CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH}"
PALABOS_ROOT="${PALABOS_ROOT}"
CCACHE_DIR="${CCACHE_DIR}"
CCACHE_MAXSIZE="${CCACHE_MAXSIZE}"
CUDA_HOME="${CUDA_HOME}"
NVHPC_ROOT="${NVHPC_ROOT}"
EOF
else
    echo "⚠️  Volume environment script not found - using defaults"
    export PATH="/workspace/deps/paraview/bin:$PATH"
    export LD_LIBRARY_PATH="/workspace/deps/paraview/lib:$LD_LIBRARY_PATH"
    export CMAKE_PREFIX_PATH="/workspace/deps"
    export PALABOS_ROOT="/workspace/deps/palabos-hybrid"
fi

# ========== Initialize ccache ==========
if [ ! -d "/workspace/.ccache" ]; then
    mkdir -p /workspace/.ccache
    echo "max_size = 10G" > /workspace/.ccache/ccache.conf
fi
echo "⚙️  Configuring ccache..."
ccache -M 10G 2>/dev/null || true
ccache -s 2>/dev/null || true

# ========== Create logs directory ==========
mkdir -p /workspace/logs
echo "📝 Logs will be saved to /workspace/logs/"

# ========== Optional: Git Clone/Update ==========
if [[ "${AUTO_CLONE}" == "true" ]] && [[ -n "${CORAL_REPO_URL}" ]]; then
  echo "📦 Managing source repository..."
  if [[ -d "${SRC_DIR}/.git" ]]; then
    echo "  Updating existing repo in ${SRC_DIR}"
    if cd "${SRC_DIR}" && git pull --rebase --autostash && git submodule update --init --recursive; then
      echo "  ✅ Repository updated"
    else
      echo "  ⚠️  Repository update failed - using existing code"
    fi
  else
    echo "  Cloning ${CORAL_REPO_URL} -> ${SRC_DIR}"
    if git clone --recursive --branch "${REPO_BRANCH}" "${CORAL_REPO_URL}" "${SRC_DIR}"; then
      echo "  ✅ Repository cloned"
    else
      echo "  ⚠️  Repository clone failed"
    fi
  fi
else
  echo "ℹ️  AUTO_CLONE=false or no repo URL - skipping git operations"
fi

# ========== Optional: Start ParaView Server ==========
start_pv() {
  if [[ "${PV_BACKEND}" == "none" ]]; then
    echo "ℹ️  PV_BACKEND=none; skipping pvserver."
    return 0
  fi

  if [[ "${VOLUME_READY}" != "true" ]]; then
    echo "⚠️  Volume not ready - skipping ParaView server"
    return 1
  fi

  # Check if pvserver exists in volume
  if [ ! -x "/workspace/deps/paraview/bin/pvserver" ]; then
    echo "⚠️  pvserver not found in volume - skipping ParaView server"
    return 1
  fi

  # Build pvserver command - use ParaView's bundled MPI to avoid ABI mismatches
  if [[ "${MPI_PROCESSES}" -gt 1 ]]; then
    # Prefer ParaView's mpiexec if available
    if [ -x "/workspace/deps/paraview/bin/mpiexec" ]; then
      PV_MPIRUN="/workspace/deps/paraview/bin/mpiexec"
      echo "Using ParaView's bundled MPI launcher"
    else
      PV_MPIRUN="mpirun --allow-run-as-root"
      echo "Using system MPI launcher (fallback)"
    fi
    PVSERVER_CMD="${PV_MPIRUN} -np ${MPI_PROCESSES} /workspace/deps/paraview/bin/pvserver"
    echo "🧪 Starting parallel pvserver (${MPI_PROCESSES} processes) on port ${PV_SERVER_PORT}"
  else  
    PVSERVER_CMD="/workspace/deps/paraview/bin/pvserver"
    echo "🧪 Starting single-process pvserver on port ${PV_SERVER_PORT}"
  fi
  
  # Check for NVIDIA GPU
  if nvidia-smi >/dev/null 2>&1; then
    echo "🎮 NVIDIA GPU detected - hardware acceleration available"
  fi

  # Build arguments
  PVSERVER_ARGS="--server-port=${PV_SERVER_PORT}"
  
  # Performance flags
  if [[ "${PV_FORCE_OFFSCREEN}" == "true" ]]; then
    PVSERVER_ARGS="${PVSERVER_ARGS} --force-offscreen-rendering"
  fi
  PVSERVER_ARGS="${PVSERVER_ARGS} --disable-xdisplay-test"

  # Handle display backend
  if [[ "${PV_BACKEND}" == "xvfb" ]]; then
    echo "🖥️  Starting Xvfb for software rendering"
    Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 & 
    export DISPLAY=:99
    sleep 2  # Give Xvfb time to start
  elif [[ "${PV_BACKEND}" == "egl" ]]; then
    echo "🎮 Using EGL for hardware-accelerated headless rendering"
    unset DISPLAY  # Ensure no display is set for EGL
  fi

  # Launch pvserver in background with logging
  echo "▶️  Command: ${PVSERVER_CMD} ${PVSERVER_ARGS}"
  LOG_FILE="/workspace/logs/pvserver_$(date +%Y%m%d_%H%M%S).log"
  echo "📝 Logging to: ${LOG_FILE}"
  
  # Start pvserver with output logged
  ${PVSERVER_CMD} ${PVSERVER_ARGS} >> "${LOG_FILE}" 2>&1 &
  PVSERVER_PID=$!
  
  # Give it a moment to start and check if it's running
  sleep 3
  if kill -0 ${PVSERVER_PID} 2>/dev/null; then
    echo "✅ ParaView server started successfully (PID: ${PVSERVER_PID})"
    echo "📋 Recent log output:"
    tail -n 5 "${LOG_FILE}" | sed 's/^/    /'
  else
    echo "⚠️  ParaView server failed to start"
    echo "📋 Error output from log:"
    tail -n 10 "${LOG_FILE}" | sed 's/^/    /'
    echo "Check full log: ${LOG_FILE}"
  fi
}

if [[ "${START_PVSERVER}" == "true" ]]; then
  start_pv || true
else
  echo "ℹ️  START_PVSERVER=false - skipping ParaView server"
fi

# ========== Create ready marker ==========
touch /tmp/.container_ready

# ========== Final Status ==========
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ Container Ready!"
echo ""
echo "  SSH Access:     Port 2222 (user: dev)"
if [[ "${START_PVSERVER}" == "true" ]] && [[ "${VOLUME_READY}" == "true" ]]; then
  echo "  ParaView:       Port ${PV_SERVER_PORT}"
fi
echo ""
if [[ "${VOLUME_READY}" == "true" ]]; then
  echo "  Volume Status:  ✅ Initialized"
  echo "  Workspace:      /workspace/"
  echo "  Dependencies:   /workspace/deps/"
  echo "  Logs:           /workspace/logs/"
  echo ""
  echo "  Quick start:"
  echo "    ssh dev@localhost -p 2222"
  echo "    cd /workspace/source"
  echo "    cmake -B ../build -G Ninja"
  echo "    ninja -C ../build"
  echo ""
  echo "  Check ParaView logs:"
  echo "    tail -f /workspace/logs/pvserver_*.log"
else
  echo "  Volume Status:  ⚠️  Not initialized"
  echo ""
  echo "  Initialize with:"
  echo "    docker-compose --profile setup run setup"
fi
echo "════════════════════════════════════════════════════════════"
echo ""

# Keep container running (DO NOT use exec which would replace this process!)
tail -f /dev/null