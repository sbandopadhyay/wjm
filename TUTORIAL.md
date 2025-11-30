# WJM Tutorial

## 1. Basics

### Submit a Job

```bash
# Create job
cat > hello.run << 'EOF'
#!/bin/bash
echo "Hello from WJM!"
sleep 5
EOF

# Submit
wjm -qrun hello.run

# Check status
wjm -status
```

### Job Metadata

```bash
cat > job.run << 'EOF'
#!/bin/bash
# WEIGHT: 50
# PRIORITY: high
# GPU: 0
# TIMEOUT: 2h
# RETRY: 3
echo "Running..."
EOF

wjm -qrun job.run
```

### Command-Line Options

```bash
wjm -qrun script.sh --weight 100 --priority urgent --name "my-job"
wjm -qrun script.sh --timeout 2h --retry 3 --cpu 4 --memory 8G
wjm -srun quick.sh    # Run immediately (bypass queue)
```

## 2. Job Control

```bash
wjm -pause job_001    # Pause
wjm -resume job_001   # Resume
wjm -kill job_001     # Kill
wjm -kill all         # Kill all
wjm -resubmit job_001 # Retry failed job
```

## 3. Monitoring

```bash
wjm -status           # Current jobs
wjm -list             # All jobs
wjm -info job_001     # Job details
wjm -logs job_001     # View logs
wjm -logs job_001 --follow  # Live log
wjm -watch job_001    # Watch job
wjm -tui              # Interactive TUI
wjm -dashboard        # Real-time dashboard
```

## 4. Advanced Features

### Dependencies

```bash
wjm -qrun preprocess.sh --name "step1"
wjm -qrun analyze.sh --depends-on job_001 --name "step2"
```

### Templates

```bash
wjm -template save my_template job_001
wjm -template use my_template new_script.sh
wjm -template list
```

### Export/Import (v1.0)

```bash
wjm -export job_001 --format yaml -o config.yaml
wjm -import --config config.yaml new_job.sh --submit
```

### Search

```bash
wjm -search --name training
wjm -search --status COMPLETED
wjm -search --project ml-experiments
```

### Analytics

```bash
wjm -stats                    # Statistics
wjm -compare job_001 job_002  # Compare jobs
wjm -profile job_001          # Performance profile
```

## 5. Engineering Examples

### OpenFOAM

```bash
cat > foam.run << 'EOF'
#!/bin/bash
# WEIGHT: 100
source /opt/openfoam10/etc/bashrc
cd $CASE_DIR
blockMesh && simpleFoam
EOF
wjm -qrun foam.run
```

### Python/GPU

```bash
cat > train.run << 'EOF'
#!/bin/bash
# GPU: 0
# TIMEOUT: 24h
source ~/miniconda3/etc/profile.d/conda.sh
conda activate pytorch
python train.py --epochs 100
EOF
wjm -qrun train.run
```

## 6. Best Practices

- Use meaningful names: `--name "bert-lr0.001"`
- Set appropriate weights: light (10), medium (50-100), heavy (150+)
- Log job info at start/end
- Handle errors with proper exit codes
- Clean up temp files using trap
- Archive completed jobs regularly: `wjm -archive`

## Quick Reference

```bash
# Submit
wjm -qrun <script>
wjm -srun <script>

# Monitor
wjm -status
wjm -info <job_id>
wjm -logs <job_id>
wjm -tui

# Control
wjm -kill <job_id>
wjm -pause <job_id>
wjm -resume <job_id>

# v1.0 Features
wjm -resources
wjm -export <job_id> --format yaml
wjm -import --config file.yaml

# Maintenance
wjm -archive
wjm -clean --failed
```

See [README.md](README.md) for more details.
