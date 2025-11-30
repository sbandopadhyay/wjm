#!/bin/bash
# Bash completion script for WJM (Workstation Job Manager)
#
# Installation:
#   Option 1: Source in your .bashrc
#     echo 'source /path/to/wjm-completion.bash' >> ~/.bashrc
#
#   Option 2: Copy to system completion directory
#     sudo cp wjm-completion.bash /etc/bash_completion.d/wjm
#
#   Option 3: Copy to user completion directory
#     cp wjm-completion.bash ~/.local/share/bash-completion/completions/wjm

_wjm_completions() {
    local cur prev opts commands job_ids
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Main commands (v1.1 updated)
    commands="-srun -qrun -status -list -info -logs -kill -pause -resume -signal -resubmit -clean -archive -watch -stats -visual -compare -profile -search -template -abtest -checkpoint -dashboard -tui -manage-logs -resources -validate-config -export -import -doctor --help --version"

    # Commands that take a job_id
    local job_id_commands="-info -logs -kill -pause -resume -signal -resubmit -watch -profile -compare -checkpoint -export"

    # Commands that take a file
    local file_commands="-srun -qrun -abtest"

    # Get list of job IDs if JOB_DIR is set
    _get_job_ids() {
        local job_dir="${JOB_DIR:-$HOME/job_logs}"
        if [[ -d "$job_dir" ]]; then
            for d in "$job_dir"/job_*; do
                [[ -d "$d" ]] && basename "$d"
            done
        fi
    }

    # Handle completions based on previous argument
    case "$prev" in
        -info|-logs|-pause|-resume|-resubmit|-watch|-profile|-export)
            # Complete with job IDs
            job_ids=$(_get_job_ids)
            COMPREPLY=( $(compgen -W "$job_ids" -- "$cur") )
            return 0
            ;;
        -import)
            # Complete with --config option
            COMPREPLY=( $(compgen -W "--config --dry-run --submit" -- "$cur") )
            return 0
            ;;
        -kill)
            # Complete with job IDs or 'all'
            job_ids=$(_get_job_ids)
            COMPREPLY=( $(compgen -W "all $job_ids" -- "$cur") )
            return 0
            ;;
        -signal)
            # First arg is job_id, then signal
            if [[ "${COMP_WORDS[COMP_CWORD-2]}" == "-signal" ]]; then
                # Complete with signal names
                COMPREPLY=( $(compgen -W "SIGTERM SIGKILL SIGINT SIGHUP SIGUSR1 SIGUSR2" -- "$cur") )
            else
                job_ids=$(_get_job_ids)
                COMPREPLY=( $(compgen -W "$job_ids" -- "$cur") )
            fi
            return 0
            ;;
        -compare)
            # Complete with job IDs
            job_ids=$(_get_job_ids)
            COMPREPLY=( $(compgen -W "$job_ids" -- "$cur") )
            return 0
            ;;
        -srun|-qrun|-abtest)
            # Complete with .run and .sh files
            COMPREPLY=( $(compgen -f -X '!*.@(run|sh)' -- "$cur") $(compgen -d -- "$cur") )
            return 0
            ;;
        -clean)
            # Complete with clean types
            COMPREPLY=( $(compgen -W "failed completed all old" -- "$cur") )
            return 0
            ;;
        -template)
            # Complete with template actions
            COMPREPLY=( $(compgen -W "save use list show delete" -- "$cur") )
            return 0
            ;;
        -checkpoint)
            # Complete with checkpoint actions
            COMPREPLY=( $(compgen -W "save list restore enable disable" -- "$cur") )
            return 0
            ;;
        -list)
            # Complete with list options
            COMPREPLY=( $(compgen -W "--status --all" -- "$cur") )
            return 0
            ;;
        -search)
            # Complete with search options
            COMPREPLY=( $(compgen -W "--name --status --priority --date --user --include-archive" -- "$cur") )
            return 0
            ;;
        --status)
            # Complete with status values
            COMPREPLY=( $(compgen -W "RUNNING COMPLETED FAILED QUEUED PAUSED KILLED" -- "$cur") )
            return 0
            ;;
        --priority)
            # Complete with priority values
            COMPREPLY=( $(compgen -W "urgent high normal low" -- "$cur") )
            return 0
            ;;
        --preset)
            # Complete with preset values
            COMPREPLY=( $(compgen -W "small medium large gpu urgent" -- "$cur") )
            return 0
            ;;
        --name|--weight|--gpu|--depends-on|--date|--user|--variants|--params|--timeout|--retry|--cpu|--memory|--project|--array)
            # These take free-form values, no completion
            return 0
            ;;
        --format)
            # Complete with format options
            COMPREPLY=( $(compgen -W "yaml json shell" -- "$cur") )
            return 0
            ;;
        --config)
            # Complete with config files
            COMPREPLY=( $(compgen -f -X '!*.config' -- "$cur") $(compgen -d -- "$cur") )
            return 0
            ;;
    esac

    # Handle options after commands
    case "${COMP_WORDS[1]}" in
        -srun|-qrun)
            if [[ "$cur" == -* ]]; then
                # v1.1: Added timeout, retry, cpu, memory, project, array options
                COMPREPLY=( $(compgen -W "--name --priority --preset --weight --depends-on --timeout --retry --cpu --memory --project --array" -- "$cur") )
                return 0
            fi
            ;;
        -export)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--format --output -o" -- "$cur") )
                return 0
            fi
            ;;
        -abtest)
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--variants --params --preset --priority" -- "$cur") )
                return 0
            fi
            ;;
    esac

    # Default: complete with main commands
    if [[ "$cur" == -* ]] || [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi
}

# Register completion for wjm and ./wjm
complete -F _wjm_completions wjm
complete -F _wjm_completions ./wjm
