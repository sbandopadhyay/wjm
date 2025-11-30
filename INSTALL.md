# Installation Guide - WJM

## Prerequisites

- Linux or macOS
- Bash 4.0+
- Optional: git, nvidia-smi (GPU), gzip (compression)

## Installation

### Method 1: Git Clone (Recommended)

```bash
git clone https://github.com/sbandopadhyay/wjm.git
cd wjm/src
./setup_wizard.sh
```

### Method 2: Manual Setup

```bash
git clone https://github.com/sbandopadhyay/wjm.git
cd wjm/src
cp wjm.config.example wjm.config
nano wjm.config

mkdir -p ~/job_logs/{queue,archive}
chmod +x wjm
```

## Configuration

Edit `wjm.config`:

```bash
JOB_DIR=$HOME/job_logs
QUEUE_DIR=$JOB_DIR/queue
ARCHIVE_DIR=$JOB_DIR/archive
MAX_CONCURRENT_JOBS=4
MAX_TOTAL_WEIGHT=100
DEFAULT_JOB_WEIGHT=10
ARCHIVE_THRESHOLD=100
```

## Add to PATH (Recommended)

```bash
echo 'export PATH="$HOME/wjm/src:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Verification

```bash
wjm --help
wjm -status

# Test job
echo -e '#!/bin/bash\necho "WJM works!"' > /tmp/test.run
wjm -srun /tmp/test.run
wjm -list
```

## Directory Structure

```
~/wjm/src/          # Installation
~/job_logs/         # Job data (auto-created)
  job_001/          # Job directories
  queue/            # Queue
  archive/          # Archive
```

## Troubleshooting

**Command not found:** Add to PATH or use full path `~/wjm/src/wjm`

**Permission denied:** `chmod +x ~/wjm/src/wjm`

**Config not found:** Run `./setup_wizard.sh` or create manually

## Updating

```bash
cd ~/wjm
cp src/wjm.config src/wjm.config.backup
git pull origin main
```

## Uninstall

```bash
wjm -kill all
rm -rf ~/wjm ~/job_logs
```

See [TUTORIAL.md](TUTORIAL.md) to get started.
