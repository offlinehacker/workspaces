#!/bin/bash

set -Eeuo pipefail

# Default values
SESSION_NAME="synapse"
PORT_OFFSET=0
BACKGROUND_MODE=false
RESET_DB=false
EXTRA_COMMAND=""
SETUP_ONLY=false
KILL_ONLY=false
NO_SETUP=false

# Show help
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Start development environment with tmux, air, vite, and storybook.

OPTIONS:
    --session NAME          Tmux session name (default: synapse)
    --port-offset OFFSET    Port offset for all services (default: 0)
    --reset                 Reset database before starting
    --bg, --background      Run in background mode
    --setup                 Only setup dependencies (don't start servers)
    --kill                  Kill the development session
    --no-setup              Start without running setup
    -- <command>           Additional command to run in a separate tmux window
    -h, --help             Show this help message

ENVIRONMENT VARIABLES:
    SESSION_NAME           Tmux session name (overridden by --session)
    PORT_OFFSET            Port offset (overridden by --port-offset)

PORTS (with offset):
    Backend:    8080 + offset
    Web:        5173 + offset
    Storybook:  6006 + offset

EXAMPLES:
    # Setup dependencies only
    $(basename "$0") --setup

    # Start and attach (default behavior)
    $(basename "$0")

    # Start with custom session and port offset
    $(basename "$0") --session task1 --port-offset 100

    # Start with fresh database
    $(basename "$0") --reset

    # Start in background
    $(basename "$0") --bg

    # Attach to running session
    $(basename "$0")

    # Kill session
    $(basename "$0") --kill

    # Start with extra command
    $(basename "$0") -- claude
EOF
    exit 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --)
            # Everything after -- is the extra command
            shift
            EXTRA_COMMAND="$*"
            break
            ;;
        --session)
            SESSION_NAME="$2"
            shift 2
            ;;
        --port-offset)
            PORT_OFFSET="$2"
            shift 2
            ;;
        --reset)
            RESET_DB=true
            shift
            ;;
        --bg|--background)
            BACKGROUND_MODE=true
            shift
            ;;
        --setup)
            SETUP_ONLY=true
            shift
            ;;
        --kill)
            KILL_ONLY=true
            shift
            ;;
        --no-setup)
            NO_SETUP=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Allow environment variables to override defaults (if not set via flags)
SESSION_NAME="${SESSION_NAME:-synapse}"
PORT_OFFSET="${PORT_OFFSET:-0}"

# Function to check if a port is available
is_port_available() {
    local port=$1
    ! lsof -i ":$port" >/dev/null 2>&1
}

get_session_display_name() {
    local name="$SESSION_NAME"
    if [[ "$name" == *-* ]]; then
        echo "${name#*-}"
    else
        echo "$name"
    fi
}

set_session_display_name() {
    local display_name
    display_name=$(get_session_display_name)
    tmux $TMUX_SOCKET set-option -t "$SESSION_NAME" @display_name "$display_name"
}

# Find available port offset
find_available_ports() {
    local offset=$1
    local max_attempts=50
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        local backend_port=$((8080 + offset))
        local web_port=$((5173 + offset))
        local storybook_port=$((6006 + offset))

        # Check if all three ports are available
        if is_port_available "$backend_port" && \
           is_port_available "$web_port" && \
           is_port_available "$storybook_port"; then
            echo "$offset"
            return 0
        fi

        offset=$((offset + 1))
        attempt=$((attempt + 1))
    done

    echo "ERROR: Could not find available ports after $max_attempts attempts" >&2
    return 1
}

# Function to check if a server is running
check_server() {
    local port=$1
    local name=$2
    local max_attempts=30  # 30 attempts with 1 second delay = 30 seconds max
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost:$port | grep -q "200\|404"; then
            echo "✓ $name is running on port $port"
            return 0
        fi

        if [ $attempt -eq 1 ]; then
            echo -n "Waiting for $name to start on port $port..."
        else
            echo -n "."
        fi

        attempt=$((attempt + 1))
        sleep 1
    done

    echo " FAILED"
    return 1
}

