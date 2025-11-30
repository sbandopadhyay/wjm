#!/usr/bin/env python3
"""
Job Scheduler Python Helper Library

This module provides Python utilities for interacting with the
Job Scheduler from Python scripts.

Usage:
    from job_helpers import submit_job, get_status, wait_for_job

    job_id = submit_job("my_script.sh", weight=50, gpu="0")
    wait_for_job(job_id)
    print(f"Job {job_id} completed!")
"""

import subprocess
import os
import sys
import time
from pathlib import Path
from typing import Optional, Dict, List


# Find the wjm executable
def find_scheduler() -> Path:
    """Find the wjm (Workstation Job Manager) executable."""
    current_dir = Path(__file__).parent
    scheduler_path = current_dir.parent / "src" / "wjm"

    if not scheduler_path.exists():
        raise FileNotFoundError(
            f"wjm executable not found at {scheduler_path}. "
            "Please ensure you're running from the wjm directory."
        )

    return scheduler_path


SCHEDULER = find_scheduler()


def submit_job(
    script: str,
    name: Optional[str] = None,
    weight: int = 10,
    gpu: Optional[str] = None,
    priority: str = "normal",
    immediate: bool = False
) -> str:
    """
    Submit a job to the scheduler.

    Args:
        script: Path to the job script
        name: Custom job name (optional)
        weight: Job weight (default: 10)
        gpu: GPU assignment (e.g., "0" or "0,1")
        priority: Job priority (urgent, high, normal, low)
        immediate: If True, use -srun (immediate), else -qrun (queued)

    Returns:
        Job ID (e.g., "job_001")

    Example:
        job_id = submit_job("train.py", weight=50, gpu="0", priority="high")
    """
    # Validate input parameters
    if not isinstance(weight, int) or weight < 1 or weight > 1000:
        raise ValueError(f"Weight must be an integer between 1 and 1000, got {weight}")

    valid_priorities = ("urgent", "high", "normal", "low")
    if priority not in valid_priorities:
        raise ValueError(f"Priority must be one of {valid_priorities}, got '{priority}'")

    if gpu is not None:
        # Validate GPU spec format
        if not all(c.isdigit() or c == ',' for c in str(gpu).strip()):
            raise ValueError(f"Invalid GPU specification: {gpu}. Must be comma-separated digits (e.g., '0' or '0,1')")

    # Create temporary job file with metadata
    script_path = Path(script)
    if not script_path.exists():
        raise FileNotFoundError(f"Script not found: {script}")

    # Build job file content
    lines = []
    if weight != 10:
        lines.append(f"# WEIGHT: {weight}")
    if gpu:
        lines.append(f"# GPU: {gpu}")
    if priority != "normal":
        lines.append(f"# PRIORITY: {priority}")

    # Add script content
    with open(script, 'r') as f:
        lines.append(f.read())

    # Write temporary job file
    import tempfile
    with tempfile.NamedTemporaryFile(
        mode='w',
        suffix='.run',
        delete=False
    ) as tmp:
        tmp.write('\n'.join(lines))
        tmp_path = tmp.name

    try:
        # Submit job
        cmd = [str(SCHEDULER)]
        cmd.append("-srun" if immediate else "-qrun")
        cmd.append(tmp_path)
        if name:
            cmd.extend(["--name", name])

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False  # We'll check manually for better error messages
            )

            if result.returncode != 0:
                error_msg = result.stderr if result.stderr else result.stdout
                raise RuntimeError(f"Job submission failed (exit code {result.returncode}): {error_msg}")

            # Parse job ID from output
            for line in result.stdout.split('\n'):
                if 'job_' in line.lower():
                    # Extract job_XXX
                    import re
                    match = re.search(r'job_\d{3}', line)
                    if match:
                        return match.group(0)

            raise RuntimeError(f"Failed to parse job ID from output: {result.stdout}")

        except subprocess.SubprocessError as e:
            raise RuntimeError(f"Failed to execute scheduler: {e}")

    finally:
        # Clean up temporary file
        try:
            os.unlink(tmp_path)
        except OSError:
            pass  # File might not exist, that's okay


