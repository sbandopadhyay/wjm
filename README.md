# WJM - Workstation Job Manager

Version 1.0.0 - Job scheduler for single workstations

## What is WJM?

WJM is a lightweight job scheduler for single workstation environments. Ideal for researchers, engineers, and developers who need job management without cluster complexity.

**Features:** Pure bash, no dependencies, weight-based scheduling, GPU management, priority queues, real-time monitoring.

## Quick Start

```bash
# Install
git clone https://github.com/sbandopadhyay/wjm.git
cd wjm/src
./setup_wizard.sh   # Or: cp wjm.config.example wjm.config

# Submit a job
wjm -qrun my_script.sh

# Check status
wjm -status
```

## Commands

```bash
# Job Submission
wjm -qrun <script>              # Queue job
wjm -srun <script>              # Run immediately
wjm -qrun job.sh --timeout 2h --retry 3 --cpu 4 --memory 8G  # v1.1 options

# Monitoring
wjm -status                     # Current jobs
wjm -list                       # All jobs
wjm -info <job_id>              # Job details
wjm -logs <job_id>              # View logs
wjm -tui                        # Interactive interface
wjm -dashboard                  # Real-time dashboard

# Control
wjm -kill <job_id>              # Kill job
wjm -pause <job_id>             # Pause job
wjm -resume <job_id>            # Resume job
wjm -resubmit <job_id>          # Retry job

# v1.1 Features
wjm -resources                  # Show system resources
wjm -validate-config            # Validate configuration
wjm -export <job_id> --format yaml  # Export job config
wjm -import --config file.yaml job.sh --submit  # Import and submit

# Analytics
wjm -stats                      # Job statistics
wjm -search --status COMPLETED  # Search jobs
wjm -compare job_001 job_002    # Compare jobs

# Maintenance
wjm -archive                    # Archive completed jobs
wjm -clean --failed             # Clean failed jobs
```

## Job File Format

```bash
#!/bin/bash
# WEIGHT: 50
# GPU: 0,1
# PRIORITY: high
# TIMEOUT: 2h
# RETRY: 3
# CPU: 0-7
# MEMORY: 16G
# PROJECT: my-project

echo "Running job..."
python train.py
```

## Configuration

Edit `wjm.config`:

```bash
JOB_DIR=$HOME/job_logs
MAX_CONCURRENT_JOBS=4
MAX_TOTAL_WEIGHT=100
DEFAULT_JOB_WEIGHT=10
```

## Documentation

- [INSTALL.md](INSTALL.md) - Installation guide
- [TUTORIAL.md](TUTORIAL.md) - Usage tutorial
- [CHANGELOG.md](CHANGELOG.md) - Version history
- `examples/` - Example jobs

## Requirements

- Linux or macOS
- Bash 4.0+
- Optional: nvidia-smi (GPU), gzip (compression)

## License

MIT License

## Author

Somdeb Bandopadhyay