# Function to create and start the tmux session
create_and_start_session() {
    local backend_window="backend-$BACKEND_PORT"
    local storybook_window="storybook-$STORYBOOK_PORT"
    local web_window="web-$WEB_PORT"

    # Create new session with backend server
    tmux $TMUX_SOCKET new-session -d -s "$SESSION_NAME" -n "$backend_window" -c "$(pwd)"
    set_session_display_name


    # Window 0: Backend server with air
    tmux $TMUX_SOCKET send-keys -t "$SESSION_NAME:$backend_window" 'echo "Starting Go backend with hot reload on port '"$BACKEND_PORT"'..."' C-m
    tmux $TMUX_SOCKET send-keys -t "$SESSION_NAME:$backend_window" 'SYNAPSE_PORT='"$BACKEND_PORT"' air' C-m

    # Create window for storybook
    tmux $TMUX_SOCKET new-window -t "$SESSION_NAME" -n "$storybook_window" -c "$(pwd)/web"

    # Window 1: Storybook
    tmux $TMUX_SOCKET send-keys -t "$SESSION_NAME:$storybook_window" 'echo "Starting Storybook on port '"$STORYBOOK_PORT"'..."' C-m
    tmux $TMUX_SOCKET send-keys -t "$SESSION_NAME:$storybook_window" 'npm run storybook -- --no-open --port '"$STORYBOOK_PORT" C-m

    # Create window for web UI
    tmux $TMUX_SOCKET new-window -t "$SESSION_NAME" -n "$web_window" -c "$(pwd)/web"

    # Window 2: Web UI
    tmux $TMUX_SOCKET send-keys -t "$SESSION_NAME:$web_window" 'echo "Starting Web UI on port '"$WEB_PORT"'..."' C-m
    tmux $TMUX_SOCKET send-keys -t "$SESSION_NAME:$web_window" 'VITE_BACKEND_PORT='"$BACKEND_PORT"' npm run dev -- --port '"$WEB_PORT" C-m

    # Select first window
    tmux $TMUX_SOCKET select-window -t "$SESSION_NAME:$backend_window"

    # Health check - verify all servers start successfully
    echo "Performing health checks..."

    # Check all servers
    if ! check_server $BACKEND_PORT "Backend"; then
        echo "ERROR: Backend server failed to start"
        echo "Cleaning up failed session..."
        tmux $TMUX_SOCKET kill-session -t "$SESSION_NAME" 2>/dev/null || true
        exit 1
    fi

    if ! check_server $STORYBOOK_PORT "Storybook"; then
        echo "ERROR: Storybook failed to start"
        echo "Cleaning up failed session..."
        tmux $TMUX_SOCKET kill-session -t "$SESSION_NAME" 2>/dev/null || true
        exit 1
    fi

    if ! check_server $WEB_PORT "Web UI"; then
        echo "ERROR: Web UI failed to start"
        echo "Cleaning up failed session..."
        tmux $TMUX_SOCKET kill-session -t "$SESSION_NAME" 2>/dev/null || true
        exit 1
    fi

    # Create extra window for custom command if provided
    if [ -n "$EXTRA_COMMAND" ]; then
        echo "Creating custom window with command: $EXTRA_COMMAND"

        # Create window for custom command (tmux will auto-name based on running process)
        tmux $TMUX_SOCKET new-window -t $SESSION_NAME -c "$(pwd)"

        # Send the custom command
        tmux $TMUX_SOCKET send-keys -t $SESSION_NAME: "$EXTRA_COMMAND" C-m
    fi

    echo "All servers started successfully!"
}

# Main execution logic
main() {
    # Find available ports (auto-increment if needed)
    PORT_OFFSET=$(find_available_ports "$PORT_OFFSET")
    if [ $? -ne 0 ]; then
        exit 1
    fi

    # Calculate ports
    BACKEND_PORT=$((8080 + PORT_OFFSET))
    WEB_PORT=$((5173 + PORT_OFFSET))
    STORYBOOK_PORT=$((6006 + PORT_OFFSET))

    echo "Using port offset: $PORT_OFFSET"
    echo "Ports: Backend=$BACKEND_PORT, Web=$WEB_PORT, Storybook=$STORYBOOK_PORT"

    # Determine tmux socket name
    if [ "$SESSION_NAME" != "synapse" ]; then
        TMUX_SOCKET="-L $SESSION_NAME"
    else
        TMUX_SOCKET=""
    fi

    # Check if session already exists
    SESSION_EXISTS=false
    if tmux $TMUX_SOCKET has-session -t $SESSION_NAME 2>/dev/null; then
        SESSION_EXISTS=true
    fi

    # Handle --kill flag
    if [ "$KILL_ONLY" = true ]; then
        if [ "$SESSION_EXISTS" = true ]; then
            echo "Killing development session '$SESSION_NAME'..."
            tmux $TMUX_SOCKET kill-session -t $SESSION_NAME
            echo "Development session killed."
        else
            echo "No development session '$SESSION_NAME' found."
        fi
        exit 0
    fi

    # Handle existing session
    if [ "$SESSION_EXISTS" = true ]; then
        set_session_display_name
        if [ "$SETUP_ONLY" = true ]; then
            echo "Development session '$SESSION_NAME' is already running"
            echo "Setup not needed for existing session."
            exit 0
        fi

        if [ "$BACKGROUND_MODE" = true ]; then
            echo "Development session '$SESSION_NAME' is already running"
            echo "To attach: $0"
            echo "To kill: $0 --kill"
            exit 0
        else
            # Attach to existing session
            echo "Development session '$SESSION_NAME' is already running"
            echo "Attaching to existing session..."
            tmux $TMUX_SOCKET attach-session -t $SESSION_NAME
            exit 0
        fi
    fi

    # Session doesn't exist - run setup first (unless --no-setup)
    if [ "$NO_SETUP" = false ]; then
        echo "Setting up development environment..."

        # Install npm dependencies
        echo "Installing npm dependencies..."
        (cd web && npm install)
        echo "Dependencies installed."

        # Install Go dependencies if needed
        echo "Installing Go dependencies..."
        go mod download
        echo "Go dependencies installed."

        echo "Setup complete."

        # Handle --setup flag (exit after setup)
        if [ "$SETUP_ONLY" = true ]; then
            exit 0
        fi
    fi

    # Reset database if requested
    if [ "$RESET_DB" = true ]; then
        echo "Resetting database..."
        rm -f *.db *.db-shm *.db-wal
        echo "Database files removed."
    fi

    # Create and start the session
    create_and_start_session

    # Attach to session or run in background
    if [ "$BACKGROUND_MODE" = true ]; then
        echo "Development servers started in background session '$SESSION_NAME'"
        echo "To attach: $0"
        echo "To kill: $0 --kill"
    else
        # Attach to session
        tmux $TMUX_SOCKET attach-session -t $SESSION_NAME
    fi
}

# Run main function
main
