#!/bin/bash
cat << EOF
WJM - Workstation Job Manager v1.0
==================================

USAGE:
  $SCRIPT_NAME [COMMAND] [ARGUMENT]

COMMANDS:
  Job Submission:
    -srun <job.run> [OPTIONS]    Run job immediately (bypasses queue)
    -qrun <job.run> [OPTIONS]    Run job with intelligent queuing

  Job Control:
    -kill <job_id/all>           Stop a job or all jobs (including queued)
    -pause <job_id>              Pause a running job (can be resumed later)
    -resume <job_id>             Resume a paused job
    -signal <job_id> <sig>       Send custom signal to job (SIGTERM, SIGUSR1, etc)
    -resubmit <job_id>           Resubmit a completed/failed job

  Monitoring:
    -status                      Show running and queued jobs with details
    -list [--status STATUS]      Show all jobs (filter by status)
    -info <job_id>               Show detailed info for a specific job
    -logs <job_id>               View logs for a specific job
    -watch <job_id/all>          Monitor jobs in real-time
    -dashboard                   Real-time dashboard with auto-refresh
    -tui                         Interactive TUI (like htop) - full-screen mode

  Analytics & Comparison:
    -stats                       Show overall scheduler statistics
    -visual                      Visual timeline of job execution
    -compare <id1> <id2>         Compare two jobs side-by-side
    -profile <job_id>            Monitor CPU/memory usage for running job
    -search [OPTIONS]            Search jobs by name, status, priority, date

  Advanced Features:
    -template <action>           Save/use job templates for quick submission
    -abtest <script> <n>         Run A/B tests with different parameters
    -checkpoint <action>         Save/restore job checkpoints for recovery

  v1.0 Features:
    -resources                   Show system resources (CPU, memory, GPU)
    -validate-config             Validate configuration file
    -export <job_id> [OPTIONS]   Export job configuration to file
    -import --config <file>      Import job configuration from file

  Maintenance:
    -archive                     Move completed jobs to archive
    -clean [--failed/--old]      Clean up completed/failed/old jobs
    -manage-logs                 Manage job logs (rotation, compression, cleanup)

  General:
    --config <path>              Use a custom config file
    --help, -h                   Show this help message
    --version, -v                Show version information
    -doctor                      Run system health check

SUBMISSION OPTIONS (v1.0):
  --name "Name"                  Friendly name for the job
  --priority <level>             Priority: urgent, high, normal, low
  --preset <name>                Preset: small, medium, large, gpu, urgent
  --depends-on <job_ids>         Comma-separated job IDs to wait for
  --timeout <duration>           Time limit (e.g., 2h, 30m, 1d)
  --retry <count>                Max retry attempts on failure
  --project <name>               Project/group name for organization
  --cpu <spec>                   CPU affinity (e.g., 4, 0-3, 0,2,4)
  --memory <limit>               Memory limit (e.g., 8G, 512M, 50%)
  --array <spec>                 Job array (e.g., 1-100, 1-100:10)

JOB FILE METADATA (v1.0):
  Basic:
    # WEIGHT: <number>           Job weight (default: 10)
    # GPU: <spec>                GPU IDs (0,1,2) or 'auto' or 'auto:N'
    # PRIORITY: <level>          urgent, high, normal, low

  Resource Limits:
    # CPU: <spec>                CPU affinity (0-3, 0,2,4, or just count: 4)
    # CORES: <count>             Number of CPU cores (alias for CPU count)
    # MEMORY: <limit>            Memory limit (8G, 512M, 50%)
    # TIMEOUT: <duration>        Time limit (2h, 30m, 1d, 3600)

  Retry & Recovery:
    # RETRY: <count>             Max retry attempts
    # RETRY_DELAY: <seconds>     Delay between retries (default: 60)
    # RETRY_ON: <codes>          Only retry on specific exit codes (1,2,137)

  Organization:
    # PROJECT: <name>            Project name
    # GROUP: <name>              Group name

  Hooks:
    # PRE_HOOK: <command>        Run before job starts
    # POST_HOOK: <command>       Run after job completes (success or fail)
    # ON_FAIL: <command>         Run only on failure
    # ON_SUCCESS: <command>      Run only on success

EXAMPLE JOB FILES:

  Simple job:
    #!/bin/bash
    echo "Hello, World!"
    python my_script.py

  GPU training with timeout:
    #!/bin/bash
    # WEIGHT: 50
    # GPU: auto:2
    # TIMEOUT: 24h
    # RETRY: 3
    # PROJECT: ml-experiments
    python train_model.py

  CPU-intensive with limits:
    #!/bin/bash
    # WEIGHT: 30
    # CPU: 0-7
    # MEMORY: 16G
    # TIMEOUT: 2h
    ./heavy_computation

  With hooks:
    #!/bin/bash
    # WEIGHT: 25
    # PRE_HOOK: echo "Starting job" | mail -s "Job Started" user@example.com
    # ON_FAIL: echo "Job failed" | mail -s "Job Failed" user@example.com
    # ON_SUCCESS: echo "Job done" | mail -s "Job Complete" user@example.com
    ./my_pipeline.sh

EXAMPLES:

  Basic Usage:
    $SCRIPT_NAME -srun quick_test.run
    $SCRIPT_NAME -qrun train.run --name "Training v1"
    $SCRIPT_NAME -status
    $SCRIPT_NAME -watch job_001

  v1.0 Features:
    # Show system resources
    $SCRIPT_NAME -resources

    # Submit with timeout and retry
    $SCRIPT_NAME -qrun train.run --timeout 2h --retry 3

    # Submit with CPU/memory limits
    $SCRIPT_NAME -qrun compute.run --cpu 4 --memory 8G

    # Submit job array (100 parallel tasks)
    $SCRIPT_NAME -qrun batch.run --array 1-100

    # Export job config for reuse
    $SCRIPT_NAME -export job_001 --format yaml -o config.yaml

    # Import and submit with same config
    $SCRIPT_NAME -import --config config.yaml new_job.run --submit

    # List jobs by project
    $SCRIPT_NAME -search --project ml-experiments

  Advanced:
    # Pause and resume jobs
    $SCRIPT_NAME -pause job_001
    $SCRIPT_NAME -resume job_001

    # Save job as template
    $SCRIPT_NAME -template save my_training job_001
    $SCRIPT_NAME -template use my_training new_script.py

    # Compare two jobs
    $SCRIPT_NAME -compare job_001 job_002

    # Interactive TUI
    $SCRIPT_NAME -tui

CONFIGURATION:
  Edit wjm.config to customize:
    - JOB_DIR              Job log directory
    - MAX_CONCURRENT_JOBS  Maximum simultaneous jobs
    - MAX_TOTAL_WEIGHT     Maximum total weight
    - DEFAULT_JOB_WEIGHT   Default weight for jobs
    - ARCHIVE_THRESHOLD    Jobs before auto-archive

ENVIRONMENT VARIABLES:
  CUDA_VISIBLE_DEVICES    Automatically set based on GPU: directive
  WJM_ARRAY_INDEX         Current index in job array
  WJM_ARRAY_ID            Array job identifier
  WJM_ARRAY_SIZE          Total jobs in array

For more information, see README.md
EOF
