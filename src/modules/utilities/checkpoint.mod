#!/bin/bash
# checkpoint.mod - Job Checkpoints & Resume

ACTION="$1"
JOB_ID="$2"

if [[ -z "$ACTION" ]]; then
    echo " Job Checkpoints & Resume"
    echo "========================================================"
    echo ""
    echo "Save job state and resume from checkpoints."
    echo ""
    echo "Usage: $SCRIPT_NAME -checkpoint <action> [job_id]"
    echo ""
    echo "Actions:"
    echo "  save <job_id>       Manually save checkpoint for running job"
    echo "  list <job_id>       List all checkpoints for a job"
    echo "  restore <job_id>    Restore job from latest checkpoint"
    echo "  enable <job_id>     Enable auto-checkpointing for job"
    echo "  disable <job_id>    Disable auto-checkpointing for job"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME -checkpoint save job_001"
    echo "  $SCRIPT_NAME -checkpoint list job_001"
    echo "  $SCRIPT_NAME -checkpoint restore job_001"
    echo ""
    echo "To use checkpoints in your job script:"
    echo "   source \$CHECKPOINT_HELPER"
    echo "   save_checkpoint \"training_epoch_10\""
    echo "   restore_checkpoint"
    exit 0
fi

CHECKPOINT_DIR="$JOB_DIR/.checkpoints"
mkdir -p "$CHECKPOINT_DIR"

case "$ACTION" in
    save)
        if [[ -z "$JOB_ID" ]]; then
            error_msg "Usage: $SCRIPT_NAME -checkpoint save <job_id>"
            exit 1
        fi

        # Validate job ID format
        if [[ ! "$JOB_ID" =~ ^job_[0-9]{3}$ ]]; then
            error_msg "Invalid job ID format: '$JOB_ID'. Expected: job_XXX"
            exit 1
        fi

        JOB_PATH="$JOB_DIR/$JOB_ID"
        if [[ ! -d "$JOB_PATH" ]]; then
            error_msg "Job '$JOB_ID' not found"
            exit 1
        fi

        # Create checkpoint directory for this job
        JOB_CHECKPOINT_DIR="$CHECKPOINT_DIR/$JOB_ID"
        mkdir -p "$JOB_CHECKPOINT_DIR"

        # Generate checkpoint ID
        CHECKPOINT_ID="checkpoint_$(date +%Y%m%d_%H%M%S)"
        CHECKPOINT_PATH="$JOB_CHECKPOINT_DIR/$CHECKPOINT_ID"
        mkdir -p "$CHECKPOINT_PATH"

        # Save job metadata
        cp "$JOB_PATH/job.info" "$CHECKPOINT_PATH/" 2>/dev/null

        # Save environment if exists
        if [[ -f "$JOB_PATH/.env" ]]; then
            cp "$JOB_PATH/.env" "$CHECKPOINT_PATH/"
        fi

        # Save any checkpoint data from job directory
        if [[ -d "$JOB_PATH/checkpoint_data" ]]; then
            cp -r "$JOB_PATH/checkpoint_data" "$CHECKPOINT_PATH/"
        fi

        # Record checkpoint metadata
        cat > "$CHECKPOINT_PATH/metadata.txt" <<EOF
