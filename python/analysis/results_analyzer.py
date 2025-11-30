#!/usr/bin/env python3
"""
Job Results Analyzer

Analyzes completed jobs and extracts metrics, statistics, and insights.

Usage:
    python results_analyzer.py job_001
    python results_analyzer.py --status COMPLETED --compare
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional
from datetime import datetime


class JobAnalyzer:
    """Analyzer for job logs and results."""

    def __init__(self, job_logs_dir: str = "~/job_logs"):
        """Initialize analyzer with job logs directory."""
        self.job_logs_dir = Path(job_logs_dir).expanduser()

    def get_job_info(self, job_id: str) -> Optional[Dict]:
        """
        Read job.info file and parse metadata.

        Returns:
            Dictionary with job metadata
        """
        job_path = self.job_logs_dir / job_id
        info_file = job_path / "job.info"

        if not info_file.exists():
            # Check archives
            archive_dir = self.job_logs_dir / "archive"
            for batch_dir in archive_dir.glob("[0-9][0-9][0-9]"):
                info_file = batch_dir / job_id / "job.info"
                if info_file.exists():
                    job_path = batch_dir / job_id
                    break

        if not info_file.exists():
            return None

        # Parse job.info
        info = {}
        with open(info_file, 'r') as f:
            for line in f:
                if '=' in line:
                    key, value = line.strip().split('=', 1)
                    info[key] = value

        return info

    def get_job_logs(self, job_id: str) -> Optional[str]:
        """Read job log file."""
        job_path = self.job_logs_dir / job_id
        log_file = job_path / f"{job_id}.log"

        if not log_file.exists():
            # Check archives
            archive_dir = self.job_logs_dir / "archive"
            for batch_dir in archive_dir.glob("[0-9][0-9][0-9]"):
                log_file = batch_dir / job_id / f"{job_id}.log"
                if log_file.exists():
                    break

        if not log_file.exists():
            return None

        with open(log_file, 'r') as f:
            return f.read()

    def extract_metrics(self, logs: str) -> Dict:
        """
        Extract numerical metrics from logs.

        Looks for patterns like:
            Accuracy: 0.95
            Loss: 0.123
            Time: 45.2s
        """
        metrics = {}

        # Common patterns
        patterns = [
            (r'Accuracy[:\s]+([0-9.]+)', 'accuracy'),
            (r'Loss[:\s]+([0-9.]+)', 'loss'),
            (r'Time[:\s]+([0-9.]+)', 'time'),
            (r'Epoch[:\s]+(\d+)', 'epochs'),
            (r'Learning[_\s]?Rate[:\s]+([0-9.e-]+)', 'learning_rate'),
            (r'F1[_\s]?Score[:\s]+([0-9.]+)', 'f1_score'),
            (r'Precision[:\s]+([0-9.]+)', 'precision'),
            (r'Recall[:\s]+([0-9.]+)', 'recall'),
        ]

        for pattern, name in patterns:
            matches = re.findall(pattern, logs, re.IGNORECASE)
            if matches:
                # Take last occurrence (usually final result)
                try:
                    metrics[name] = float(matches[-1])
                except ValueError:
                    metrics[name] = matches[-1]

        return metrics

    def calculate_runtime(self, info: Dict) -> Optional[float]:
        """Calculate job runtime in seconds."""
        start = info.get('START_TIME')
        end = info.get('END_TIME')

        if not start or not end or start == 'N/A' or end == 'N/A':
            return None

        try:
            start_dt = datetime.strptime(start, '%Y-%m-%d %H:%M:%S')
            end_dt = datetime.strptime(end, '%Y-%m-%d %H:%M:%S')
            duration = (end_dt - start_dt).total_seconds()
            return duration if duration >= 0 else None
        except Exception:
            return None

    def analyze_job(self, job_id: str) -> Dict:
        """
        Complete analysis of a single job.

        Returns:
            Dictionary with analysis results
        """
        info = self.get_job_info(job_id)
        if not info:
            return {"error": f"Job {job_id} not found"}

        logs = self.get_job_logs(job_id)
        metrics = self.extract_metrics(logs) if logs else {}
        runtime = self.calculate_runtime(info)

        return {
            "job_id": job_id,
            "name": info.get('JOB_NAME', 'N/A'),
            "status": info.get('STATUS', 'UNKNOWN'),
            "weight": info.get('WEIGHT', '10'),
            "gpu": info.get('GPU', 'N/A'),
            "priority": info.get('PRIORITY', 'normal'),
            "runtime_seconds": runtime,
            "runtime_formatted": self.format_duration(runtime) if runtime else "N/A",
            "metrics": metrics,
            "exit_code": info.get('EXIT_CODE', 'N/A'),
            "user": info.get('USER', 'N/A'),
        }

    def compare_jobs(self, job_ids: List[str]) -> Dict:
        """
        Compare multiple jobs side-by-side.

        Returns:
            Comparison summary
        """
        analyses = [self.analyze_job(jid) for jid in job_ids]

        comparison = {
            "jobs": analyses,
            "best_runtime": None,
            "best_accuracy": None,
            "summary": {}
        }

        # Find best runtime
        valid_runtimes = [
            (a['job_id'], a['runtime_seconds'])
            for a in analyses
            if a.get('runtime_seconds')
        ]
        if valid_runtimes:
            best = min(valid_runtimes, key=lambda x: x[1])
            comparison['best_runtime'] = best[0]

        # Find best accuracy
        valid_accuracy = [
            (a['job_id'], a['metrics'].get('accuracy'))
            for a in analyses
            if a.get('metrics', {}).get('accuracy')
        ]
        if valid_accuracy:
            best = max(valid_accuracy, key=lambda x: x[1])
            comparison['best_accuracy'] = best[0]

        return comparison

    @staticmethod
    def format_duration(seconds: float) -> str:
        """Format duration as human-readable string."""
        minutes = int(seconds // 60)
        secs = int(seconds % 60)
        if minutes > 0:
            return f"{minutes}m {secs}s"
        return f"{secs}s"

    def print_analysis(self, analysis: Dict):
        """Print formatted analysis results."""
        print("=" * 60)
        print(f"Job Analysis: {analysis['job_id']}")
        print("=" * 60)
        print()

        print(f"Name:     {analysis['name']}")
        print(f"Status:   {analysis['status']}")
        print(f"Runtime:  {analysis['runtime_formatted']}")
        print(f"Weight:   {analysis['weight']}")
        print(f"GPU:      {analysis['gpu']}")
        print(f"Priority: {analysis['priority']}")
        print(f"User:     {analysis['user']}")
        print()

        if analysis.get('metrics'):
            print("Extracted Metrics:")
            for key, value in analysis['metrics'].items():
                print(f"  {key:15s}: {value}")
            print()

        print(f"Exit Code: {analysis['exit_code']}")


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Analyze job scheduler results"
    )
    parser.add_argument(
        'job_ids',
        nargs='+',
        help='Job IDs to analyze (e.g., job_001 job_002)'
    )
    parser.add_argument(
        '--compare',
        action='store_true',
        help='Compare multiple jobs'
    )
    parser.add_argument(
        '--logs-dir',
        default='~/job_logs',
        help='Job logs directory (default: ~/job_logs)'
    )

    args = parser.parse_args()

    analyzer = JobAnalyzer(args.logs_dir)

    if len(args.job_ids) == 1 and not args.compare:
        # Single job analysis
        analysis = analyzer.analyze_job(args.job_ids[0])
        if 'error' in analysis:
            print(f"Error: {analysis['error']}", file=sys.stderr)
            sys.exit(1)
        analyzer.print_analysis(analysis)

    else:
        # Compare multiple jobs
        comparison = analyzer.compare_jobs(args.job_ids)

        print("=" * 60)
        print(f"Comparing {len(args.job_ids)} jobs")
        print("=" * 60)
        print()

        for analysis in comparison['jobs']:
            if 'error' not in analysis:
                print(f"{analysis['job_id']}: {analysis['name']}")
                print(f"  Status: {analysis['status']}")
                print(f"  Runtime: {analysis['runtime_formatted']}")
                if analysis['metrics']:
                    for key, value in list(analysis['metrics'].items())[:3]:
                        print(f"  {key}: {value}")
                print()

        if comparison['best_runtime']:
            print(f"Fastest: {comparison['best_runtime']}")
        if comparison['best_accuracy']:
            print(f"Best Accuracy: {comparison['best_accuracy']}")


if __name__ == "__main__":
    main()
