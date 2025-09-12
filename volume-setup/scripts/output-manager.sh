#!/bin/bash
# Output Manager - Helps organize simulation outputs
# Lives in /workspace/deps/scripts/output-manager.sh

OUTPUT_ROOT="/workspace/output"

# Ensure output directories exist
ensure_output_dirs() {
    mkdir -p "$OUTPUT_ROOT"/{vtk,data,images,checkpoints,logs}
}

# Create timestamped subdirectory for a run
create_run_dir() {
    local category="$1"  # vtk, data, images, etc.
    local name="${2:-run}"  # optional run name
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local run_dir="$OUTPUT_ROOT/$category/${name}_${timestamp}"
    
    mkdir -p "$run_dir"
    echo "$run_dir"
}

# Create organized structure for a simulation
setup_simulation() {
    local sim_name="${1:-simulation}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local sim_base="${sim_name}_${timestamp}"
    
    echo "📁 Setting up output structure for: $sim_name"
    
    # Create all subdirectories for this simulation
    local vtk_dir="$OUTPUT_ROOT/vtk/$sim_base"
    local data_dir="$OUTPUT_ROOT/data/$sim_base"
    local log_dir="$OUTPUT_ROOT/logs/$sim_base"
    local checkpoint_dir="$OUTPUT_ROOT/checkpoints/$sim_base"
    
    mkdir -p "$vtk_dir" "$data_dir" "$log_dir" "$checkpoint_dir"
    
    # Create a symlink to latest
    ln -sfn "$vtk_dir" "$OUTPUT_ROOT/vtk/latest"
    ln -sfn "$data_dir" "$OUTPUT_ROOT/data/latest"
    ln -sfn "$log_dir" "$OUTPUT_ROOT/logs/latest"
    ln -sfn "$checkpoint_dir" "$OUTPUT_ROOT/checkpoints/latest"
    
    # Create info file
    cat > "$OUTPUT_ROOT/logs/$sim_base/info.txt" << EOF
Simulation: $sim_name
Started: $(date)
Directories:
  VTK: $vtk_dir
  Data: $data_dir
  Logs: $log_dir
  Checkpoints: $checkpoint_dir
EOF
    
    echo "✅ Output directories created:"
    echo "  VTK:         $vtk_dir"
    echo "  Data:        $data_dir"
    echo "  Logs:        $log_dir"
    echo "  Checkpoints: $checkpoint_dir"
    echo ""
    echo "  Shortcuts:   */latest -> latest run"
    
    # Export paths for use in scripts
    export CORAL_VTK_DIR="$vtk_dir"
    export CORAL_DATA_DIR="$data_dir"
    export CORAL_LOG_DIR="$log_dir"
    export CORAL_CHECKPOINT_DIR="$checkpoint_dir"
}

# List recent outputs
list_outputs() {
    local category="${1:-all}"
    
    echo "📊 Recent Outputs"
    echo "================"
    
    if [ "$category" = "all" ] || [ "$category" = "vtk" ]; then
        echo ""
        echo "VTK Files:"
        ls -lt "$OUTPUT_ROOT/vtk" 2>/dev/null | head -6 | tail -5
    fi
    
    if [ "$category" = "all" ] || [ "$category" = "data" ]; then
        echo ""
        echo "Data Files:"
        ls -lt "$OUTPUT_ROOT/data" 2>/dev/null | head -6 | tail -5
    fi
    
    if [ "$category" = "all" ] || [ "$category" = "logs" ]; then
        echo ""
        echo "Log Files:"
        ls -lt "$OUTPUT_ROOT/logs" 2>/dev/null | head -6 | tail -5
    fi
    
    if [ "$category" = "all" ] || [ "$category" = "checkpoints" ]; then
        echo ""
        echo "Checkpoints:"
        ls -lt "$OUTPUT_ROOT/checkpoints" 2>/dev/null | head -6 | tail -5
    fi
}

# Clean old outputs (with confirmation)
clean_outputs() {
    local category="${1:-all}"
    local days="${2:-30}"
    
    echo "⚠️  This will delete outputs older than $days days"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        return 1
    fi
    
    if [ "$category" = "all" ] || [ "$category" = "vtk" ]; then
        find "$OUTPUT_ROOT/vtk" -type d -mtime +$days -exec rm -rf {} + 2>/dev/null
        echo "✅ Cleaned old VTK files"
    fi
    
    if [ "$category" = "all" ] || [ "$category" = "data" ]; then
        find "$OUTPUT_ROOT/data" -type d -mtime +$days -exec rm -rf {} + 2>/dev/null
        echo "✅ Cleaned old data files"
    fi
    
    if [ "$category" = "all" ] || [ "$category" = "logs" ]; then
        find "$OUTPUT_ROOT/logs" -type d -mtime +$days -exec rm -rf {} + 2>/dev/null
        echo "✅ Cleaned old log files"
    fi
}

# Get disk usage
output_usage() {
    echo "💾 Output Directory Usage"
    echo "========================"
    
    du -sh "$OUTPUT_ROOT" 2>/dev/null | awk '{print "Total:       " $1}'
    du -sh "$OUTPUT_ROOT/vtk" 2>/dev/null | awk '{print "VTK:         " $1}'
    du -sh "$OUTPUT_ROOT/data" 2>/dev/null | awk '{print "Data:        " $1}'
    du -sh "$OUTPUT_ROOT/images" 2>/dev/null | awk '{print "Images:      " $1}'
    du -sh "$OUTPUT_ROOT/checkpoints" 2>/dev/null | awk '{print "Checkpoints: " $1}'
    du -sh "$OUTPUT_ROOT/logs" 2>/dev/null | awk '{print "Logs:        " $1}'
    
    echo ""
    echo "Free space:"
    df -h /workspace | tail -1 | awk '{print "  " $4 " available on volume"}'
}

# Main command handling
case "${1:-help}" in
    setup)
        setup_simulation "$2"
        ;;
    create)
        ensure_output_dirs
        create_run_dir "$2" "$3"
        ;;
    list)
        list_outputs "$2"
        ;;
    clean)
        clean_outputs "$2" "$3"
        ;;
    usage)
        output_usage
        ;;
    help|--help|-h)
        cat << EOF
Output Manager - Organize simulation outputs

Usage: $0 {setup|create|list|clean|usage|help}

Commands:
  setup <name>     - Setup organized output structure for a simulation
  create <type>    - Create timestamped directory (vtk/data/logs/etc)
  list [type]      - List recent outputs (all/vtk/data/logs)
  clean [type] [days] - Clean outputs older than N days (default: 30)
  usage            - Show disk usage of output directories
  help             - Show this help message

Examples:
  $0 setup cavity3d       # Setup dirs for cavity3d simulation
  $0 create vtk           # Create timestamped VTK directory
  $0 list vtk             # List recent VTK outputs
  $0 clean all 7          # Clean outputs older than 7 days
  $0 usage                # Check disk usage

Environment Variables Set by 'setup':
  CORAL_VTK_DIR        - Path to VTK output directory
  CORAL_DATA_DIR       - Path to data output directory
  CORAL_LOG_DIR        - Path to log directory
  CORAL_CHECKPOINT_DIR - Path to checkpoint directory

EOF
        ;;
    *)
        echo "Unknown command: $1. Use '$0 help' for usage."
        exit 1
        ;;
esac