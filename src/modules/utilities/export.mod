#!/bin/bash
# export.mod - Export job configurations
# v1.0 Feature: Export job settings for reuse or sharing

# Parse arguments
JOB_ID=""
OUTPUT_FILE=""
FORMAT="yaml"  # Default format

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            if [[ -z "$2" ]]; then
                error_msg "--format flag requires a value (yaml, json, shell)"
                exit 1
            fi
            FORMAT="$2"
            shift 2
            ;;
        --output|-o)
            if [[ -z "$2" ]]; then
                error_msg "--output flag requires a file path"
                exit 1
            fi
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            if [[ -z "$JOB_ID" ]]; then
                JOB_ID="$1"
            fi
            shift
            ;;
    esac
done

# Validate input
if [[ -z "$JOB_ID" ]]; then
    error_msg "Please specify a job ID to export"
    echo "Usage: $SCRIPT_NAME -export <job_id> [--format yaml|json|shell] [--output file]"
    exit 1
fi

# Validate format
case "$FORMAT" in
    yaml|json|shell) ;;
    *)
        error_msg "Invalid format: $FORMAT (use yaml, json, or shell)"
        exit 1
        ;;
esac

# Find the job
JOB_PATH=""
if [[ -d "$JOB_DIR/$JOB_ID" ]]; then
    JOB_PATH="$JOB_DIR/$JOB_ID"
elif [[ -d "$ARCHIVE_DIR/$JOB_ID" ]]; then
    JOB_PATH="$ARCHIVE_DIR/$JOB_ID"
else
    error_msg "Job '$JOB_ID' not found"
    exit 1
fi

# Read job.info
if [[ ! -f "$JOB_PATH/job.info" ]]; then
    error_msg "Job info not found for '$JOB_ID'"
    exit 1
fi

# Parse job info (don't source, parse safely)
while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    case "$key" in
        JOB_NAME) JOB_NAME="$value" ;;
        JOB_FILE) JOB_FILE="$value" ;;
        WEIGHT) WEIGHT="$value" ;;
        GPU) GPU="$value" ;;
        PRIORITY) PRIORITY="$value" ;;
        TIMEOUT) TIMEOUT="$value" ;;
        RETRY_MAX) RETRY_MAX="$value" ;;
        RETRY_DELAY) RETRY_DELAY="$value" ;;
        RETRY_ON) RETRY_ON="$value" ;;
        CPU) CPU="$value" ;;
        MEMORY) MEMORY="$value" ;;
        PROJECT) PROJECT="$value" ;;
        GROUP) GROUP="$value" ;;
        PRE_HOOK) PRE_HOOK="$value" ;;
        POST_HOOK) POST_HOOK="$value" ;;
        ON_FAIL) ON_FAIL="$value" ;;
        ON_SUCCESS) ON_SUCCESS="$value" ;;
    esac
done < "$JOB_PATH/job.info"

# Export function for YAML format
export_yaml() {
    cat <<EOF
# WJM Job Export
# Exported: $(date '+%Y-%m-%d %H:%M:%S')
# Source Job: $JOB_ID

job:
  name: "${JOB_NAME:-}"
  file: "${JOB_FILE:-}"

resources:
  weight: ${WEIGHT:-10}
  gpu: "${GPU:-N/A}"
  cpu: "${CPU:-N/A}"
  memory: "${MEMORY:-N/A}"

scheduling:
  priority: "${PRIORITY:-normal}"
  timeout: "${TIMEOUT:-N/A}"

retry:
  max: ${RETRY_MAX:-0}
  delay: ${RETRY_DELAY:-60}
  on_codes: "${RETRY_ON:-N/A}"

organization:
  project: "${PROJECT:-N/A}"
  group: "${GROUP:-N/A}"

hooks:
  pre: "${PRE_HOOK:-N/A}"
  post: "${POST_HOOK:-N/A}"
  on_fail: "${ON_FAIL:-N/A}"
  on_success: "${ON_SUCCESS:-N/A}"
EOF
}

