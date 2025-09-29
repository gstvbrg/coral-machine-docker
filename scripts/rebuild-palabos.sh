#!/bin/bash
# Rebuilds Palabos inside the runtime container using the already-installed NVHPC toolchain

set -euo pipefail

# --- Locate repository root to reuse shared logging helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${REPO_ROOT}/lib/common.sh"

# --- Defaults that can be overridden via flags or environment variables
PALABOS_SRC_DEFAULT="${PALABOS_SRC:-/workspace/deps/palabos-hybrid}"
PALABOS_BUILD_DEFAULT="${PALABOS_BUILD_DIR:-/workspace/build/palabos-nvhpc}"
INSTALL_LIB_DIR="${INSTALL_LIB_DIR:-/workspace/deps/lib}"
INSTALL_INCLUDE_DIR="${INSTALL_INCLUDE_DIR:-/workspace/deps/include/palabos}"

# --- Simple argument parser for power users
usage() {
    cat <<USAGE
Usage: $(basename "$0") [--source DIR] [--build DIR]

Rebuilds the Palabos static library with the NVHPC toolchain.
Environment knobs:
  PALABOS_EXTRA_FLAGS   Additional NVHPC flags appended to NVHPC_CXX_FLAGS
  PALABOS_GPU_MEM_MODE  Overrides -gpu=mem:* setting (e.g. managed, separate)
  DISABLE_TBB_BACKEND   If set to 1, adds -D_GLIBCXX_USE_TBB_PAR_BACKEND=0
  PALABOS_SKIP_UPDATE   If set to 1, skip git fetch/pull for existing checkout
  PALABOS_REPO_OVERRIDE Clone/update from an alternate Git remote
USAGE
}

PALABOS_SRC="${PALABOS_SRC_DEFAULT}"
PALABOS_BUILD_DIR="${PALABOS_BUILD_DEFAULT}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            PALABOS_SRC="$2"; shift 2 ;;
        --build)
            PALABOS_BUILD_DIR="$2"; shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            log_error "Unknown argument: $1"
            usage
            exit 1 ;;
    esac
done

# --- Validate prerequisites (env.sh present before we start fetching sources)
ENV_FILE="/workspace/deps/env.sh"
if [[ ! -f "${ENV_FILE}" ]]; then
    log_error "${ENV_FILE} not found. Run the installer bootstrap first."
    exit 1
fi

# --- Ensure Palabos sources exist (clone/update into persistent volume)
ensure_palabos_sources() {
    if ! command -v git >/dev/null 2>&1; then
        log_error "git is required to manage Palabos sources"
        exit 1
    fi
    local repo_url="${PALABOS_REPO_OVERRIDE:-${PALABOS_REPO:-https://github.com/gstvbrg/palabos-hybrid-prerelease.git}}"

    if [[ ! -d "${PALABOS_SRC}" || ! -d "${PALABOS_SRC}/.git" ]]; then
        log_info "Cloning Palabos repository into ${PALABOS_SRC}"
        rm -rf "${PALABOS_SRC}"
        mkdir -p "$(dirname "${PALABOS_SRC}")"
        if ! git clone --recursive "${repo_url}" "${PALABOS_SRC}"; then
            log_error "Failed to clone Palabos repository from ${repo_url}"
            exit 1
        fi
    else
        if [[ "${PALABOS_SKIP_UPDATE:-0}" == "1" ]]; then
            log_info "Skipping Palabos repository update (PALABOS_SKIP_UPDATE=1)"
        else
            log_info "Updating Palabos repository in ${PALABOS_SRC}"
            if git -C "${PALABOS_SRC}" fetch --prune --tags; then
                if ! git -C "${PALABOS_SRC}" pull --ff-only; then
                    log_warn "Palabos repository not fast-forwardable; continuing with existing checkout"
                fi
            else
                log_warn "Unable to fetch Palabos updates; using existing checkout"
            fi
        fi

        if ! git -C "${PALABOS_SRC}" diff --quiet --ignore-submodules HEAD; then
            log_warn "Palabos source tree has local modifications; rebuild will use those changes"
        fi
    fi
}

