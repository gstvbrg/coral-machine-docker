#!/bin/bash
# Setup script with organized paths
# Sources from ~/.bashrc to load persistent utilities

# Add scripts directory to PATH if not already there
if [[ ":$PATH:" != *":/workspace/deps/scripts:"* ]]; then
    export PATH="$PATH:/workspace/deps/scripts"
fi

# ParaView shortcuts (using the manager script)
alias pv='/workspace/deps/scripts/paraview-manager.sh'
alias pv-start='pv start'
alias pv-stop='pv stop'
alias pv-restart='pv restart'
alias pv-status='pv status'
alias pv-logs='pv logs'

# Quick ParaView function
function paraview() {
    /workspace/deps/scripts/paraview-manager.sh start
}

# Output management
alias output='/workspace/deps/scripts/output-manager.sh'
alias output-setup='output setup'
alias output-list='output list'
alias output-usage='output usage'
alias output-clean='output clean'

# Quick simulation setup
function new-simulation() {
    local name="${1:-simulation}"
    /workspace/deps/scripts/output-manager.sh setup "$name"
    echo ""
    echo "💡 Tip: Your output paths are now in environment variables:"
    echo "   \$CORAL_VTK_DIR, \$CORAL_DATA_DIR, \$CORAL_LOG_DIR"
}

# === ADD YOUR CUSTOM SCRIPTS HERE ===
# Example pattern for adding new scripts:
# alias my-tool='/workspace/deps/scripts/my-tool.sh'
# function my-quick-command() { /workspace/deps/scripts/my-tool.sh start; }

# === DEVELOPMENT HELPERS ===
# Coral Machine development
alias build-coral='cd /workspace/source && cmake -B ../build -G Ninja && ninja -C ../build'
alias clean-build='rm -rf /workspace/build/* && echo "Build directory cleaned"'
alias coral-source='cd /workspace/source'
alias coral-build='cd /workspace/build'

# GPU monitoring
alias gpu='nvidia-smi'
alias gpu-watch='watch -n 1 nvidia-smi'

# === SCRIPT MANAGEMENT ===
# Helper to create new custom script from template
function new-script() {
    local name="$1"
    if [ -z "$name" ]; then
        echo "Usage: new-script <script-name>"
        echo "Example: new-script gpu-monitor"
        return 1
    fi
    
    local script_path="/workspace/deps/scripts/${name}.sh"
    
    if [ -f "$script_path" ]; then
        echo "❌ Script already exists: $script_path"
        return 1
    fi
    
    # Copy template
    cp /workspace/deps/scripts/SCRIPT_TEMPLATE.sh "$script_path"
    
    # Basic customization
    sed -i "s/YOUR_SCRIPT_NAME/$name/g" "$script_path"
    sed -i "s/YOUR_PURPOSE_HERE/Custom script for $name/g" "$script_path"
    sed -i "s/YOUR_NAME/$(whoami)/g" "$script_path"
    sed -i "s/\$(date +%Y-%m-%d)/$(date +%Y-%m-%d)/g" "$script_path"
    
    # Make executable
    chmod +x "$script_path"
    
    echo "✅ Created new script: $script_path"
    echo ""
    echo "Next steps:"
    echo "1. Edit the script: nano $script_path"
    echo "2. Add an alias to this file: nano /workspace/deps/scripts/setup-aliases.sh"
    echo "3. Reload aliases: source ~/.bashrc"
    echo ""
    echo "Example alias to add:"
    echo "  alias $name='$script_path'"
}

