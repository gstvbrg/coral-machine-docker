#!/bin/bash
# Bootstraps the GPU validation volume by reusing the standard installer stack

set -euo pipefail

# --- Resolve repository paths and import shared helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SETUP_ROOT}/lib/common.sh"
source "${SETUP_ROOT}/config.env"

log_section "GPU Validation Bootstrap"

# --- Allow optional flag overrides without mutating repo defaults
FLAGS_OVERRIDE_FILE="${SCRIPT_DIR}/flags-override.env"
if [[ -f "${FLAGS_OVERRIDE_FILE}" ]]; then
    log_info "Applying flag overrides from ${FLAGS_OVERRIDE_FILE}"
    # shellcheck source=/dev/null
    source "${FLAGS_OVERRIDE_FILE}"
fi

# --- Enforce stdpar GPU usage and block PSTL/TBB interception
EXTRA_FLAGS="-D_GLIBCXX_USE_TBB_PAR_BACKEND=0 -Minfo=stdpar"
export NVHPC_CXX_FLAGS="${NVHPC_CXX_FLAGS:-} ${EXTRA_FLAGS}"
export INSTALL_TBB=${INSTALL_TBB:-false}
unset CPLUS_INCLUDE_PATH || true
log_info "Effective NVHPC flags: ${NVHPC_CXX_FLAGS}"

# --- Verify /workspace is mounted so installers can populate it
WORKSPACE_DIR="/workspace"
if [[ ! -d "${WORKSPACE_DIR}" ]]; then
    log_error "${WORKSPACE_DIR} is missing. Mount a Docker volume to /workspace before running."
    exit 1
fi

# --- Run the standard installer chain to populate the sandbox volume
log_info "Preparing build environment"
"${SETUP_ROOT}/installers/00-prep.sh"

log_info "Installing NVIDIA HPC SDK"
"${SETUP_ROOT}/installers/01-compilers.sh"

log_info "Installing Palabos core libraries"
"${SETUP_ROOT}/installers/03-core-libraries.sh"

# --- Summarize outcome for quick verification
if [[ -f "${WORKSPACE_DIR}/deps/env.sh" ]]; then
    log_success "Bootstrap complete: toolchain available in ${WORKSPACE_DIR}/deps"
else
    log_error "Bootstrap finished without creating ${WORKSPACE_DIR}/deps/env.sh"
    exit 1
fi
