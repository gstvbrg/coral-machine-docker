#!/usr/bin/env bash
# RESILIENT STARTUP SCRIPT - Container stays alive even if builds fail
# Key change: Removed 'set -e' which was killing container on any error
set -uo pipefail

echo "🚀 PORAG Dev Environment Starting"

# ---------- PATH Setup (handled via Dockerfile ENV and /etc/profile.d) ----------

# ---------- Config via env ----------
: "${REPO_URL:=https://github.com/gstvbrg/coral-machine.git}"   # your repo (HTTPS for public access)
: "${REPO_BRANCH:=main}"
: "${SRC_DIR:=/workspace/source}"
: "${BUILD_DIR:=${SRC_DIR}/build}"
: "${PV_BACKEND:=egl}"              # egl | xvfb | none
: "${PV_SERVER_PORT:=11111}"
: "${NV_GPU_ARCH:=}"                # e.g., cc89 for 4090; leave empty for generic
: "${AUTH_KEYS_PATH:=}"             # optional: path to authorized_keys mounted into container

# New control flags for optional operations
: "${AUTO_CLONE:=true}"             # Auto clone/update git repo
: "${AUTO_BUILD:=false}"            # Auto build project (default OFF for stability)
: "${START_PVSERVER:=true}"         # Start ParaView server
: "${FAIL_ON_BUILD_ERROR:=false}"   # Exit if build fails (default: keep running)

# ParaView server configuration
: "${MPI_PROCESSES:=1}"             # Enable parallel processing (set >1 for multi-process)
: "${PV_CONNECT_ID:=random}"        # Security via connect ID (random/false/specific-id)  
: "${PV_MULTI_CLIENTS:=false}"      # Multi-client support for collaboration
: "${PV_FORCE_OFFSCREEN:=true}"     # Performance for headless rendering

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

# ========== User & Permission Setup ==========
echo "🔑 Setting up SSH access..."
mkdir -p ~dev/.ssh || true
chmod 700 ~dev/.ssh 2>/dev/null || true
chown -R dev:dev ~dev/.ssh 2>/dev/null || true

# Copy authorized keys if provided
if [[ -n "${AUTH_KEYS_PATH}" && -f "${AUTH_KEYS_PATH}" ]]; then
  install -m 600 -o dev -g dev "${AUTH_KEYS_PATH}" ~dev/.ssh/authorized_keys || \
    echo "⚠️  Failed to install authorized_keys"
fi

# Trust common git hosts with modern key types
sudo -u dev -H bash -lc 'mkdir -p ~/.ssh && touch ~/.ssh/known_hosts && chmod 600 ~/.ssh/known_hosts' || true
for host in github.com gitlab.com; do
  ssh-keyscan -t rsa,ecdsa,ed25519 "${host}" >> ~dev/.ssh/known_hosts 2>/dev/null || true
done
chown dev:dev ~dev/.ssh/known_hosts 2>/dev/null || true

# Ensure workspace exists and baseline ownership without recursive chown
install -d -o dev -g dev /workspace 2>/dev/null || true
# Fix ownership only for top-level entries not owned by dev (fast path)
if command -v find >/dev/null 2>&1; then
  find /workspace -mindepth 1 -maxdepth 1 ! -user dev -exec chown -R dev:dev {} + 2>/dev/null || true
fi

# ========== Optional: Git Clone/Update ==========
if [[ "${AUTO_CLONE}" == "true" ]]; then
  echo "📦 Managing source repository..."
  if [[ -d "${SRC_DIR}/.git" ]]; then
    echo "  Updating existing repo in ${SRC_DIR}"
    if sudo -u dev -H bash -lc "git -C '${SRC_DIR}' pull --rebase --autostash && git -C '${SRC_DIR}' submodule update --init --recursive"; then
      echo "  ✅ Repository updated"
    else
      echo "  ⚠️  Repository update failed - using existing code"
    fi
  else
    echo "  Cloning ${REPO_URL} -> ${SRC_DIR}"
    if sudo -u dev -H bash -lc "git clone --recursive --branch '${REPO_BRANCH}' '${REPO_URL}' '${SRC_DIR}'"; then
      echo "  ✅ Repository cloned"
    else
      echo "  ⚠️  Repository clone failed - no source code available"
    fi
  fi
else
  echo "ℹ️  AUTO_CLONE=false - skipping git operations"
fi

# ========== Optional: ccache Setup ==========
echo "⚙️  Configuring ccache..."
sudo -u dev -H bash -lc 'ccache -M 10G 2>/dev/null || true'
sudo -u dev -H bash -lc 'ccache -s 2>/dev/null || true'

