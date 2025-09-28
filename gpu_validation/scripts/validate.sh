#!/bin/bash
# Runs GPU offload validation for stdpar and minimal Palabos workloads

set -euo pipefail

# --- Resolve repository paths and ensure environment is loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_DIR="/workspace"

if [[ ! -f "${WORKSPACE_DIR}/deps/env.sh" ]]; then
    echo "env.sh missing at ${WORKSPACE_DIR}/deps/env.sh. Run bootstrap first." >&2
    exit 1
fi

# shellcheck disable=SC1091
auth_source() {
    source "${WORKSPACE_DIR}/deps/env.sh"
}
auth_source

# --- Parse CLI overrides (default cc89, mem:separate)
GPU_ARCH="cc89"
MEM_MODE="separate"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --gpu-arch)
            GPU_ARCH="$2"; shift 2 ;;
        --mem-mode)
            MEM_MODE="$2"; shift 2 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1 ;;
    esac
done

echo "=== GPU Validation Suite ==="
echo "GPU Architecture : ${GPU_ARCH}"
echo "Memory Mode      : ${MEM_MODE}"

BUILD_ROOT="${WORKSPACE_DIR}/validation-build"
mkdir -p "${BUILD_ROOT}"

# --- Test 1: stdpar transform/reduce sanity check
STD_PAR_SRC="${SETUP_ROOT}/gpu_validation/tests/stdpar_test.cpp"
STD_PAR_BIN="${BUILD_ROOT}/stdpar_test"

cp "${STD_PAR_SRC}" "${BUILD_ROOT}/"

STD_FLAGS=(
    -stdpar=gpu
    "-gpu=${GPU_ARCH}"
    "-gpu=mem:${MEM_MODE}"
    -D_GLIBCXX_USE_TBB_PAR_BACKEND=0
    -Minfo=stdpar
    -O3
    -DNDEBUG
)

pushd "${BUILD_ROOT}" > /dev/null

echo -e "\n[TEST 1] stdpar transform/reduce"

nvc++ "${STD_FLAGS[@]}" -std=c++20 -o stdpar_test stdpar_test.cpp

nsys profile -t cuda,nvtx --stats=true -o stdpar_test ./stdpar_test

KERNEL_COUNT=$(nsys stats stdpar_test.nsys-rep | grep -c "CUDA Kernel" || true)
if [[ "${KERNEL_COUNT}" -gt 0 ]]; then
    echo "✓ GPU kernels detected: ${KERNEL_COUNT}"
else
    echo "✗ No GPU kernels detected (check flags/runtime)"
fi

# --- Test 2: minimal Palabos collide/stream workload
echo -e "\n[TEST 2] Palabos accelerated lattice"

cp "${SETUP_ROOT}/gpu_validation/tests/palabos_minimal.cpp" "${BUILD_ROOT}/"
mkdir -p "${BUILD_ROOT}/palabos"
cp "${SETUP_ROOT}/gpu_validation/tests/CMakeLists.txt" "${BUILD_ROOT}/palabos/"
cp "${SETUP_ROOT}/gpu_validation/tests/palabos_minimal.cpp" "${BUILD_ROOT}/palabos/"

pushd "${BUILD_ROOT}/palabos" > /dev/null
cmake -G Ninja \
    -DCMAKE_CXX_COMPILER="${CXX:-nvc++}" \
    -DCMAKE_CXX_FLAGS="${NVHPC_CXX_FLAGS_FOR_CMAKE}" \
    .

ninja

nsys profile -t cuda,nvtx --stats=true -o palabos_minimal ./palabos_minimal

GPU_LOG="${BUILD_ROOT}/gpu_util.log"
rm -f "${GPU_LOG}"
nohup nvidia-smi dmon -s u -c 5 > "${GPU_LOG}" 2>&1 &
SMI_PID=$!
./palabos_minimal || true
wait "${SMI_PID}" || true

if [[ -s "${GPU_LOG}" ]]; then
    AVG_UTIL=$(awk '{sum+=$3} END {if (NR>0) print sum/NR; else print 0}' "${GPU_LOG}")
    printf 'Average GPU utilization: %.2f%%\n' "${AVG_UTIL}"
    if (( $(echo "${AVG_UTIL} > 0" | bc -l) )); then
        echo "✓ GPU utilization observed"
    else
        echo "✗ GPU utilization remained at 0%%"
    fi
else
    echo "⚠  Unable to read GPU utilization (nvidia-smi dmon missing?)"
fi

popd > /dev/null  # leave palabos build dir
popd > /dev/null  # leave build root

echo -e "\n=== Validation Complete ==="
echo "Artifacts saved under ${BUILD_ROOT}"
