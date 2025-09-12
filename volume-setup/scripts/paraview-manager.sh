#!/bin/bash
# ParaView Server Manager - Clean version with organized paths
# Lives in /workspace/deps/scripts/paraview-manager.sh

PVSERVER_PORT=11111
RUNTIME_DIR="/workspace/deps/runtime"
PVSERVER_LOG="$RUNTIME_DIR/paraview.log"
PVSERVER_PID="$RUNTIME_DIR/paraview.pid"

# Ensure runtime directory exists
mkdir -p "$RUNTIME_DIR"

# Source environment if needed
if [ -f "/workspace/deps/env.sh" ]; then
    source /workspace/deps/env.sh
fi

start_pvserver() {
    if [ -f "$PVSERVER_PID" ] && kill -0 $(cat "$PVSERVER_PID") 2>/dev/null; then
        echo "⚠️  ParaView server already running (PID: $(cat $PVSERVER_PID))"
        return 1
    fi
    
    echo "🚀 Starting ParaView server on port $PVSERVER_PORT..."
    
    # Start pvserver in background
    nohup pvserver --server-port=$PVSERVER_PORT --force-offscreen-rendering \
        > "$PVSERVER_LOG" 2>&1 &
    
    local pid=$!
    echo $pid > "$PVSERVER_PID"
    
    # Wait a moment and check if it started successfully
    sleep 2
    if kill -0 $pid 2>/dev/null; then
        echo "✅ ParaView server started successfully (PID: $pid)"
        echo "📝 Logs: $PVSERVER_LOG"
        echo ""
        echo "To connect from your local machine:"
        echo "1. Ensure SSH tunnel is active: -L $PVSERVER_PORT:localhost:$PVSERVER_PORT"
        echo "2. In ParaView: File → Connect → localhost:$PVSERVER_PORT"
    else
        echo "❌ Failed to start ParaView server. Check logs: $PVSERVER_LOG"
        rm -f "$PVSERVER_PID"
        return 1
    fi
}

stop_pvserver() {
    if [ ! -f "$PVSERVER_PID" ]; then
        echo "⚠️  No PID file found. ParaView server may not be running."
        return 1
    fi
    
    local pid=$(cat "$PVSERVER_PID")
    if kill -0 $pid 2>/dev/null; then
        echo "🛑 Stopping ParaView server (PID: $pid)..."
        kill $pid
        sleep 1
        
        # Force kill if still running
        if kill -0 $pid 2>/dev/null; then
            echo "Force killing..."
            kill -9 $pid
        fi
        
        rm -f "$PVSERVER_PID"
        echo "✅ ParaView server stopped"
    else
        echo "⚠️  ParaView server not running (stale PID file)"
        rm -f "$PVSERVER_PID"
    fi
}

restart_pvserver() {
    echo "🔄 Restarting ParaView server..."
    stop_pvserver
    sleep 1
    start_pvserver
}

status_pvserver() {
    if [ -f "$PVSERVER_PID" ] && kill -0 $(cat "$PVSERVER_PID") 2>/dev/null; then
        local pid=$(cat "$PVSERVER_PID")
        echo "✅ ParaView server is running"
        echo "   PID: $pid"
        echo "   Port: $PVSERVER_PORT"
        echo "   Logs: $PVSERVER_LOG"
        echo ""
        echo "   Memory usage:"
        ps aux | grep -E "PID|$pid" | grep -v grep
    else
        echo "❌ ParaView server is not running"
        echo ""
        echo "   Start with: $0 start"
    fi
}

tail_logs() {
    if [ -f "$PVSERVER_LOG" ]; then
        echo "📜 Tailing ParaView server logs (Ctrl+C to stop)..."
        tail -f "$PVSERVER_LOG"
    else
        echo "⚠️  No log file found at $PVSERVER_LOG"
    fi
}

# Main command handling
case "$1" in
    start)
        start_pvserver
        ;;
    stop)
        stop_pvserver
        ;;
    restart)
        restart_pvserver
        ;;
    status)
        status_pvserver
        ;;
    logs)
        tail_logs
        ;;
    *)
        echo "ParaView Server Manager"
        echo "Usage: $0 {start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start   - Start ParaView server"
        echo "  stop    - Stop ParaView server"
        echo "  restart - Restart ParaView server"
        echo "  status  - Check server status"
        echo "  logs    - Tail server logs"
        exit 1
        ;;
esac