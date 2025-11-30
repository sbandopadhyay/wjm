#!/bin/bash
# Job Scheduler Setup Wizard
# Interactive configuration for optimal deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN} $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}  $1${NC}"
}

print_error() {
    echo -e "${RED} $1${NC}"
}

print_info() {
    echo -e "${CYAN}  $1${NC}"
}

ask_question() {
    local question="$1"
    local default="$2"
    local response

    if [ -n "$default" ]; then
        echo -e "${CYAN}$question [${default}]: ${NC}"
        read -r response
        echo "${response:-$default}"
    else
        echo -e "${CYAN}$question: ${NC}"
        read -r response
        echo "$response"
    fi
}

detect_system() {
    # Detect number of CPU cores
    if [ -f /proc/cpuinfo ]; then
        CPU_CORES=$(grep -c ^processor /proc/cpuinfo)
    elif command -v sysctl &> /dev/null; then
        CPU_CORES=$(sysctl -n hw.ncpu)
    else
        CPU_CORES=4
    fi

    # Detect available memory (in GB)
    if [ -f /proc/meminfo ]; then
        MEM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
    elif command -v sysctl &> /dev/null; then
        MEM_BYTES=$(sysctl -n hw.memsize)
        MEM_GB=$((MEM_BYTES / 1024 / 1024 / 1024))
    else
        MEM_GB=8
    fi

    # Detect GPUs
    if command -v nvidia-smi &> /dev/null; then
        GPU_COUNT=$(nvidia-smi --list-gpus 2>/dev/null | wc -l)
    else
        GPU_COUNT=0
    fi
}

# Main setup wizard
main() {
    clear
    print_header " Job Scheduler Setup Wizard"
    echo ""
    echo "This wizard will help you configure the job scheduler"
    echo "for optimal performance on your system."
    echo ""

    # Detect system capabilities
    print_info "Detecting system capabilities..."
    detect_system

    echo ""
    print_success "System detected:"
    echo "  - CPU Cores: $CPU_CORES"
    echo "  - Memory: ${MEM_GB}GB"
    echo "  - GPUs: $GPU_COUNT"
    echo ""

    # Ask usage type
    print_header "Step 1: Usage Type"
    echo ""
    echo "What will you primarily use this scheduler for?"
    echo ""
    echo "1) Personal Development (light workloads, testing)"
    echo "2) Research & Experiments (medium workloads, ML training)"
    echo "3) Production Computing (heavy workloads, batch processing)"
    echo "4) GPU Workloads (deep learning, CUDA)"
    echo "5) High-Throughput (many small jobs)"
    echo "6) Custom (I'll configure manually)"
    echo ""

    usage_type=$(ask_question "Select option (1-6)" "2")

    # Configure based on selection
    case "$usage_type" in
        1)
            CONFIG_TYPE="Personal Development"
            MAX_CONCURRENT_JOBS=2
            MAX_TOTAL_WEIGHT=50
            DEFAULT_JOB_WEIGHT=10
            ARCHIVE_THRESHOLD=50
            REFRESH_INTERVAL=3
            ;;
        2)
            CONFIG_TYPE="Research & Experiments"
            MAX_CONCURRENT_JOBS=4
            MAX_TOTAL_WEIGHT=100
            DEFAULT_JOB_WEIGHT=10
            ARCHIVE_THRESHOLD=100
            REFRESH_INTERVAL=3
            ;;
        3)
            CONFIG_TYPE="Production Computing"
            MAX_CONCURRENT_JOBS=$CPU_CORES
            MAX_TOTAL_WEIGHT=$((CPU_CORES * 25))
            DEFAULT_JOB_WEIGHT=20
            ARCHIVE_THRESHOLD=200
            REFRESH_INTERVAL=2
            ;;
        4)
            CONFIG_TYPE="GPU Workloads"
            if [ "$GPU_COUNT" -gt 0 ]; then
                MAX_CONCURRENT_JOBS=$GPU_COUNT
            else
                MAX_CONCURRENT_JOBS=2
            fi
            MAX_TOTAL_WEIGHT=$((MAX_CONCURRENT_JOBS * 100))
            DEFAULT_JOB_WEIGHT=100
            ARCHIVE_THRESHOLD=100
            REFRESH_INTERVAL=5
            ;;
        5)
            CONFIG_TYPE="High-Throughput"
            MAX_CONCURRENT_JOBS=$((CPU_CORES * 2))
            MAX_TOTAL_WEIGHT=100
            DEFAULT_JOB_WEIGHT=5
            ARCHIVE_THRESHOLD=500
            REFRESH_INTERVAL=1
            ;;
        6)
            CONFIG_TYPE="Custom"
            echo ""
            MAX_CONCURRENT_JOBS=$(ask_question "Max concurrent jobs" "4")
            MAX_TOTAL_WEIGHT=$(ask_question "Max total weight" "100")
            DEFAULT_JOB_WEIGHT=$(ask_question "Default job weight" "10")
            ARCHIVE_THRESHOLD=$(ask_question "Archive threshold" "100")
            REFRESH_INTERVAL=$(ask_question "Dashboard refresh interval (seconds)" "3")
            ;;
        *)
            print_error "Invalid option. Using defaults."
            usage_type=2
            MAX_CONCURRENT_JOBS=4
            MAX_TOTAL_WEIGHT=100
            DEFAULT_JOB_WEIGHT=10
            ARCHIVE_THRESHOLD=100
            REFRESH_INTERVAL=3
            ;;
    esac

    echo ""
    print_header "Step 2: Directory Configuration"
    echo ""

    DEFAULT_JOB_DIR="$HOME/job_logs"
    JOB_DIR=$(ask_question "Job logs directory" "$DEFAULT_JOB_DIR")

    # Create directories
    mkdir -p "$JOB_DIR"
    mkdir -p "$JOB_DIR/queue"
    mkdir -p "$JOB_DIR/archive"

    echo ""
    print_header "Step 3: Review Configuration"
    echo ""
    echo "Configuration Summary:"
    echo "  Type: $CONFIG_TYPE"
    echo "  Max Concurrent Jobs: $MAX_CONCURRENT_JOBS"
    echo "  Max Total Weight: $MAX_TOTAL_WEIGHT"
    echo "  Default Job Weight: $DEFAULT_JOB_WEIGHT"
    echo "  Archive Threshold: $ARCHIVE_THRESHOLD"
    echo "  Refresh Interval: ${REFRESH_INTERVAL}s"
    echo "  Job Directory: $JOB_DIR"
    echo ""

    confirm=$(ask_question "Save this configuration? (yes/no)" "yes")

    if [[ ! "$confirm" =~ ^[Yy] ]]; then
        print_warning "Setup cancelled."
        exit 0
    fi

    # Write configuration file
    CONFIG_FILE="wjm.config"

    cat > "$CONFIG_FILE" << EOF