ensure_palabos_sources

if [[ ! -d "${PALABOS_SRC}" ]]; then
    log_error "Palabos source directory still not available: ${PALABOS_SRC}"
    exit 1
fi

# --- Load NVHPC toolchain environment and echo the compiler we will use
source "${ENV_FILE}"
command -v nvc++ >/dev/null || {
    log_error "nvc++ compiler not available in PATH"
    exit 1
}
log_section "Rebuilding Palabos with $(nvc++ --version | head -n1)"

# --- Construct compiler flag string from env plus optional overrides
EFFECTIVE_FLAGS="${NVHPC_CXX_FLAGS:-}"
if [[ -n "${PALABOS_GPU_MEM_MODE:-}" ]]; then
    EFFECTIVE_FLAGS="${EFFECTIVE_FLAGS} -gpu=mem:${PALABOS_GPU_MEM_MODE}"
fi
if [[ "${DISABLE_TBB_BACKEND:-0}" == "1" ]]; then
    EFFECTIVE_FLAGS="${EFFECTIVE_FLAGS} -D_GLIBCXX_USE_TBB_PAR_BACKEND=0"
fi
if [[ -n "${PALABOS_EXTRA_FLAGS:-}" ]]; then
    EFFECTIVE_FLAGS="${EFFECTIVE_FLAGS} ${PALABOS_EXTRA_FLAGS}"
fi

log_info "Using NVHPC flags: ${EFFECTIVE_FLAGS}"

# --- Prepare clean build directory
log_info "Using source: ${PALABOS_SRC}"
log_info "Using build: ${PALABOS_BUILD_DIR}"
rm -rf "${PALABOS_BUILD_DIR}"
mkdir -p "${PALABOS_BUILD_DIR}"

# --- Configure with CMake using nvc++
pushd "${PALABOS_BUILD_DIR}" >/dev/null
cmake "${PALABOS_SRC}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}" \
    -DCMAKE_CXX_COMPILER=nvc++ \
    -DCMAKE_C_COMPILER=nvc \
    -DCMAKE_CXX_STANDARD="${CMAKE_CXX_STANDARD:-20}" \
    -DCMAKE_CXX_FLAGS="${EFFECTIVE_FLAGS}" \
    -DENABLE_MPI=OFF \
    -DPALABOS_ENABLE_MPI=OFF \
    -DPALABOS_ENABLE_CUDA=OFF \
    -DBUILD_HDF5=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF

# --- Build the static library target
log_info "Building libpalabos.a"
ninja palabos

# --- Install library artifact
log_info "Installing library to ${INSTALL_LIB_DIR}"
mkdir -p "${INSTALL_LIB_DIR}"
NEW_LIB="$(find . -name libpalabos.a -print -quit)"
if [[ -z "${NEW_LIB}" ]]; then
    log_error "libpalabos.a not produced"
    exit 1
fi
cp "${NEW_LIB}" "${INSTALL_LIB_DIR}/"

# --- Install headers (rsync keeps tree clean)
log_info "Installing headers to ${INSTALL_INCLUDE_DIR}"
mkdir -p "${INSTALL_INCLUDE_DIR}"
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "${PALABOS_SRC}/src/" "${INSTALL_INCLUDE_DIR}/"
    rsync -a --delete "${PALABOS_SRC}/externalLibraries/" "${INSTALL_INCLUDE_DIR}/externalLibraries/"
else
    rm -rf "${INSTALL_INCLUDE_DIR}"/*
    cp -R "${PALABOS_SRC}/src/." "${INSTALL_INCLUDE_DIR}/"
    cp -R "${PALABOS_SRC}/externalLibraries/." "${INSTALL_INCLUDE_DIR}/externalLibraries/"
fi

popd >/dev/null

log_success "Palabos rebuild complete"
log_info "Library: ${INSTALL_LIB_DIR}/libpalabos.a"
