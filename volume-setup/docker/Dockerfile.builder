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
    # Download tools
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
    libhdf5-dev \
    # Runtime for testing
    xvfb \
    # Utilities
    sudo \
    rsync \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create build user with same UID as volume (1000)
RUN useradd -m -u 1000 -g 1000 -s /bin/bash builder \
    && echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder

# Copy setup scripts into image
# This makes the image self-contained for RunPod deployment
COPY . /opt/volume-setup/

# Ensure scripts are executable
RUN chmod +x /opt/volume-setup/*.sh \
    && chmod +x /opt/volume-setup/installers/*.sh \
    && chown -R builder:builder /opt/volume-setup

# Create workspace mount points
RUN mkdir -p /workspace/deps /workspace/source /workspace/build \
    && chown -R builder:builder /workspace

WORKDIR /opt/volume-setup

# Run as builder user by default (can override with --user root if needed)
USER builder

# Default command runs full setup
CMD ["./setup.sh"]