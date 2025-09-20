#!/bin/bash
# Template for new custom scripts
# Copy this file and modify for your needs
# Place in /workspace/deps/scripts/ and make executable

# Script name: YOUR_SCRIPT_NAME
# Purpose: YOUR_PURPOSE_HERE
# Author: YOUR_NAME
# Date: $(date +%Y-%m-%d)

# Configuration
SCRIPT_NAME="$(basename $0 .sh)"
RUNTIME_DIR="/workspace/deps/runtime"
LOG_FILE="$RUNTIME_DIR/${SCRIPT_NAME}.log"
PID_FILE="$RUNTIME_DIR/${SCRIPT_NAME}.pid"

# Ensure runtime directory exists
mkdir -p "$RUNTIME_DIR"

# Source environment
if [ -f "/workspace/deps/env.sh" ]; then
    source /workspace/deps/env.sh
fi

# Helper functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "❌ Error: $*" >&2
    exit 1
}

success() {
    echo "✅ $*"
}

info() {
    echo "ℹ️  $*"
}

# Main functions
start() {
    info "Starting $SCRIPT_NAME..."
    # YOUR START LOGIC HERE
    success "$SCRIPT_NAME started"
}

stop() {
    info "Stopping $SCRIPT_NAME..."
    # YOUR STOP LOGIC HERE
    success "$SCRIPT_NAME stopped"
}

status() {
    info "$SCRIPT_NAME status:"
    # YOUR STATUS LOGIC HERE
}

# Command handling
case "${1:-help}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 1
        start
        ;;
    status)
        status
        ;;
    help|--help|-h)
        cat << EOF
$SCRIPT_NAME - YOUR_DESCRIPTION_HERE

Usage: $0 {start|stop|restart|status|help}

Commands:
  start   - Start $SCRIPT_NAME
  stop    - Stop $SCRIPT_NAME
  restart - Restart $SCRIPT_NAME
  status  - Check $SCRIPT_NAME status
  help    - Show this help message

Examples:
  $0 start       # Start the service
  $0 status      # Check if running

EOF
        ;;
    *)
        error "Unknown command: $1. Use '$0 help' for usage."
        ;;
esac