# Job Scheduler Configuration
# Generated by Setup Wizard on $(date)
# Configuration Type: $CONFIG_TYPE

# Directory Configuration
JOB_DIR=$JOB_DIR
QUEUE_DIR=\$JOB_DIR/queue
ARCHIVE_DIR=\$JOB_DIR/archive

# Resource Limits
MAX_CONCURRENT_JOBS=$MAX_CONCURRENT_JOBS
MAX_TOTAL_WEIGHT=$MAX_TOTAL_WEIGHT
DEFAULT_JOB_WEIGHT=$DEFAULT_JOB_WEIGHT

# Archiving
ARCHIVE_THRESHOLD=$ARCHIVE_THRESHOLD

# Monitoring
LOG_FILE_NAME="job_XXX.log"
WATCH_REFRESH_INTERVAL=$REFRESH_INTERVAL
EOF

    print_success "Configuration saved to: $CONFIG_FILE"

    echo ""
    print_header "Step 4: Create Example Jobs"
    echo ""

    create_examples=$(ask_question "Create example jobs? (yes/no)" "yes")

    if [[ "$create_examples" =~ ^[Yy] ]]; then
        mkdir -p examples

        # Example 1: Simple job
        cat > examples/example_simple.run << 'SIMPLE'
#!/bin/bash
# Simple example job
echo "Hello from job scheduler!"
echo "Current time: $(date)"
sleep 5
echo "Job complete!"
SIMPLE

        # Example 2: GPU job
        cat > examples/example_gpu.run << 'GPU'
# WEIGHT: 100
# GPU: 0
#!/bin/bash
echo "GPU job starting..."
echo "CUDA_VISIBLE_DEVICES: $CUDA_VISIBLE_DEVICES"
# Your GPU code here
sleep 10
echo "GPU job complete!"
GPU

        # Example 3: Priority job
        cat > examples/example_priority.run << 'PRIORITY'
# WEIGHT: 30
# PRIORITY: high
#!/bin/bash
echo "High priority job"
sleep 5
echo "Priority job complete!"
PRIORITY

        # Example 4: Python script
        cat > examples/example_python.py << 'PYTHON'
#!/usr/bin/env python3
import time
import sys

print("Python job starting...")
for i in range(1, 6):
    print(f"Progress: {i}/5")
    time.sleep(1)
