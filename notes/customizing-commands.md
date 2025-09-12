# Customizing Commands in Coral Machine Development Environment

## Overview
The Coral Machine environment provides a flexible command system that can be customized and extended throughout the development process. Commands are organized in layers, with some defined on the host (via Makefile) and others inside the container (via shell scripts).

## Two Command Systems

### 1. Host-Side Commands (Makefile)
- **Location**: `volume-setup/Makefile`
- **Where they run**: On your host machine (Windows/macOS/Linux)
- **When used**: Before/during container setup
- **Purpose**: Manage Docker containers and volumes
- **Examples**: `make setup`, `make dev`, `make shell`
- **Platform support**: Works on any OS with `make` installed

### 2. Container-Side Commands (Quick Commands)
- **Location**: `/workspace/deps/scripts/setup-aliases.sh`
- **Where they run**: Inside the Docker container
- **When available**: After container starts and volume is mounted
- **Purpose**: Development shortcuts and productivity tools
- **Examples**: `coral-help`, `paraview`, `check-env`
- **Persistence**: Stored in volume, survive container restarts

## System Architecture

```
Host Machine (Any OS)              Docker Container
---------------------              ----------------
volume-setup/                      /workspace/deps/scripts/
  ├── Makefile                      ├── setup-aliases.sh (main aliases)
  │   └── make commands              ├── paraview-manager.sh
  └── scripts/                       ├── output-manager.sh
      └── [templates]                └── [your-custom-scripts].sh
                                          ↓
                                    Sourced by ~/.bashrc
                                          ↓
                                    Available in terminal
```

## How Container Commands Work

### Initialization Flow
1. **During Setup** (`make setup`):
   - `00-prep.sh` copies scripts to `/workspace/deps/scripts/`
   - Scripts are made executable and persistent

2. **Container Startup**:
   - `startup-runpod.sh` checks for scripts
   - Adds source command to `~/.bashrc`
   - Scripts loaded on shell start

3. **User Session**:
   - MOTD displays available commands
   - Aliases and functions ready to use
   - Type command name to execute

## Customizing Commands

### Method 1: Direct Editing (Quick Iterations)
```bash
# Inside container
nano /workspace/deps/scripts/setup-aliases.sh

# Add your custom aliases/functions
alias gpu-mon='watch -n 1 nvidia-smi'
alias build-fast='cmake -B build -G Ninja && ninja -C build -j8'
alias coral-profile='nsys profile -o /workspace/output/profile_$(date +%s)'

# Reload immediately
source ~/.bashrc

# Changes persist across container restarts
```

### Method 2: Creating New Scripts
```bash
# Use built-in helper
new-script benchmark-runner

# Edit the generated script
nano /workspace/deps/scripts/benchmark-runner.sh

# Add alias to setup-aliases.sh
echo "alias benchmark='/workspace/deps/scripts/benchmark-runner.sh'" >> \
     /workspace/deps/scripts/setup-aliases.sh

# Reload
source ~/.bashrc
```

### Method 3: Complex Tools
```bash
# Create a management script
cat > /workspace/deps/scripts/gpu-manager.sh << 'EOF'
#!/bin/bash
case "$1" in
    start)  echo "Starting GPU monitoring..." ;;
    stop)   echo "Stopping GPU monitoring..." ;;
    status) nvidia-smi ;;
    *)      echo "Usage: $0 {start|stop|status}" ;;
esac
EOF

chmod +x /workspace/deps/scripts/gpu-manager.sh

# Add alias
echo "alias gpu='/workspace/deps/scripts/gpu-manager.sh'" >> \
     /workspace/deps/scripts/setup-aliases.sh
```

## File Locations and Persistence

### Persistent (Volume-Mounted)
```
/workspace/deps/scripts/
├── setup-aliases.sh         # Main command definitions (EDIT THIS!)
├── paraview-manager.sh       # ParaView server management
├── output-manager.sh         # Output directory management
├── SCRIPT_TEMPLATE.sh        # Template for new scripts
└── [custom-scripts].sh       # Your additions
```

### Temporary (Container Image)
```
/etc/motd                    # Welcome message (rebuild to change)
/root/.bashrc                # Sources setup-aliases.sh
/root/.zshrc                 # Sources setup-aliases.sh
```

