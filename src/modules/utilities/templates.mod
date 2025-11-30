#!/bin/bash
# templates.mod - Job Templates System
# Save and reuse job configurations

TEMPLATE_DIR="$JOB_DIR/.templates"
mkdir -p "$TEMPLATE_DIR"

ACTION="$1"
TEMPLATE_NAME="$2"
JOB_ID="$3"

if [[ -z "$ACTION" ]]; then
    echo " Job Templates"
    echo "========================================================"
    echo ""
    echo "Usage: $SCRIPT_NAME -template <action> [args]"
    echo ""
    echo "Actions:"
    echo "  save <name> <job_id>    Save job as template"
    echo "  use <name> <script>     Create job from template"
    echo "  list                    List all templates"
    echo "  show <name>             Show template details"
    echo "  delete <name>           Delete a template"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME -template save gpu_training job_001"
    echo "  $SCRIPT_NAME -template use gpu_training new_script.sh"
    echo "  $SCRIPT_NAME -template list"
    exit 0
fi

case "$ACTION" in
    save)
        if [[ -z "$TEMPLATE_NAME" || -z "$JOB_ID" ]]; then
            error_msg "Usage: $SCRIPT_NAME -template save <name> <job_id>"
            exit 1
        fi

        # Validate template name (prevent directory traversal)
        if [[ "$TEMPLATE_NAME" =~ [/\\.] || "$TEMPLATE_NAME" =~ ^- ]]; then
            error_msg "Invalid template name: '$TEMPLATE_NAME'"
            echo "Template names cannot contain: / \\ . or start with -"
            exit 1
        fi

        # Validate job exists
        JOB_PATH="$JOB_DIR/$JOB_ID"
        if [[ ! -d "$JOB_PATH" || ! -f "$JOB_PATH/job.info" ]]; then
            error_msg "Job '$JOB_ID' not found"
            exit 1
        fi

        # Create template directory
        TEMPLATE_PATH="$TEMPLATE_DIR/$TEMPLATE_NAME"
        if ! mkdir -p "$TEMPLATE_PATH"; then
            error_msg "Failed to create template directory"
            exit 1
        fi

        # Save job metadata
        if ! cp "$JOB_PATH/job.info" "$TEMPLATE_PATH/template.info" 2>/dev/null; then
            error_msg "Failed to copy job metadata"
            rm -rf "$TEMPLATE_PATH"
            exit 1
        fi

        # Save command if exists
        if [[ -f "$JOB_PATH/command.run" ]]; then
            cp "$JOB_PATH/command.run" "$TEMPLATE_PATH/command.run"
        fi

        # Extract and save key parameters
        WEIGHT=$(grep "^WEIGHT=" "$JOB_PATH/job.info" 2>/dev/null | cut -d= -f2)
        GPU=$(grep "^GPU=" "$JOB_PATH/job.info" 2>/dev/null | cut -d= -f2)
        PRIORITY=$(grep "^PRIORITY=" "$JOB_PATH/job.info" 2>/dev/null | cut -d= -f2)

        cat > "$TEMPLATE_PATH/params.conf" <<EOF