CHECKPOINT_ID=$CHECKPOINT_ID
JOB_ID=$JOB_ID
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
CREATED_EPOCH=$(date +%s)
PID=$(cat "$JOB_PATH/job.pid" 2>/dev/null)
EOF

        echo "Checkpoint saved: $CHECKPOINT_ID"
        echo "   Location: $CHECKPOINT_PATH"
        log_action_safe "Created checkpoint for job $JOB_ID: $CHECKPOINT_ID"
        ;;

    list)
        if [[ -z "$JOB_ID" ]]; then
            error_msg "Usage: $SCRIPT_NAME -checkpoint list <job_id>"
            exit 1
        fi

        # Validate job ID format
        if [[ ! "$JOB_ID" =~ ^job_[0-9]{3}$ ]]; then
            error_msg "Invalid job ID format: '$JOB_ID'. Expected: job_XXX"
            exit 1
        fi

        JOB_CHECKPOINT_DIR="$CHECKPOINT_DIR/$JOB_ID"
        if [[ ! -d "$JOB_CHECKPOINT_DIR" ]]; then
            echo "No checkpoints found for job '$JOB_ID'"
            exit 0
        fi

        echo " Checkpoints for $JOB_ID"
        echo "========================================================"
        echo ""

        checkpoint_count=0
        for checkpoint in "$JOB_CHECKPOINT_DIR"/checkpoint_*; do
            [[ ! -d "$checkpoint" ]] && continue

            checkpoint_id=$(basename "$checkpoint")
            checkpoint_count=$((checkpoint_count + 1))

            if [[ -f "$checkpoint/metadata.txt" ]]; then
                created=$(grep "^CREATED=" "$checkpoint/metadata.txt" 2>/dev/null | cut -d= -f2)
                echo "📍 $checkpoint_id"
                echo "   Created: $created"

                # Show size
                size=$(du -sh "$checkpoint" 2>/dev/null | cut -f1)
                echo "   Size: $size"
                echo ""
            fi
        done

        if [[ $checkpoint_count -eq 0 ]]; then
            echo "No checkpoints found"
        else
            echo "Total: $checkpoint_count checkpoint(s)"
        fi
        ;;

    restore)
        if [[ -z "$JOB_ID" ]]; then
            error_msg "Usage: $SCRIPT_NAME -checkpoint restore <job_id>"
            exit 1
        fi

        # Validate job ID format
        if [[ ! "$JOB_ID" =~ ^job_[0-9]{3}$ ]]; then
            error_msg "Invalid job ID format: '$JOB_ID'. Expected: job_XXX"
            exit 1
        fi

        JOB_CHECKPOINT_DIR="$CHECKPOINT_DIR/$JOB_ID"
        if [[ ! -d "$JOB_CHECKPOINT_DIR" ]]; then
            error_msg "No checkpoints found for job '$JOB_ID'"
            exit 1
        fi

        # Find latest checkpoint using glob and sort (safer than ls)
        shopt -s nullglob
        checkpoints=("$JOB_CHECKPOINT_DIR"/checkpoint_*)
        shopt -u nullglob

        if [[ ${#checkpoints[@]} -eq 0 ]]; then
            error_msg "No checkpoints available"
            exit 1
        fi

        # Get the latest checkpoint by sorting (newest first)
        LATEST_CHECKPOINT=$(printf '%s\n' "${checkpoints[@]}" | sort -r | head -1 | xargs basename)

        CHECKPOINT_PATH="$JOB_CHECKPOINT_DIR/$LATEST_CHECKPOINT"

        echo "Restoring from checkpoint: $LATEST_CHECKPOINT"
        echo ""

        # Restore checkpoint data to job directory
        JOB_PATH="$JOB_DIR/$JOB_ID"
        if [[ ! -d "$JOB_PATH" ]]; then
            warn_msg "Job directory doesn't exist, creating..."
            mkdir -p "$JOB_PATH"
        fi

        # Restore checkpoint data
        if [[ -d "$CHECKPOINT_PATH/checkpoint_data" ]]; then
            cp -r "$CHECKPOINT_PATH/checkpoint_data" "$JOB_PATH/"
            echo "Checkpoint data restored"
        fi

        # Restore environment
        if [[ -f "$CHECKPOINT_PATH/.env" ]]; then
            cp "$CHECKPOINT_PATH/.env" "$JOB_PATH/"
            echo "Environment restored"
        fi

        echo ""
        echo "Checkpoint restored successfully"
        echo ""
        echo "To resume the job, resubmit with:"
        echo "  $SCRIPT_NAME -resubmit $JOB_ID"

        log_action_safe "Restored checkpoint for job $JOB_ID from $LATEST_CHECKPOINT"
        ;;

    enable|disable)
        if [[ -z "$JOB_ID" ]]; then
            error_msg "Usage: $SCRIPT_NAME -checkpoint $ACTION <job_id>"
            exit 1
        fi

        # Validate job ID format
        if [[ ! "$JOB_ID" =~ ^job_[0-9]{3}$ ]]; then
            error_msg "Invalid job ID format: '$JOB_ID'. Expected: job_XXX"
            exit 1
        fi

        JOB_PATH="$JOB_DIR/$JOB_ID"
        if [[ ! -d "$JOB_PATH" ]]; then
            error_msg "Job '$JOB_ID' not found"
            exit 1
        fi

        if [[ "$ACTION" == "enable" ]]; then
            touch "$JOB_PATH/.auto_checkpoint"
            echo "Auto-checkpointing enabled for $JOB_ID"
            echo ""
            echo "Checkpoints will be saved every 5 minutes while job runs"
        else
            rm -f "$JOB_PATH/.auto_checkpoint"
            echo "Auto-checkpointing disabled for $JOB_ID"
        fi
        ;;

    *)
        error_msg "Unknown action: $ACTION"
        echo ""
        echo "Valid actions: save, list, restore, enable, disable"
        exit 1
        ;;
esac
