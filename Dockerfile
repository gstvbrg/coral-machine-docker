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

# Base packages & headless graphics bits + DEV TOOLS
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo openssh-server \
    cmake ninja-build ccache git git-lfs zsh tmux curl wget rsync unzip \
    # Development tools (ADDED FOR BETTER DEV EXPERIENCE)
    vim nano htop ncdu tree jq \
    # Network debugging
    netcat-openbsd iputils-ping net-tools \
    libeigen3-dev \
    libgl1-mesa-dev libglfw3-dev libglm-dev \
    # EGL headless (uses host NVIDIA driver libs), X fallback bits:
    libegl1 libgl1 libopengl0 libxrender1 libxkbcommon0 \
    # GLX runtime libraries for ParaView compatibility
    libx11-6 libxext6 libsm6 libice6 libxcursor1 \
    xvfb mesa-utils \
    tini \
 && rm -rf /var/lib/apt/lists/*

# Non-root user for dev work
RUN groupadd -g 1000 dev \
 && useradd -m -u 1000 -g 1000 -s /bin/zsh dev \
 && usermod -aG sudo dev \
 && echo "dev ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/dev

# SSH daemon configuration (secure defaults with PAM environment support)
RUN mkdir -p /var/run/sshd \
 && sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's@^#\?AuthorizedKeysFile .*@AuthorizedKeysFile .ssh/authorized_keys@' /etc/ssh/sshd_config \
 && sed -i 's/^#\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?UsePAM .*/UsePAM yes/' /etc/ssh/sshd_config \
 && echo "PermitUserEnvironment yes" >> /etc/ssh/sshd_config

# Workspace & deps dirs
RUN mkdir -p /workspace /opt/deps /opt/paraview \
 && chown -R dev:dev /workspace /opt/deps /opt/paraview

# CRITICAL FIX: Set up environment variables globally
# This ensures ALL sessions (SSH, docker exec, etc) get correct paths
ENV PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/bin:${PATH}"
ENV PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/comm_libs/mpi/bin:${PATH}"
ENV PATH="/opt/paraview/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/lib:${LD_LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/math_libs/lib64:${LD_LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/cuda/lib64:${LD_LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/opt/paraview/lib:${LD_LIBRARY_PATH}"
# Fix NVIDIA MPI paths to prevent missing help file errors
ENV OPAL_PREFIX="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/comm_libs/12.5/hpcx/hpcx-2.19/ompi"
ENV OMPI_MCA_orte_tmpdir_base="/tmp"
ENV CMAKE_PREFIX_PATH="/opt/deps"
ENV PALABOS_ROOT="/opt/deps/palabos-hybrid"
ENV CCACHE_DIR="/workspace/.ccache"
ENV CCACHE_MAXSIZE="10G"
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
# ParaView plugin path
ENV PV_PLUGIN_PATH="/opt/paraview/lib/paraview-6.0/plugins"
ENV NVIDIA_VISIBLE_DEVICES="all"
ENV NVIDIA_DRIVER_CAPABILITIES="compute,utility,graphics"

# Create /etc/environment for PAM (SSH and su commands will get these)
RUN echo 'PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/bin:/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/comm_libs/mpi/bin:/opt/paraview/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' > /etc/environment && \
    echo 'LD_LIBRARY_PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/lib:/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/math_libs/lib64:/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/cuda/lib64:/opt/paraview/lib"' >> /etc/environment && \
    echo 'CMAKE_PREFIX_PATH="/opt/deps"' >> /etc/environment && \
    echo 'PALABOS_ROOT="/opt/deps/palabos-hybrid"' >> /etc/environment && \
    echo 'OPAL_PREFIX="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/comm_libs/12.5/hpcx/hpcx-2.19/ompi"' >> /etc/environment && \
    echo 'OMPI_MCA_orte_tmpdir_base="/tmp"' >> /etc/environment && \
    echo 'CCACHE_DIR="/workspace/.ccache"' >> /etc/environment && \
    echo 'CCACHE_MAXSIZE="10G"' >> /etc/environment