WEIGHT=$WEIGHT
GPU=$GPU
PRIORITY=$PRIORITY
CREATED=$(date '+%Y-%m-%d %H:%M:%S')
SOURCE_JOB=$JOB_ID
EOF

        echo "Template '$TEMPLATE_NAME' saved successfully"
        echo ""
        echo "Parameters saved:"
        echo "  Weight:   $WEIGHT"
        echo "  GPU:      $GPU"
        echo "  Priority: $PRIORITY"
        echo ""
        echo "Use template: $SCRIPT_NAME -template use $TEMPLATE_NAME <script>"
        ;;

    use)
        SCRIPT_FILE="$JOB_ID"  # Reuse variable

        if [[ -z "$TEMPLATE_NAME" || -z "$SCRIPT_FILE" ]]; then
            error_msg "Usage: $SCRIPT_NAME -template use <name> <script>"
            exit 1
        fi

        # Validate template name
        if [[ "$TEMPLATE_NAME" =~ [/\\.] || "$TEMPLATE_NAME" =~ ^- ]]; then
            error_msg "Invalid template name: '$TEMPLATE_NAME'"
            exit 1
        fi

        # Validate template exists
        TEMPLATE_PATH="$TEMPLATE_DIR/$TEMPLATE_NAME"
        if [[ ! -d "$TEMPLATE_PATH" || ! -f "$TEMPLATE_PATH/params.conf" ]]; then
            error_msg "Template '$TEMPLATE_NAME' not found"
            echo ""
            echo "Available templates:"
            for tmpl in "$TEMPLATE_DIR"/*; do
                [[ -d "$tmpl" ]] && echo "  - $(basename "$tmpl")"
            done
            exit 1
        fi

        # Validate script exists
        if [[ ! -f "$SCRIPT_FILE" ]]; then
            error_msg "Script file '$SCRIPT_FILE' not found"
            exit 1
        fi

        # Load template parameters
        source "$TEMPLATE_PATH/params.conf"

        # Build qrun command with template parameters
        CMD_ARGS=("$SCRIPT_FILE")

        [[ -n "$WEIGHT" && "$WEIGHT" != "N/A" ]] && CMD_ARGS+=("--weight" "$WEIGHT")
        [[ -n "$PRIORITY" && "$PRIORITY" != "N/A" ]] && CMD_ARGS+=("--priority" "$PRIORITY")

        # For GPU, we need to add metadata to the script
        if [[ -n "$GPU" && "$GPU" != "N/A" ]]; then
            # Create temporary script with GPU metadata
            TEMP_SCRIPT=$(mktemp "/tmp/template_XXXXXX.run") || {
                error_msg "Failed to create temporary script file"
                exit 1
            }
            trap 'rm -f "$TEMP_SCRIPT"' EXIT INT TERM

            echo "# WEIGHT: $WEIGHT" > "$TEMP_SCRIPT"
            echo "# GPU: $GPU" >> "$TEMP_SCRIPT"
            echo "# PRIORITY: $PRIORITY" >> "$TEMP_SCRIPT"
            cat "$SCRIPT_FILE" >> "$TEMP_SCRIPT"
            chmod +x "$TEMP_SCRIPT"

            echo "Submitting job with template '$TEMPLATE_NAME'"
            echo "  Weight:   $WEIGHT"
            echo "  GPU:      $GPU"
            echo "  Priority: $PRIORITY"
            echo ""

            source "$MODULES_DIR/core/qrun.mod" "$TEMP_SCRIPT"
        else
            echo "Submitting job with template '$TEMPLATE_NAME'"
            echo "  Weight:   $WEIGHT"
            echo "  Priority: $PRIORITY"
            echo ""

            source "$MODULES_DIR/core/qrun.mod" "${CMD_ARGS[@]}"
        fi
        ;;

    list)
        echo " Available Templates"
        echo "========================================================"
        echo ""

        template_count=0
        for tmpl in "$TEMPLATE_DIR"/*; do
            [[ ! -d "$tmpl" ]] && continue

            tmpl_name=$(basename "$tmpl")
            template_count=$((template_count + 1))

            if [[ -f "$tmpl/params.conf" ]]; then
                source "$tmpl/params.conf"
                echo "$tmpl_name"
                echo "   Weight: $WEIGHT  |  GPU: $GPU  |  Priority: $PRIORITY"
                echo "   Created: $CREATED  |  Source: $SOURCE_JOB"
                echo ""
            fi
        done

        if [[ $template_count -eq 0 ]]; then
            echo "No templates found."
            echo ""
            echo "Create a template: $SCRIPT_NAME -template save <name> <job_id>"
        else
            echo "Total templates: $template_count"
        fi
        ;;

    show)
        if [[ -z "$TEMPLATE_NAME" ]]; then
            error_msg "Usage: $SCRIPT_NAME -template show <name>"
            exit 1
        fi

        TEMPLATE_PATH="$TEMPLATE_DIR/$TEMPLATE_NAME"
        if [[ ! -d "$TEMPLATE_PATH" ]]; then
            error_msg "Template '$TEMPLATE_NAME' not found"
            exit 1
        fi

        echo "Template: $TEMPLATE_NAME"
        echo "========================================================"
        echo ""

        if [[ -f "$TEMPLATE_PATH/params.conf" ]]; then
            source "$TEMPLATE_PATH/params.conf"
            echo "Parameters:"
            echo "  Weight:      $WEIGHT"
            echo "  GPU:         $GPU"
            echo "  Priority:    $PRIORITY"
            echo "  Created:     $CREATED"
            echo "  Source Job:  $SOURCE_JOB"
            echo ""
        fi

        if [[ -f "$TEMPLATE_PATH/command.run" ]]; then
            echo "Command Preview:"
            echo "========================================================"
            head -20 "$TEMPLATE_PATH/command.run"
            echo "========================================================"
        fi
        ;;

    delete)
        if [[ -z "$TEMPLATE_NAME" ]]; then
            error_msg "Usage: $SCRIPT_NAME -template delete <name>"
            exit 1
        fi

        TEMPLATE_PATH="$TEMPLATE_DIR/$TEMPLATE_NAME"
        if [[ ! -d "$TEMPLATE_PATH" ]]; then
            error_msg "Template '$TEMPLATE_NAME' not found"
            exit 1
        fi

        rm -rf "$TEMPLATE_PATH"
        echo "Template '$TEMPLATE_NAME' deleted"
        ;;

    *)
        error_msg "Unknown action: $ACTION"
        echo ""
        echo "Valid actions: save, use, list, show, delete"
        exit 1
        ;;
esac
