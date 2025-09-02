# Remote GPU Dev Workstation for Coral Morphogenesis
# - NVHPC + OpenMPI + SSH + ParaView (EGL or Xvfb fallback)
# - Non-root "dev" user for builds & SSH logins
# - Preserves ccache & build dirs in /workspace (mount a volume there)

FROM nvcr.io/nvidia/nvhpc:24.7-devel-cuda12.5-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-lc"]

# Fix GPG signature issues by reinstalling keyring and certs
RUN apt-get clean && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/* && \
    apt-get update --allow-insecure-repositories && \
    apt-get install -y --allow-unauthenticated --reinstall --no-install-recommends \
    ca-certificates ubuntu-keyring curl gnupg && \
    apt-get clean && rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*

# Base packages & headless graphics bits
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo openssh-server \
    cmake ninja-build ccache git zsh tmux curl wget rsync unzip \
    netcat-openbsd \
    libopenmpi-dev openmpi-bin \
    # EGL headless (uses host NVIDIA driver libs), X fallback bits:
    libegl1 libgl1 libxrender1 libxkbcommon0 \
    xvfb mesa-utils \
    tini \
 && rm -rf /var/lib/apt/lists/*

# Non-root user for dev work
RUN groupadd -g 1000 dev \
 && useradd -m -u 1000 -g 1000 -s /bin/zsh dev \
 && usermod -aG sudo dev \
 && echo "dev ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/dev

# SSH daemon baseline
RUN mkdir -p /var/run/sshd \
 && sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's@^#\?AuthorizedKeysFile .*@AuthorizedKeysFile .ssh/authorized_keys@' /etc/ssh/sshd_config

# Workspace & deps dirs
RUN mkdir -p /workspace /opt/deps /opt/paraview \
 && chown -R dev:dev /workspace /opt/deps /opt/paraview

# Install ParaView (required for VTK visualization workflow)
RUN echo "Installing ParaView server (required dependency)" && \
    ARCH="$(dpkg --print-architecture)"; \
    PV_URL="https://www.paraview.org/files/v5.12/ParaView-5.12.0-egl-MPI-Linux-Python3.10-${ARCH}.tar.gz"; \
    # Map Debian arch to ParaView naming
    if [ "$ARCH" = "amd64" ]; then PV_URL="${PV_URL/amd64/x86_64}"; fi; \
    wget -qO /tmp/paraview.tar.gz "$PV_URL" && \
    tar -xzf /tmp/paraview.tar.gz -C /opt/paraview --strip-components=1 && \
    rm /tmp/paraview.tar.gz && \
    # Verify installation
    test -x /opt/paraview/bin/pvserver || (echo "ParaView installation failed" && exit 1)

# Phase 2: geometry-central (mesh processing library)
# Small dependency to validate C++ build toolchain
WORKDIR /tmp/build

RUN echo "🔧 Building geometry-central..." && \
    git clone --recursive --depth 1 \
    https://github.com/nmwsharp/geometry-central.git && \
    cd geometry-central && \
    mkdir build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/opt/deps \
             -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_CXX_COMPILER=nvc++ && \
    make -j$(nproc) install && \
    echo "✅ geometry-central installed successfully" && \
    cd / && rm -rf /tmp/build/geometry-central

WORKDIR /workspace

# Environment
ENV PATH="/opt/paraview/bin:${PATH}"
ENV CMAKE_PREFIX_PATH="/opt/deps"
ENV CCACHE_DIR="/workspace/.ccache" CCACHE_MAXSIZE="10G"
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# Startup
COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh \
 && chown dev:dev /usr/local/bin/startup.sh

WORKDIR /workspace

# Ports: SSH & ParaView
EXPOSE 22 11111

# Healthcheck: ParaView server availability (pvserver always installed)
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=10 \
  CMD nc -z 127.0.0.1 ${PV_SERVER_PORT:-11111}

# Use tini as PID 1
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/startup.sh"]
