#!/bin/bash
# GPU Architecture Detection Utility for Coral Machine
# Detects GPU architecture and sets appropriate CUDA compilation flags
# This reduces build times by targeting only the specific GPU architecture

detect_gpu_architecture() {
    # Check if nvidia-smi is available
    if ! command -v nvidia-smi &> /dev/null; then
        echo "[GPU] nvidia-smi not found - unable to detect GPU architecture" >&2
        return 1
    fi

    # Get GPU name using nvidia-smi
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 | sed 's/^[ \t]*//;s/[ \t]*$//')

    if [ -z "$GPU_NAME" ]; then
        echo "[GPU] No GPU detected" >&2
        return 1
    fi

    echo "[GPU] Detected: $GPU_NAME" >&2

    # Map GPU name to compute capability
    # Based on NVIDIA GPU architectures and CLAUDE.md supported list
    COMPUTE_CAPABILITY=""
    GPU_ARCH_FLAG=""

    # First, try to get compute capability directly from nvidia-smi
    CC_RAW=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^[ \t]*//;s/[ \t]*$//')
    if [ -z "$CC_RAW" ] || [ "$CC_RAW" = "N/A" ]; then
        CC_RAW=$(nvidia-smi --query-gpu=compute_capability --format=csv,noheader 2>/dev/null | head -n1 | sed 's/^[ \t]*//;s/[ \t]*$//')
    fi
    if [ -n "$CC_RAW" ] && [ "$CC_RAW" != "N/A" ]; then
        COMPUTE_CAPABILITY=$(echo "$CC_RAW" | tr -d '.' | tr -cd '0-9' )
        if [ -n "$COMPUTE_CAPABILITY" ]; then
            GPU_ARCH_FLAG="cc${COMPUTE_CAPABILITY}"
            GPU_ARCH_NAME="NVIDIA (cc${COMPUTE_CAPABILITY})"
        fi
    fi

    if [ -z "$COMPUTE_CAPABILITY" ]; then
    case "$GPU_NAME" in
        # Blackwell (cc100) - B200, B100
        *"B200"*|*"B100"*)
            COMPUTE_CAPABILITY="100"
            GPU_ARCH_FLAG="cc100"
            GPU_ARCH_NAME="Blackwell"
            ;;

        # Hopper (cc90) - H100, H200
        *"H100"*|*"H200"*|*"GH200"*)
            COMPUTE_CAPABILITY="90"
            GPU_ARCH_FLAG="cc90"
            GPU_ARCH_NAME="Hopper"
            ;;

        # Ada Lovelace (cc89) - RTX 4090, 4080, 4070, L40S, L40, L20, L4
        *"RTX 4090"*|*"RTX 4080"*|*"RTX 4070"*|*"GeForce RTX 409"*|*"GeForce RTX 408"*|*"GeForce RTX 407"*)
            COMPUTE_CAPABILITY="89"
            GPU_ARCH_FLAG="cc89"
            GPU_ARCH_NAME="Ada Lovelace"
            ;;
        *"L40S"*|*"L40"*|*"L20"*|*"L4"*)
            COMPUTE_CAPABILITY="89"
            GPU_ARCH_FLAG="cc89"
            GPU_ARCH_NAME="Ada Lovelace"
            ;;
        *"RTX 6000 Ada"*|*"RTX 5880 Ada"*|*"RTX 5000 Ada"*|*"RTX 4500 Ada"*|*"RTX 4000 Ada"*)
            COMPUTE_CAPABILITY="89"
            GPU_ARCH_FLAG="cc89"
            GPU_ARCH_NAME="Ada Lovelace"
            ;;

        # Ampere (cc86) - RTX 3080, 3070, 3060, 3050
        *"RTX 3080"*|*"RTX 3070"*|*"RTX 3060"*|*"RTX 3050"*|*"GeForce RTX 308"*|*"GeForce RTX 307"*|*"GeForce RTX 306"*|*"GeForce RTX 305"*)
            COMPUTE_CAPABILITY="86"
            GPU_ARCH_FLAG="cc86"
            GPU_ARCH_NAME="Ampere (Consumer)"
            ;;
        *"RTX A6000"*|*"RTX A5500"*|*"RTX A5000"*|*"RTX A4500"*|*"RTX A4000"*|*"RTX A2000"*)
            COMPUTE_CAPABILITY="86"
            GPU_ARCH_FLAG="cc86"
            GPU_ARCH_NAME="Ampere (Professional)"
            ;;

        # Ampere (cc80) - A100, A30
        *"A100"*|*"A30"*)
            COMPUTE_CAPABILITY="80"
            GPU_ARCH_FLAG="cc80"
            GPU_ARCH_NAME="Ampere (Data Center)"
            ;;
        # Ampere (cc86) - RTX 3090 (GA102)
        *"RTX 3090"*|*"GeForce RTX 3090"*)
            COMPUTE_CAPABILITY="86"
            GPU_ARCH_FLAG="cc86"
            GPU_ARCH_NAME="Ampere (Consumer)"
            ;;
        *"A6000"*|*"A40"*|*"A10"*|*"A16"*|*"A2"*)
            COMPUTE_CAPABILITY="86"
            GPU_ARCH_FLAG="cc86"
            GPU_ARCH_NAME="Ampere (Data Center)"
            ;;

        # Turing (cc75) - RTX 2080, 2070, 2060, T4
        *"RTX 2080"*|*"RTX 2070"*|*"RTX 2060"*|*"GeForce RTX 208"*|*"GeForce RTX 207"*|*"GeForce RTX 206"*)
            COMPUTE_CAPABILITY="75"
            GPU_ARCH_FLAG="cc75"
            GPU_ARCH_NAME="Turing"
            ;;
        *"T4"*|*"Quadro RTX"*)
            COMPUTE_CAPABILITY="75"
            GPU_ARCH_FLAG="cc75"
            GPU_ARCH_NAME="Turing"
            ;;

        # Volta (cc70) - V100
        *"V100"*)
            COMPUTE_CAPABILITY="70"
            GPU_ARCH_FLAG="cc70"
            GPU_ARCH_NAME="Volta"
            ;;

        # Pascal (cc61) - GTX 1080, 1070, 1060, P100
        *"GTX 1080"*|*"GTX 1070"*|*"GTX 1060"*|*"GeForce GTX 108"*|*"GeForce GTX 107"*|*"GeForce GTX 106"*)
            COMPUTE_CAPABILITY="61"
            GPU_ARCH_FLAG="cc61"
            GPU_ARCH_NAME="Pascal"
            ;;
        *"P100"*|*"P40"*|*"P6"*|*"P4"*)
            COMPUTE_CAPABILITY="60"
            GPU_ARCH_FLAG="cc60"
            GPU_ARCH_NAME="Pascal"
            ;;

        # Default case - unknown GPU
        *)
            echo "[GPU] Unknown GPU architecture: $GPU_NAME" >&2
            echo "[GPU] Please add mapping for this GPU or use manual override" >&2
            return 1
            ;;
    esac
    fi

    # Export the detected values
    export CUDA_COMPUTE_CAPABILITY="$COMPUTE_CAPABILITY"
    export CUDA_ARCH_FLAG="$GPU_ARCH_FLAG"
    export GPU_ARCH_NAME="$GPU_ARCH_NAME"
    export GPU_NAME="$GPU_NAME"

    # For NVCC, use the SM format
    export CUDA_ARCH_SM="sm_${COMPUTE_CAPABILITY}"

    # For nvc++, use -gpu flag format
    export NVHPC_GPU_FLAG="-gpu=$GPU_ARCH_FLAG"

    # Single architecture for faster builds
    export CMAKE_CUDA_ARCHITECTURES="$COMPUTE_CAPABILITY"

    echo "[GPU] Architecture: $GPU_ARCH_NAME ($GPU_ARCH_FLAG)" >&2
    echo "[GPU] Build flags set:" >&2
    echo "  CUDA_COMPUTE_CAPABILITY=$COMPUTE_CAPABILITY" >&2
    echo "  CUDA_ARCH_FLAG=$GPU_ARCH_FLAG" >&2
    echo "  CUDA_ARCH_SM=$CUDA_ARCH_SM" >&2
    echo "  NVHPC_GPU_FLAG=$NVHPC_GPU_FLAG" >&2
    echo "  CMAKE_CUDA_ARCHITECTURES=$COMPUTE_CAPABILITY" >&2

    return 0
}