## Development Workflow

### Initial Development
```bash
# Start environment
$ make dev
$ make shell

# Check available commands
root@coral~machine:~$ coral-help

# Test and iterate on commands
root@coral~machine:~$ nano /workspace/deps/scripts/setup-aliases.sh
root@coral~machine:~$ source ~/.bashrc
```

### Adding Project-Specific Commands
```bash
# As project evolves, add specialized commands
root@coral~machine:~$ cat >> /workspace/deps/scripts/setup-aliases.sh << 'EOF'

# Coral simulation shortcuts
alias sim-small='./build/coral_machine --config small.cfg'
alias sim-large='./build/coral_machine --config large.cfg'
alias sim-profile='./build/coral_machine --profile --output /workspace/output'

# Data processing
function process-vtk() {
    local input="$1"
    echo "Processing $input..."
    # Add processing logic
}
EOF

root@coral~machine:~$ source ~/.bashrc
```

### Sharing with Team
```bash
# Export your customizations
$ docker cp coral-dev:/workspace/deps/scripts/setup-aliases.sh \
           volume-setup/scripts/setup-aliases-custom.sh

# Commit to version control
$ git add volume-setup/scripts/setup-aliases-custom.sh
$ git commit -m "Add team productivity commands"
$ git push
```

## Built-in Helper Commands

### Script Management
- `new-script <name>` - Create new script from template
- `list-scripts` - List all custom scripts
- `check-env` - Verify environment setup

### Development Helpers
- `build-coral` - Build Coral Machine project
- `clean-build` - Clean build directory
- `coral-source` - Navigate to source directory
- `coral-build` - Navigate to build directory

### Visualization
- `paraview` - Start ParaView server
- `pv start/stop/status` - ParaView management
- `new-simulation <name>` - Setup output directories

## Best Practices

### 1. Organize by Function
```bash
# Group related commands
# === GPU TOOLS ===
alias gpu='nvidia-smi'
alias gpu-watch='watch -n 1 nvidia-smi'

# === BUILD SHORTCUTS ===
alias build-debug='cmake -DCMAKE_BUILD_TYPE=Debug ...'
alias build-release='cmake -DCMAKE_BUILD_TYPE=Release ...'
```

### 2. Document Your Commands
```bash
# Add help text
function my-tool() {
    if [ "$1" = "--help" ]; then
        echo "Usage: my-tool [options]"
        echo "  Does something useful"
        return
    fi
    # Tool logic here
}
```

### 3. Version Control Important Scripts
```bash
# Keep source-controlled copy
volume-setup/scripts/
├── setup-aliases.sh          # Base aliases
├── project-commands.sh       # Project-specific
└── team-tools.sh            # Shared team tools
```

### 4. Use Functions for Complex Logic
```bash
# Instead of complex aliases, use functions
function coral-benchmark() {
    local iterations="${1:-100}"
    local output="/workspace/output/benchmark_$(date +%Y%m%d_%H%M%S)"
    
    echo "Running $iterations iterations..."
    for i in $(seq 1 $iterations); do
        ./build/coral_machine --benchmark >> "$output.log"
    done
    
    echo "Results saved to $output.log"
}
```

## Troubleshooting

### Commands Not Available
```bash
# Check if scripts are sourced
grep setup-aliases ~/.bashrc

# Manually source if missing
echo "source /workspace/deps/scripts/setup-aliases.sh" >> ~/.bashrc
source ~/.bashrc
```

### Changes Not Persisting
```bash
# Ensure editing persistent location
pwd  # Should be /workspace/deps/scripts/

# Check volume mount
mount | grep workspace
```

### Script Permission Issues
```bash
# Fix permissions
chmod +x /workspace/deps/scripts/*.sh
```

## Summary

The command system is designed to:
- **Start simple**: Basic commands available immediately
- **Grow with project**: Add commands as needs arise
- **Persist changes**: Modifications survive restarts
- **Share easily**: Export and version control customizations
- **Stay organized**: Modular script structure

This flexibility allows the environment to adapt throughout the entire development lifecycle, from initial setup through production deployment.