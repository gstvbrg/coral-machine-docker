#!/usr/bin/env bash
set -euo pipefail

echo "🚀 PORAG Dev Environment Starting"

# ---------- Config via env ----------
: "${REPO_URL:=git@github.com:username/coralMachine.git}"   # your repo (SSH recommended)
: "${REPO_BRANCH:=main}"
: "${SRC_DIR:=/workspace/source}"
: "${BUILD_DIR:=${SRC_DIR}/build}"
: "${PV_BACKEND:=egl}"     # egl | xvfb | none
: "${PV_SERVER_PORT:=11111}"
: "${NV_GPU_ARCH:=}"       # e.g., cc89 for 4090; leave empty for generic
: "${AUTH_KEYS_PATH:=}"    # optional: path to authorized_keys mounted into container

# ParaView server configuration (based on ParaView best practices)
: "${MPI_PROCESSES:=1}"           # Enable parallel processing (set >1 for multi-process)
: "${PV_CONNECT_ID:=random}"      # Security via connect ID (random/false/specific-id)  
: "${PV_MULTI_CLIENTS:=false}"    # Multi-client support for collaboration
: "${PV_FORCE_OFFSCREEN:=true}"   # Performance for headless rendering
# ------------------------------------

# Ensure SSH host keys exist; start sshd
ssh-keygen -A >/dev/null 2>&1 || true
if ! pgrep -x sshd >/dev/null; then
  /usr/sbin/sshd
fi

# Dev user's SSH setup
mkdir -p ~dev/.ssh
chmod 700 ~dev/.ssh
chown -R dev:dev ~dev/.ssh

if [[ -n "${AUTH_KEYS_PATH}" && -f "${AUTH_KEYS_PATH}" ]]; then
  install -m 600 -o dev -g dev "${AUTH_KEYS_PATH}" ~dev/.ssh/authorized_keys
fi

# Helpful: trust GitHub/GitLab for SSH (if using SSH URLs)
sudo -u dev -H bash -lc 'mkdir -p ~/.ssh && touch ~/.ssh/known_hosts && chmod 600 ~/.ssh/known_hosts'
for host in github.com gitlab.com; do
  ssh-keyscan -t rsa "${host}" >> ~dev/.ssh/known_hosts 2>/dev/null || true
done
chown dev:dev ~dev/.ssh/known_hosts

# Make sure workspace is owned by dev
chown -R dev:dev /workspace

# Clone or update source
if [[ -d "${SRC_DIR}/.git" ]]; then
  echo "📦 Updating repo in ${SRC_DIR}"
  sudo -u dev -H bash -lc "git -C '${SRC_DIR}' pull --rebase --autostash && git -C '${SRC_DIR}' submodule update --init --recursive"
else
  echo "📦 Cloning ${REPO_URL} -> ${SRC_DIR}"
  sudo -u dev -H bash -lc "git clone --recursive --branch '${REPO_BRANCH}' '${REPO_URL}' '${SRC_DIR}'"
fi

# ccache setup
sudo -u dev -H bash -lc 'ccache -M 10G || true'
sudo -u dev -H bash -lc 'ccache -s || true'

# Configure & build via CMakePresets if present
if [[ -f "${SRC_DIR}/CMakePresets.json" ]]; then
  if [[ -n "${NV_GPU_ARCH}" ]]; then
    echo "🔧 Configure (gpu-arch preset) with NV_GPU_ARCH=${NV_GPU_ARCH}"
    sudo -u dev -H bash -lc "cd '${SRC_DIR}' && cmake --preset gpu-arch"
    sudo -u dev -H bash -lc "cd '${SRC_DIR}' && cmake --build --preset gpu-arch-relwithdebinfo"
  else
    echo "🔧 Configure (gpu-generic preset)"
    sudo -u dev -H bash -lc "cd '${SRC_DIR}' && cmake --preset gpu-generic"
    sudo -u dev -H bash -lc "cd '${SRC_DIR}' && cmake --build --preset gpu-generic-relwithdebinfo"
  fi