# Create profile script for interactive shells (supplements /etc/environment)
RUN echo 'export PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/bin:$PATH"' >> /etc/profile.d/coral-env.sh && \
    echo 'export PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/comm_libs/mpi/bin:$PATH"' >> /etc/profile.d/coral-env.sh && \
    echo 'export PATH="/opt/paraview/bin:$PATH"' >> /etc/profile.d/coral-env.sh && \
    echo 'export LD_LIBRARY_PATH="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/compilers/lib:$LD_LIBRARY_PATH"' >> /etc/profile.d/coral-env.sh && \
    echo 'export CMAKE_PREFIX_PATH="/opt/deps"' >> /etc/profile.d/coral-env.sh && \
    echo 'export PALABOS_ROOT="/opt/deps/palabos-hybrid"' >> /etc/profile.d/coral-env.sh && \
    echo 'export OPAL_PREFIX="/opt/nvidia/hpc_sdk/Linux_x86_64/24.7/comm_libs/12.5/hpcx/hpcx-2.19/ompi"' >> /etc/profile.d/coral-env.sh && \
    echo 'export OMPI_MCA_orte_tmpdir_base="/tmp"' >> /etc/profile.d/coral-env.sh && \
    chmod +x /etc/profile.d/coral-env.sh

# Make zsh load system profile (for dev user's zsh)
RUN mkdir -p /etc/zsh && \
    echo '# Load system profile for environment setup' > /etc/zsh/zprofile && \
    echo '[ -r /etc/profile ] && . /etc/profile' >> /etc/zsh/zprofile

# Install ParaView 6.0.0 with MPI support
RUN echo "Installing ParaView 6.0.0 with MPI support" && \
    ARCH="$(dpkg --print-architecture)"; \
    # ParaView 6.0.0 MPI build
    if [ "$ARCH" = "amd64" ]; then \
        PV_URL="https://www.paraview.org/files/v6.0/ParaView-6.0.0-MPI-Linux-Python3.12-x86_64.tar.gz"; \
    else \
        PV_URL="https://www.paraview.org/files/v6.0/ParaView-6.0.0-MPI-Linux-Python3.9-${ARCH}.tar.gz"; \
    fi; \
    # Validate URL exists before download
    echo "Validating ParaView download URL..." && \
    wget -q --spider "$PV_URL" || (echo "ParaView URL not accessible: $PV_URL" && exit 1) && \
    echo "Downloading from: $PV_URL" && \
    wget -qO /tmp/paraview.tar.gz "$PV_URL" || (echo "Failed to download ParaView" && exit 1) && \
    echo "Extracting ParaView..." && \
    tar -xzf /tmp/paraview.tar.gz -C /opt/paraview --strip-components=1 && \
    rm /tmp/paraview.tar.gz && \
    # Verify installation
    test -x /opt/paraview/bin/pvserver || (echo "ParaView installation failed" && exit 1) && \
    echo "ParaView 6.0.0 installed successfully"

# Validate ParaView installation
RUN echo "Validating ParaView installation..." && \
    /opt/paraview/bin/pvserver --version && \
    echo "✅ ParaView 6.0.0 installation validated"

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
             -DCMAKE_CXX_COMPILER=g++ \
             -DCMAKE_CXX_STANDARD=17 \
             -DCMAKE_VERBOSE_MAKEFILE=ON && \
    make -j$(nproc) install && \
    echo "✅ geometry-central installed successfully" && \
    cd / && rm -rf /tmp/build/geometry-central

WORKDIR /workspace

# Phase 4: Polyscope (optional visualization)
WORKDIR /tmp/build

