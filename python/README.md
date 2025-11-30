# Python Utilities

Python helper libraries and analysis tools for the Job Scheduler.

## Contents

- **job_helpers.py** - Python API for job submission and management
- **analysis/results_analyzer.py** - Tool for analyzing and comparing job results

---

## job_helpers.py

Python library for programmatically interacting with the Job Scheduler.

### Quick Start

```python
from job_helpers import submit_job, wait_for_job, get_logs

# Submit a job
job_id = submit_job(
    "train.py",
    weight=50,
    gpu="0",
    priority="high",
    name="Model Training"
)

print(f"Submitted: {job_id}")

# Wait for completion
success = wait_for_job(job_id)

# Get logs
logs = get_logs(job_id)
print(logs)
```

### Available Functions

- **submit_job()** - Submit a job with custom parameters
- **get_status()** - Get job status
- **wait_for_job()** - Block until job completes
- **kill_job()** - Stop a job
- **pause_job()** - Pause a running job
- **resume_job()** - Resume a paused job
- **get_logs()** - Retrieve job logs
- **search_jobs()** - Search for jobs by criteria

### Example: Batch Submission

```python
from job_helpers import submit_job

# Submit multiple experiments
job_ids = []
for lr in [0.001, 0.01, 0.1]:
    job_id = submit_job(
        "train.py",
        name=f"LR_{lr}",
        weight=50
    )
    job_ids.append(job_id)

print(f"Submitted {len(job_ids)} jobs")
```

---

## results_analyzer.py

Command-line tool for analyzing job results and extracting metrics.

### Usage

**Analyze a single job:**
```bash
python analysis/results_analyzer.py job_001
```

Output:
```
============================================================
Job Analysis: job_001
============================================================

Name:     Model Training
Status:   COMPLETED
Runtime:  5m 23s
Weight:   50
GPU:      0
Priority: high
User:     username

Extracted Metrics:
  accuracy       : 0.95
  loss           : 0.123
  epochs         : 10

Exit Code: 0
```

**Compare multiple jobs:**
```bash
python analysis/results_analyzer.py job_001 job_002 job_003 --compare
```

Output:
```
============================================================
Comparing 3 jobs
============================================================

job_001: Model Training v1
  Status: COMPLETED
  Runtime: 5m 23s
  accuracy: 0.95

job_002: Model Training v2
  Status: COMPLETED
  Runtime: 4m 18s
  accuracy: 0.97

job_003: Model Training v3
  Status: COMPLETED
  Runtime: 6m 02s
  accuracy: 0.93

Fastest: job_002
Best Accuracy: job_002
```

### Automatic Metric Extraction

The analyzer automatically detects common metrics in logs:
- Accuracy
- Loss
- Precision / Recall / F1 Score
- Learning Rate
- Epochs
- Custom metrics (extensible)

### Custom Logs Directory

```bash
python analysis/results_analyzer.py job_001 --logs-dir /custom/path/job_logs
```

---

## Integration Examples

### Example 1: Automated Experiment Runner

```python
#!/usr/bin/env python3
from job_helpers import submit_job, wait_for_job
from analysis.results_analyzer import JobAnalyzer

# Submit experiments
experiments = [
    {"lr": 0.001, "batch": 32},
    {"lr": 0.01, "batch": 64},
    {"lr": 0.1, "batch": 128}
]

job_ids = []
for exp in experiments:
    job_id = submit_job(
        "train.py",
        name=f"LR_{exp['lr']}_BATCH_{exp['batch']}",
        weight=50,
        gpu="0"
    )
    job_ids.append(job_id)
    print(f"Submitted {job_id}")

# Wait for all to complete
print("\nWaiting for jobs to complete...")
for job_id in job_ids:
    wait_for_job(job_id)
    print(f"{job_id} completed")

# Analyze results
analyzer = JobAnalyzer()
comparison = analyzer.compare_jobs(job_ids)

print(f"\nBest job: {comparison['best_accuracy']}")
```

### Example 2: Continuous Monitoring

```python
#!/usr/bin/env python3
import time
from job_helpers import submit_job, get_status

job_id = submit_job("long_training.py", weight=100, gpu="0")

print(f"Monitoring {job_id}...")
while True:
    status = get_status(job_id)
    print(status['output'])

    if 'COMPLETED' in status['output'] or 'FAILED' in status['output']:
        break

    time.sleep(10)

print("Job finished!")
```

---

## Requirements

- Python 3.6+
- Job Scheduler installed in `../src/`

No external dependencies required - uses only Python standard library.

---

## Extending the Library

### Adding Custom Metric Extractors

Edit `analysis/results_analyzer.py`:

```python
patterns = [
    (r'MyMetric[:\s]+([0-9.]+)', 'my_metric'),
    # Add more patterns here
]
```

### Adding New Helper Functions

Edit `job_helpers.py`:

```python
def my_custom_function(job_id: str):
    """My custom helper function."""
    cmd = [str(SCHEDULER), "-custom-command", job_id]
    result = subprocess.run(cmd, capture_output=True)
    return result.returncode == 0
```

---

## Future Enhancements

Planned features for Python utilities:

- **Jupyter Integration** - Submit jobs from notebooks
- **Progress Bars** - Visual progress for wait_for_job()
- **Pandas DataFrame Export** - Export job results to DataFrame
- **Plotting** - Visualize job timelines and metrics
- **REST API** - Web interface for remote job submission

---

## Learn More

- **Tutorials**: See `../tutorials/` for usage examples
- **Documentation**: See `../docs/` for scheduler details
- **Examples**: See `../examples/` for job file examples