else
  # Fallback direct configure
  echo "🔧 Configure (fallback)"
  mkdir -p "${BUILD_DIR}"
  if [[ -n "${NV_GPU_ARCH}" ]]; then
    sudo -u dev -H bash -lc "cmake -G Ninja -S '${SRC_DIR}' -B '${BUILD_DIR}' \
      -DCMAKE_PREFIX_PATH=/opt/deps \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_CXX_COMPILER=nvc++ \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DCMAKE_CXX_FLAGS='-stdpar -gpu=${NV_GPU_ARCH}'"
  else
    sudo -u dev -H bash -lc "cmake -G Ninja -S '${SRC_DIR}' -B '${BUILD_DIR}' \
      -DCMAKE_PREFIX_PATH=/opt/deps \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_CXX_COMPILER=nvc++ \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DCMAKE_CXX_FLAGS='-stdpar'"
  fi
  sudo -u dev -H bash -lc "ninja -C '${BUILD_DIR}' -j\$(nproc)"
fi

# Start ParaView server with enhanced configuration (always available)
start_pv() {
  if [[ "${PV_BACKEND}" == "none" ]]; then
    echo "ℹ️  PV_BACKEND=none; skipping pvserver."
    return
  fi

  # Build pvserver command and arguments based on configuration
  if [[ "${MPI_PROCESSES}" -gt 1 ]]; then
    PVSERVER_CMD="mpirun -np ${MPI_PROCESSES} /opt/paraview/bin/pvserver"
    echo "🧪 Starting parallel pvserver (${MPI_PROCESSES} processes) on port ${PV_SERVER_PORT}"
  else  
    PVSERVER_CMD="/opt/paraview/bin/pvserver"
    echo "🧪 Starting single-process pvserver on port ${PV_SERVER_PORT}"
  fi

  # Build arguments array
  PVSERVER_ARGS="--server-port=${PV_SERVER_PORT}"
  
  # Security & multi-client configuration
  if [[ "${PV_CONNECT_ID}" != "false" ]]; then
    if [[ "${PV_CONNECT_ID}" == "random" ]]; then
      # Generate random connect ID (4-digit number)
      CONNECT_ID=$((RANDOM % 9000 + 1000))
      echo "🔐 Generated connect ID: ${CONNECT_ID}"
    else
      CONNECT_ID="${PV_CONNECT_ID}"
      echo "🔐 Using connect ID: ${CONNECT_ID}"
    fi
    PVSERVER_ARGS+=" --connect-id=${CONNECT_ID}"
  fi
  
  if [[ "${PV_MULTI_CLIENTS}" == "true" ]]; then
    PVSERVER_ARGS+=" --multi-clients --disable-further-connections"
    echo "👥 Multi-client support enabled"
  fi

  # Performance flags
  if [[ "${PV_FORCE_OFFSCREEN}" == "true" ]]; then
    PVSERVER_ARGS+=" --force-offscreen-rendering"
  fi
  PVSERVER_ARGS+=" --disable-xdisplay-test"

  # Handle display setup for different backends
  if [[ "${PV_BACKEND}" == "xvfb" ]]; then
    echo "🖥️  Starting Xvfb for software rendering"
    Xvfb :99 -screen 0 1024x768x24 & 
    export DISPLAY=:99
  elif [[ "${PV_BACKEND}" == "egl" ]]; then
    echo "🎮 Using EGL for hardware-accelerated headless rendering"
  fi

  # Launch pvserver with full configuration
  echo "▶️  Command: ${PVSERVER_CMD} ${PVSERVER_ARGS}"
  ${PVSERVER_CMD} ${PVSERVER_ARGS} &
}
start_pv

echo "✅ Ready. SSH on port 22 (user: dev). ParaView on ${PV_SERVER_PORT} (if enabled)."
# Drop into an interactive shell if the container is attached
exec sudo -u dev -H zsh -l