RUN echo "🎨 Building Polyscope (optional)..." && \
    mkdir -p /tmp/build && cd /tmp/build && \
    git clone --recursive --depth 1 https://github.com/nmwsharp/polyscope.git && \
    cd polyscope && \
    mkdir -p build && cd build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/opt/deps \
             -DCMAKE_BUILD_TYPE=Release \
             -DPOLYSCOPE_BACKEND=OPENGL3_GLFW \
             -DPOLYSCOPE_ENABLE_RENDER_BACKEND_OPENGL3=ON && \
    make -j$(nproc) install && \
    echo "✅ Polyscope installed" || ( \
      echo "⚠️  Polyscope install not found; vendoring headers only" && \
      cd .. && mkdir -p /opt/deps/include && cp -r include/polyscope /opt/deps/include/ && \
      IMGUI_DIR=$(dirname $(find . -type f -name imgui.h | head -n1)) && \
      mkdir -p /opt/deps/include/imgui && cp -r ${IMGUI_DIR}/* /opt/deps/include/imgui/ || true \
    ); \
    # Also vendor implot headers if present
    IPLOT_DIR=$(dirname $(find /tmp/build/polyscope -type f -name implot.h | head -n1)) && \
    if [ -n "$IPLOT_DIR" ]; then mkdir -p /opt/deps/include/implot && cp -r ${IPLOT_DIR}/* /opt/deps/include/implot/; fi || true

WORKDIR /workspace

# Phase 3: Palabos-hybrid (core simulation engine)
# Build with NVHPC, CUDA, and MPI enabled
WORKDIR /tmp/build

RUN echo "🧮 Building Palabos-hybrid (this will take a while)..." && \
    mkdir -p /tmp/build && cd /tmp/build && \
    git clone --depth 1 https://github.com/gstvbrg/palabos-hybrid-prerelease.git palabos-hybrid && \
    cd palabos-hybrid && \
    # Disable building anything under examples/ by commenting out add_subdirectory calls
    sed -i -E 's|^[[:space:]]*add_subdirectory[[:space:]]*\([[:space:]]*examples/|# DISABLED: &|g' CMakeLists.txt && \
    rm -rf build && mkdir -p build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
             -DCMAKE_CXX_COMPILER=g++ \
             -DCMAKE_CXX_STANDARD=20 \
             -DCMAKE_CUDA_COMPILER=nvcc \
             -DPALABOS_ENABLE_MPI=ON \
             -DPALABOS_ENABLE_CUDA=ON \
             -DBUILD_HDF5=OFF \
             -DBUILD_EXAMPLES=OFF \
             -DBUILD_TESTING=OFF \
             -DPALABOS_BUILD_EXAMPLES=OFF \
             -DPALABOS_BUILD_TUTORIALS=OFF \
             -DPALABOS_BUILD_TESTS=OFF \
             -DCUDA_ARCH="sm_75;sm_80;sm_86;sm_89" && \
    # Build Palabos-hybrid library
    make -j$(nproc) palabos && \
    # Install in expected structure for our CMakeLists.txt
    cd .. && \
    mkdir -p /opt/deps/palabos-hybrid/include /opt/deps/palabos-hybrid/lib && \
    # Copy headers (preserving directory structure)
    cp -r src /opt/deps/palabos-hybrid/include/ && \
    cp -r externalLibraries /opt/deps/palabos-hybrid/include/ && \
    # Copy the built library
    find build -name "libpalabos.a" -exec cp {} /opt/deps/palabos-hybrid/lib/ \; && \
    # Verify installation
    test -f /opt/deps/palabos-hybrid/lib/libpalabos.a || (echo "ERROR: libpalabos.a not found!" && exit 1) && \
    echo "✅ Palabos-hybrid installed to /opt/deps/palabos-hybrid" && \
    echo "   Headers: /opt/deps/palabos-hybrid/include/{src,externalLibraries}" && \
    echo "   Library: /opt/deps/palabos-hybrid/lib/libpalabos.a" && \
    cd / && rm -rf /tmp/build/palabos-hybrid

WORKDIR /workspace

# Note: Environment variables already set earlier in Dockerfile for better layer caching

# Setup dev user configuration
USER dev
RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
    touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && \
    # Setup shells for proper environment loading
    # zsh (primary shell)
    echo '# Custom prompt' >> ~/.zshrc && \
    echo 'export PS1="%n@coral-dev %~ %# "' >> ~/.zshrc && \
    # bash (backup/compatibility)
    echo '# Ensure profile is loaded' >> ~/.bashrc && \
    echo '[ -r /etc/profile ] && . /etc/profile' >> ~/.bashrc && \
    # Setup vim
    echo 'syntax on' >> ~/.vimrc && \
    echo 'set number' >> ~/.vimrc && \
    echo 'set autoindent' >> ~/.vimrc && \
    echo 'set tabstop=4' >> ~/.vimrc && \
    echo 'set shiftwidth=4' >> ~/.vimrc && \
    echo 'set expandtab' >> ~/.vimrc

USER root

# COPY OPERATIONS GO LAST TO PRESERVE BUILD CACHE!
# Copy authorized_keys if provided (optional)
COPY --chown=dev:dev authorized_keys* /tmp/
RUN if [ -f /tmp/authorized_keys ]; then \
        cp /tmp/authorized_keys /home/dev/.ssh/authorized_keys && \
        chmod 600 /home/dev/.ssh/authorized_keys && \
        chown dev:dev /home/dev/.ssh/authorized_keys; \
    fi && \
    rm -f /tmp/authorized_keys*

# Copy startup script LAST (most likely to change)
COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh && \
    chown root:root /usr/local/bin/startup.sh

WORKDIR /workspace

# Ports: SSH & ParaView
EXPOSE 22 11111

# Healthcheck: SSH availability (more critical than ParaView)
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=10 \
  CMD nc -z localhost 22 || exit 1

# Use tini as PID 1
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/usr/local/bin/startup.sh"]
