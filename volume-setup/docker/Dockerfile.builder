# Builder image for populating the Coral Machine volume
# Contains all build tools needed to compile dependencies
# This image is only used during setup, not for runtime

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install all build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core build tools
    build-essential \
    cmake \
    ninja-build \
    ccache \
    pkg-config \
    # Version control
    git \
    git-lfs \
    # Download tools (aria2 for RunPod optimization)
    aria2 \
    wget \
    curl \
    ca-certificates \
    # Python (for some build scripts)
    python3 \
    python3-pip \
    # Automation tools
    expect \
    # Development headers (will be copied to volume)
    libeigen3-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libx11-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxi-dev \
    libxext-dev \
    libtbb-dev \
    # Runtime for testing
    xvfb \
    # SSH for host key generation during setup
    openssh-server \
    # Utilities
    sudo \
    rsync \
    pv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create build user with same UID as volume (1000)
RUN groupadd -g 1000 builder \
    && useradd -m -u 1000 -g 1000 -s /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder

# Copy setup assets (includes authorized_keys) into image
# This makes the image self-contained for RunPod deployment
COPY . /opt/volume-setup/

# Fix line endings and ensure scripts are executable
# This is critical for Windows development where files may have CRLF endings
RUN find /opt/volume-setup -type f \( -name "*.sh" -o -name "*.env" -o -name "config.env" -o -name "Makefile" \) \
    -exec sed -i 's/\r$//' {} \; \
    && chmod +x /opt/volume-setup/*.sh \
    && chmod +x /opt/volume-setup/installers/*.sh \
    && if [ -f /opt/volume-setup/authorized_keys ]; then chmod 600 /opt/volume-setup/authorized_keys; fi \
    && chown -R builder:builder /opt/volume-setup

# Create workspace mount points with organized output structure
RUN mkdir -p /workspace/deps /workspace/source /workspace/build \
    /workspace/output/vtk /workspace/output/data /workspace/output/images \
    /workspace/output/checkpoints /workspace/output/logs \
    && chown -R builder:builder /workspace

WORKDIR /opt/volume-setup

# Run as root for setup (builder needs to install packages)
# This is safe because this container is only used for initial setup
# USER builder  # Commented out - run as root for package installation

# Default command runs full setup
CMD ["./setup.sh"]