# Export function for JSON format
export_json() {
    cat <<EOF
{
  "_meta": {
    "exported": "$(date '+%Y-%m-%d %H:%M:%S')",
    "source_job": "$JOB_ID",
    "wjm_version": "${WJM_VERSION:-1.0}"
  },
  "job": {
    "name": "${JOB_NAME:-}",
    "file": "${JOB_FILE:-}"
  },
  "resources": {
    "weight": ${WEIGHT:-10},
    "gpu": "${GPU:-N/A}",
    "cpu": "${CPU:-N/A}",
    "memory": "${MEMORY:-N/A}"
  },
  "scheduling": {
    "priority": "${PRIORITY:-normal}",
    "timeout": "${TIMEOUT:-N/A}"
  },
  "retry": {
    "max": ${RETRY_MAX:-0},
    "delay": ${RETRY_DELAY:-60},
    "on_codes": "${RETRY_ON:-N/A}"
  },
  "organization": {
    "project": "${PROJECT:-N/A}",
    "group": "${GROUP:-N/A}"
  },
  "hooks": {
    "pre": "${PRE_HOOK:-N/A}",
    "post": "${POST_HOOK:-N/A}",
    "on_fail": "${ON_FAIL:-N/A}",
    "on_success": "${ON_SUCCESS:-N/A}"
  }
}
EOF
}

# Export function for shell format (can be sourced)
export_shell() {
    cat <<EOF
#!/bin/bash
# WJM Job Export - Shell Format
# Exported: $(date '+%Y-%m-%d %H:%M:%S')
# Source Job: $JOB_ID
# Usage: source this file, then run your job script

# Job metadata directives (add to job file header)
# These can be placed at the top of your job script:
#
# # WEIGHT: ${WEIGHT:-10}
# # GPU: ${GPU:-N/A}
# # CPU: ${CPU:-N/A}
# # MEMORY: ${MEMORY:-N/A}
# # PRIORITY: ${PRIORITY:-normal}
# # TIMEOUT: ${TIMEOUT:-N/A}
# # RETRY: ${RETRY_MAX:-0}
# # RETRY_DELAY: ${RETRY_DELAY:-60}
# # RETRY_ON: ${RETRY_ON:-N/A}
# # PROJECT: ${PROJECT:-N/A}
# # GROUP: ${GROUP:-N/A}
# # PRE_HOOK: ${PRE_HOOK:-N/A}
# # POST_HOOK: ${POST_HOOK:-N/A}
# # ON_FAIL: ${ON_FAIL:-N/A}
# # ON_SUCCESS: ${ON_SUCCESS:-N/A}

# Environment variables for command-line submission
export WJM_WEIGHT="${WEIGHT:-10}"
export WJM_GPU="${GPU:-N/A}"
export WJM_CPU="${CPU:-N/A}"
export WJM_MEMORY="${MEMORY:-N/A}"
export WJM_PRIORITY="${PRIORITY:-normal}"
export WJM_TIMEOUT="${TIMEOUT:-N/A}"
export WJM_RETRY="${RETRY_MAX:-0}"
export WJM_PROJECT="${PROJECT:-N/A}"

# Command to submit with these settings:
# wjm -qrun your_job.run \\
#   --priority "${PRIORITY:-normal}" \\
#   --timeout "${TIMEOUT:-N/A}" \\
#   --retry "${RETRY_MAX:-0}" \\
#   --project "${PROJECT:-N/A}" \\
#   --cpu "${CPU:-N/A}" \\
#   --memory "${MEMORY:-N/A}"
EOF
}

# Generate output
case "$FORMAT" in
    yaml)
        if [[ -n "$OUTPUT_FILE" ]]; then
            export_yaml > "$OUTPUT_FILE"
            echo "Exported to: $OUTPUT_FILE (YAML format)"
        else
            export_yaml
        fi
        ;;
    json)
        if [[ -n "$OUTPUT_FILE" ]]; then
            export_json > "$OUTPUT_FILE"
            echo "Exported to: $OUTPUT_FILE (JSON format)"
        else
            export_json
        fi
        ;;
    shell)
        if [[ -n "$OUTPUT_FILE" ]]; then
            export_shell > "$OUTPUT_FILE"
            chmod +x "$OUTPUT_FILE"
            echo "Exported to: $OUTPUT_FILE (Shell format)"
        else
            export_shell
        fi
        ;;
esac