# List all custom scripts
function list-scripts() {
    echo "📜 Custom Scripts in /workspace/deps/scripts/"
    echo "============================================"
    for script in /workspace/deps/scripts/*.sh; do
        if [ -f "$script" ] && [ "$script" != *"SCRIPT_TEMPLATE.sh" ] && [ "$script" != *"setup-aliases.sh" ]; then
            local name=$(basename "$script" .sh)
            echo "  • $name"
            if [ -x "$script" ]; then
                # Try to get description from script
                grep -m1 "^# Purpose:" "$script" 2>/dev/null | sed 's/# Purpose: /    └─ /'
            fi
        fi
    done
    echo ""
    echo "Create new script: new-script <name>"
}

# === ENVIRONMENT CHECKS ===
function check-env() {
    echo "🔍 Coral Machine Environment Check"
    echo "===================================="
    
    # Check compilers
    echo "Compilers:"
    which nvc++ &>/dev/null && echo "  ✅ nvc++ ($(nvc++ --version 2>&1 | head -1))" || echo "  ❌ nvc++ not found"
    which nvcc &>/dev/null && echo "  ✅ nvcc ($(nvcc --version | grep release))" || echo "  ❌ nvcc not found"
    
    # Check libraries
    echo ""
    echo "Libraries:"
    [ -f /workspace/deps/lib/libpalabos.a ] && echo "  ✅ Palabos" || echo "  ❌ Palabos"
    [ -f /workspace/deps/lib/libgeometry-central.a ] && echo "  ✅ Geometry-central" || echo "  ❌ Geometry-central"
    
    # Check tools
    echo ""
    echo "Tools:"
    which pvserver &>/dev/null && echo "  ✅ ParaView server" || echo "  ❌ ParaView server"
    which cmake &>/dev/null && echo "  ✅ CMake" || echo "  ❌ CMake"
    which ninja &>/dev/null && echo "  ✅ Ninja" || echo "  ❌ Ninja"
    
    # Check custom scripts
    echo ""
    echo "Custom Scripts:"
    local script_count=$(ls -1 /workspace/deps/scripts/*.sh 2>/dev/null | grep -v TEMPLATE | grep -v setup-aliases | wc -l)
    echo "  📜 $script_count custom scripts available"
    
    # Check GPU
    echo ""
    echo "GPU:"
    if nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | sed 's/^/  /'
    else
        echo "  ❌ No GPU detected"
    fi
    
    # Check runtime directory
    echo ""
    echo "Runtime Directory:"
    if [ -d /workspace/deps/runtime ]; then
        local log_count=$(ls -1 /workspace/deps/runtime/*.log 2>/dev/null | wc -l)
        local pid_count=$(ls -1 /workspace/deps/runtime/*.pid 2>/dev/null | wc -l)
        echo "  📁 /workspace/deps/runtime/"
        echo "     ├─ $log_count log files"
        echo "     └─ $pid_count pid files"
    else
        echo "  📁 /workspace/deps/runtime/ (not created yet)"
    fi
}

# === HELP SYSTEM ===
function coral-help() {
    echo "🪸 Coral Machine Development Commands"
    echo "====================================="
    echo "Development:"
    echo "  build-coral   - Build Coral Machine project"
    echo "  clean-build   - Clean build directory"
    echo "  coral-source  - Go to source directory"
    echo "  coral-build   - Go to build directory"
    echo ""
    echo "ParaView Server:"
    echo "  paraview      - Quick start ParaView server"
    echo "  pv start      - Start ParaView server"
    echo "  pv stop       - Stop ParaView server"
    echo "  pv status     - Check ParaView status"
    echo "  pv logs       - View ParaView logs"
    echo ""
    echo "Output Management:"
    echo "  new-simulation <name> - Setup output dirs for simulation"
    echo "  output-list   - List recent output files"
    echo "  output-usage  - Check disk usage of outputs"
    echo "  output-clean  - Clean old output files"
    echo "  output help   - More output management commands"
    echo "Environment:"
    echo "  check-env     - Check environment setup"
    echo "  gpu           - Show GPU status"
    echo "  gpu-watch     - Monitor GPU continuously"
    echo ""
    echo "Script Management:"
    echo "  new-script    - Create new custom script from template"
    echo "  list-scripts  - List all custom scripts"
    echo ""

    echo "Type 'coral-help' to see this message again"
}