# ========== Optional: Build Project ==========
if [[ "${AUTO_BUILD}" == "true" ]] && [[ -d "${SRC_DIR}" ]]; then
  echo "🔧 Attempting to build project..."
  
  # Check if source directory has CMakeLists.txt
  if [[ ! -f "${SRC_DIR}/CMakeLists.txt" ]]; then
    echo "  ⚠️  No CMakeLists.txt found - skipping build"
  else
    # Try to determine best compiler
    if command -v nvc++ >/dev/null 2>&1; then
      CXX_COMPILER="nvc++"
      echo "  Using NVIDIA HPC compiler (nvc++)"
    elif command -v g++ >/dev/null 2>&1; then
      CXX_COMPILER="g++"
      echo "  Using GNU compiler (g++)"
    else
      CXX_COMPILER=""
      echo "  ⚠️  No suitable C++ compiler found"
    fi
    
    if [[ -n "${CXX_COMPILER}" ]]; then
      mkdir -p "${BUILD_DIR}"
      
      # Build CMake command
      CMAKE_CMD="cmake -G Ninja -S '${SRC_DIR}' -B '${BUILD_DIR}'"
      CMAKE_CMD="${CMAKE_CMD} -DCMAKE_PREFIX_PATH=/opt/deps"
      CMAKE_CMD="${CMAKE_CMD} -DCMAKE_BUILD_TYPE=RelWithDebInfo"
      CMAKE_CMD="${CMAKE_CMD} -DCMAKE_CXX_COMPILER=${CXX_COMPILER}"
      CMAKE_CMD="${CMAKE_CMD} -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
      CMAKE_CMD="${CMAKE_CMD} -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
      
      # Add GPU flags for nvc++
      if [[ "${CXX_COMPILER}" == "nvc++" ]]; then
        if [[ -n "${NV_GPU_ARCH}" ]]; then
          CMAKE_CMD="${CMAKE_CMD} -DCMAKE_CXX_FLAGS='-stdpar -gpu=${NV_GPU_ARCH}'"
        else
          CMAKE_CMD="${CMAKE_CMD} -DCMAKE_CXX_FLAGS='-stdpar'"
        fi
      fi
      
      # Run cmake configuration
      echo "  Running: ${CMAKE_CMD}"
      if sudo -u dev -H bash -lc "${CMAKE_CMD}"; then
        echo "  ✅ CMake configuration successful"
        
        # Try to build
        if sudo -u dev -H bash -lc "ninja -C '${BUILD_DIR}' -j\$(nproc)"; then
          echo "  ✅ Build successful!"
        else
          echo "  ⚠️  Build failed - container continues running"
          [[ "${FAIL_ON_BUILD_ERROR}" == "true" ]] && exit 1
        fi
      else
        echo "  ⚠️  CMake configuration failed - container continues running"
        [[ "${FAIL_ON_BUILD_ERROR}" == "true" ]] && exit 1
      fi
    fi
  fi
else
  echo "ℹ️  AUTO_BUILD=false or no source - skipping build"
fi

# ========== Optional: Start ParaView Server ==========
start_pv() {
  if [[ "${PV_BACKEND}" == "none" ]]; then
    echo "ℹ️  PV_BACKEND=none; skipping pvserver."
    return 0
  fi

  # Check if pvserver exists
  if ! command -v pvserver >/dev/null 2>&1; then
    echo "⚠️  pvserver not found - skipping ParaView server"
    return 1
  fi

  # Build pvserver command
  if [[ "${MPI_PROCESSES}" -gt 1 ]]; then
    PVSERVER_CMD="mpirun --allow-run-as-root -np ${MPI_PROCESSES} pvserver"
    echo "🧪 Starting parallel pvserver (${MPI_PROCESSES} processes) on port ${PV_SERVER_PORT}"
  else  
    PVSERVER_CMD="pvserver"
    echo "🧪 Starting single-process pvserver on port ${PV_SERVER_PORT}"
  fi

  # Build arguments
  PVSERVER_ARGS="--server-port=${PV_SERVER_PORT}"
  
  # Security & multi-client configuration
  if [[ "${PV_CONNECT_ID}" != "false" ]]; then
    if [[ "${PV_CONNECT_ID}" == "random" ]]; then
      CONNECT_ID=$((RANDOM % 9000 + 1000))
      echo "🔐 Generated connect ID: ${CONNECT_ID}"
    else
      CONNECT_ID="${PV_CONNECT_ID}"
      echo "🔐 Using connect ID: ${CONNECT_ID}"
    fi
    PVSERVER_ARGS="${PVSERVER_ARGS} --connect-id=${CONNECT_ID}"
  fi
  
  if [[ "${PV_MULTI_CLIENTS}" == "true" ]]; then
    PVSERVER_ARGS="${PVSERVER_ARGS} --multi-clients --disable-further-connections"
    echo "👥 Multi-client support enabled"
  fi

  # Performance flags
  if [[ "${PV_FORCE_OFFSCREEN}" == "true" ]]; then
    PVSERVER_ARGS="${PVSERVER_ARGS} --force-offscreen-rendering"
  fi
  PVSERVER_ARGS="${PVSERVER_ARGS} --disable-xdisplay-test"

  # Handle display setup
  if [[ "${PV_BACKEND}" == "xvfb" ]]; then
    echo "🖥️  Starting Xvfb for software rendering"
    Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 & 
    export DISPLAY=:99
  elif [[ "${PV_BACKEND}" == "egl" ]]; then
    echo "🎮 Using EGL for hardware-accelerated headless rendering"
  fi

  # Launch pvserver (as dev user) in background and report status
  echo "▶️  Command: ${PVSERVER_CMD} ${PVSERVER_ARGS}"
  sudo -u dev -H bash -lc "${PVSERVER_CMD} ${PVSERVER_ARGS} >/dev/null 2>&1 &"
  if [[ $? -eq 0 ]]; then
    echo "✅ ParaView server started"
  else
    echo "⚠️  ParaView server failed to start"
  fi
}

if [[ "${START_PVSERVER}" == "true" ]]; then
  start_pv || true
else
  echo "ℹ️  START_PVSERVER=false - skipping ParaView server"
fi

# ========== Final Status & Keep Alive ==========
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ Container Ready!"
echo "  SSH:      Port 22 (user: dev)"
echo "  ParaView: Port ${PV_SERVER_PORT} (if enabled)"
echo "  "
echo "  To build manually:"
echo "    docker exec -it <container> bash"
echo "    cd /workspace/source"
echo "    cmake -B build && ninja -C build"
echo "════════════════════════════════════════════════════════════"
echo ""

# Keep container running (DO NOT use exec which would replace this process!)
# This ensures the container stays alive even if SSH or other services fail
tail -f /dev/null