print("Python job complete!")
PYTHON

        chmod +x examples/*.run examples/*.py

        print_success "Example jobs created in ./examples/"
    fi

    echo ""
    print_header "Step 5: Quick Start Guide"
    echo ""

    cat > GETTING_STARTED.txt << 'GUIDE'
 Getting Started with Your Job Scheduler

You're all set up! Here are your next steps:

1. TEST THE SCHEDULER
   ./wjm --help

2. RUN YOUR FIRST JOB
   ./wjm -qrun examples/example_simple.run

3. CHECK STATUS
   ./wjm -status

4. VIEW LOGS
   ./wjm -logs job_001

5. TRY INTERACTIVE MODE
   ./wjm -tui

6. READ TUTORIALS
   cat tutorials/TUTORIAL_1_BEGINNER.md

7. LEARN BEST PRACTICES
   cat BEST_PRACTICES.md

QUICK REFERENCE:
- Submit job: ./wjm -qrun <job>.run
- Check status: ./wjm -status
- Interactive TUI: ./wjm -tui
- View help: ./wjm --help

CONFIGURATION:
Your configuration is in: wjm.config
Edit this file to customize settings.

DOCUMENTATION:
- QUICKSTART.md - 5-minute guide
- BEST_PRACTICES.md - Production tips
- PRODUCTION_CONFIG.md - Advanced configs
- tutorials/ - Step-by-step tutorials
GUIDE

    print_success "Quick start guide created: GETTING_STARTED.txt"

    echo ""
    print_header "Setup Complete!"
    echo ""
    print_success "Job scheduler is ready to use!"
    echo ""
    echo "Next steps:"
    echo "  1. cat GETTING_STARTED.txt"
    echo "  2. ./wjm -qrun examples/example_simple.run"
    echo "  3. ./wjm -tui"
    echo ""
    echo "For help: ./wjm --help"
    echo "For tutorials: ls tutorials/"
    echo ""

    # Offer to add wjm to PATH
    echo ""
    print_header " Add wjm to PATH (Recommended)"
    echo ""
    print_info "Currently you need to type './wjm' from the src/ directory"
    print_info "Adding to PATH lets you type just 'wjm' from anywhere"
    echo ""

    add_to_path=$(ask_question "Add wjm to your PATH? (yes/no)" "yes")
    if [[ "$add_to_path" =~ ^[Yy] ]]; then
        # Detect shell config file
        SHELL_CONFIG=""
        if [ -n "$BASH_VERSION" ]; then
            SHELL_CONFIG="$HOME/.bashrc"
        elif [ -n "$ZSH_VERSION" ]; then
            SHELL_CONFIG="$HOME/.zshrc"
        else
            # Try to detect from $SHELL
            case "$SHELL" in
                */bash)
                    SHELL_CONFIG="$HOME/.bashrc"
                    ;;
                */zsh)
                    SHELL_CONFIG="$HOME/.zshrc"
                    ;;
                *)
                    SHELL_CONFIG="$HOME/.bashrc"  # Default to bashrc
                    ;;
            esac
        fi

        WJM_PATH="$(pwd)"

        # Check if already in PATH config
        if grep -q "# WJM - Workstation Job Manager" "$SHELL_CONFIG" 2>/dev/null; then
            print_warning "wjm PATH entry already exists in $SHELL_CONFIG"
        else
            # Add to shell config
            echo "" >> "$SHELL_CONFIG"
            echo "# WJM - Workstation Job Manager" >> "$SHELL_CONFIG"
            echo "export PATH=\"$WJM_PATH:\$PATH\"" >> "$SHELL_CONFIG"

            print_success "Added wjm to PATH in $SHELL_CONFIG"
            echo ""
            print_info "To use immediately, run: source $SHELL_CONFIG"
            print_info "Or simply open a new terminal"
            echo ""
            print_success "You can now type 'wjm' from anywhere!"
        fi
    else
        print_info "Skipped. You can add it later by running:"
        print_info "  echo 'export PATH=\"$(pwd):\$PATH\"' >> ~/.bashrc"
        print_info "  source ~/.bashrc"
    fi
    echo ""

    # Offer to run first example
    run_example=$(ask_question "Run example job now? (yes/no)" "no")
    if [[ "$run_example" =~ ^[Yy] ]]; then
        echo ""
        print_info "Running example job..."
        ./wjm -qrun examples/example_simple.run
        sleep 2
        ./wjm -status
        echo ""
        print_info "Watch it with: ./wjm -watch job_001"
    fi
}

# Check we're in the right directory
if [ ! -f "wjm" ]; then
    print_error "Error: wjm executable not found in current directory"
    print_info "Please run this script from the src/ directory"
    exit 1
fi

# Run the wizard
main

exit 0