# Function to write GPU detection results to env file
write_gpu_env() {
    local ENV_FILE="$1"

    if [ -z "$ENV_FILE" ]; then
        echo "[GPU] Error: No environment file specified" >&2
        return 1
    fi

    # Remove any existing GPU architecture lines
    sed -i '/^export CUDA_COMPUTE_CAPABILITY=/d' "$ENV_FILE" 2>/dev/null || true
    sed -i '/^export CUDA_ARCH_FLAG=/d' "$ENV_FILE" 2>/dev/null || true
    sed -i '/^export CUDA_ARCH_SM=/d' "$ENV_FILE" 2>/dev/null || true
    sed -i '/^export NVHPC_GPU_FLAG=/d' "$ENV_FILE" 2>/dev/null || true
    sed -i '/^export CMAKE_CUDA_ARCHITECTURES=/d' "$ENV_FILE" 2>/dev/null || true
    sed -i '/^export GPU_ARCH_NAME=/d' "$ENV_FILE" 2>/dev/null || true
    sed -i '/^export GPU_NAME=/d' "$ENV_FILE" 2>/dev/null || true
    sed -i '/^# GPU Architecture/d' "$ENV_FILE" 2>/dev/null || true

    # Append GPU architecture variables
    echo "" >> "$ENV_FILE"
    echo "# GPU Architecture Detection (auto-detected at runtime)" >> "$ENV_FILE"
    echo "export CUDA_COMPUTE_CAPABILITY=\"${CUDA_COMPUTE_CAPABILITY}\"" >> "$ENV_FILE"
    echo "export CUDA_ARCH_FLAG=\"${CUDA_ARCH_FLAG}\"" >> "$ENV_FILE"
    echo "export CUDA_ARCH_SM=\"${CUDA_ARCH_SM}\"" >> "$ENV_FILE"
    echo "export NVHPC_GPU_FLAG=\"${NVHPC_GPU_FLAG}\"" >> "$ENV_FILE"
    echo "export CMAKE_CUDA_ARCHITECTURES=\"${CMAKE_CUDA_ARCHITECTURES}\"" >> "$ENV_FILE"
    echo "export GPU_ARCH_NAME=\"${GPU_ARCH_NAME}\"" >> "$ENV_FILE"
    echo "export GPU_NAME=\"${GPU_NAME}\"" >> "$ENV_FILE"

    echo "[GPU] Environment variables written to $ENV_FILE" >&2

    return 0
}