def get_status(job_id: Optional[str] = None) -> Dict:
    """
    Get job status.

    Args:
        job_id: Specific job ID, or None for all jobs

    Returns:
        Dictionary with status information
    """
    cmd = [str(SCHEDULER)]
    if job_id:
        cmd.extend(["-info", job_id])
    else:
        cmd.append("-status")

    result = subprocess.run(cmd, capture_output=True, text=True)

    # Parse output (simplified - full parsing would be more complex)
    return {
        "output": result.stdout,
        "success": result.returncode == 0
    }


def wait_for_job(job_id: str, poll_interval: int = 5) -> bool:
    """
    Wait for a job to complete.

    Args:
        job_id: Job ID to wait for
        poll_interval: Seconds between status checks

    Returns:
        True if job completed successfully, False if failed
    """
    while True:
        result = get_status(job_id)
        output = result["output"]

        if "COMPLETED" in output:
            return True
        elif "FAILED" in output:
            return False
        elif "RUNNING" in output or "QUEUED" in output:
            time.sleep(poll_interval)
        else:
            # Job not found or other issue
            return False


def kill_job(job_id: str) -> bool:
    """Kill a running or queued job."""
    cmd = [str(SCHEDULER), "-kill", job_id]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0 and result.stderr:
            print(f"Error killing job: {result.stderr}", file=sys.stderr)
        return result.returncode == 0
    except subprocess.SubprocessError as e:
        print(f"Failed to kill job: {e}", file=sys.stderr)
        return False


def pause_job(job_id: str) -> bool:
    """Pause a running job."""
    cmd = [str(SCHEDULER), "-pause", job_id]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0 and result.stderr:
            print(f"Error pausing job: {result.stderr}", file=sys.stderr)
        return result.returncode == 0
    except subprocess.SubprocessError as e:
        print(f"Failed to pause job: {e}", file=sys.stderr)
        return False


def resume_job(job_id: str) -> bool:
    """Resume a paused job."""
    cmd = [str(SCHEDULER), "-resume", job_id]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0 and result.stderr:
            print(f"Error resuming job: {result.stderr}", file=sys.stderr)
        return result.returncode == 0
    except subprocess.SubprocessError as e:
        print(f"Failed to resume job: {e}", file=sys.stderr)
        return False


def get_logs(job_id: str) -> str:
    """Get job logs."""
    cmd = [str(SCHEDULER), "-logs", job_id]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Warning: Failed to get logs (exit code {result.returncode})", file=sys.stderr)
        return result.stdout
    except subprocess.SubprocessError as e:
        print(f"Error getting logs: {e}", file=sys.stderr)
        return ""


def search_jobs(
    name: Optional[str] = None,
    status: Optional[str] = None,
    priority: Optional[str] = None
) -> List[str]:
    """
    Search for jobs.

    Args:
        name: Search by name pattern
        status: Filter by status (RUNNING, COMPLETED, FAILED, etc.)
        priority: Filter by priority (urgent, high, normal, low)

    Returns:
        List of matching job IDs
    """
    cmd = [str(SCHEDULER), "-search"]
    if name:
        cmd.extend(["--name", name])
    if status:
        cmd.extend(["--status", status])
    if priority:
        cmd.extend(["--priority", priority])

    result = subprocess.run(cmd, capture_output=True, text=True)

    # Parse job IDs from output
    import re
    job_ids = re.findall(r'job_\d{3}', result.stdout)
    return list(set(job_ids))  # Remove duplicates


# Example usage
if __name__ == "__main__":
    print("Job Scheduler Python Helper Library")
    print("=" * 50)
    print()
    print("Example usage:")
    print()
    print("  from job_helpers import submit_job, wait_for_job")
    print()
    print("  # Submit a job")
    print("  job_id = submit_job('train.py', weight=50, gpu='0')")
    print("  print(f'Submitted: {job_id}')")
    print()
    print("  # Wait for completion")
    print("  success = wait_for_job(job_id)")
    print("  print(f'Job completed: {success}')")
    print()
    print("  # Get logs")
    print("  logs = get_logs(job_id)")
    print("  print(logs)")