# Allow manual override via environment variable
if [ -n "${CUDA_ARCH_OVERRIDE:-}" ]; then
    echo "[GPU] Using manual override: $CUDA_ARCH_OVERRIDE" >&2
    COMPUTE_CAPABILITY="${CUDA_ARCH_OVERRIDE//[^0-9]/}"
    export CUDA_COMPUTE_CAPABILITY="$COMPUTE_CAPABILITY"
    export CUDA_ARCH_FLAG="cc$COMPUTE_CAPABILITY"
    export CUDA_ARCH_SM="sm_${COMPUTE_CAPABILITY}"
    export NVHPC_GPU_FLAG="-gpu=cc$COMPUTE_CAPABILITY"
    export CMAKE_CUDA_ARCHITECTURES="$COMPUTE_CAPABILITY"
    export GPU_ARCH_NAME="Manual Override"
    export GPU_NAME="Override (cc$COMPUTE_CAPABILITY)"
    # If script is executed directly and an env file is provided, write override values
    if [ "${BASH_SOURCE[0]}" == "${0}" ] && [ -n "${1:-}" ]; then
        write_gpu_env "$1"
    fi
else
    # Run detection if script is executed directly
    if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
        detect_gpu_architecture

        # If successful and env file is provided as argument, write to it
        if [ $? -eq 0 ] && [ -n "${1:-}" ]; then
            write_gpu_env "$1"
        fi
    fi
fi