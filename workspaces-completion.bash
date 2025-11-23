#!/bin/bash
# Bash completion for workspaces

_workspaces_completion() {
    # Standard bash completion variables
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword=$COMP_CWORD

    # Find git root and derive paths
    local git_root project_name tasks_dir
    git_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"

    if [ -z "$git_root" ]; then
        # Not in a git repository, completion won't work
        COMPREPLY=()
        return 0
    fi

    project_name="$(basename "$git_root")"
    tasks_dir="$HOME/.worktrees/config/$project_name"

    # Available commands
    local commands="new start attach list stop reset rm"

    # Get list of existing tasks
    local tasks=""
    if [ -d "$tasks_dir" ]; then
        tasks=$(cd "$tasks_dir" && ls -1 2>/dev/null || true)
    fi

    # First argument: complete command or global flags
    if [ $cword -eq 1 ]; then
        COMPREPLY=($(compgen -W "$commands --help" -- "$cur"))
        return 0
    fi

    local cmd="${COMP_WORDS[1]}"

    # Check if -- delimiter was used (stop completion after --)
    for ((i=1; i<cword; i++)); do
        if [ "${COMP_WORDS[i]}" = "--" ]; then
            # No completion after --
            COMPREPLY=()
            return 0
        fi
    done

    # Handle completion for position 2 and beyond
    if [ $cword -ge 2 ]; then
        case "$cmd" in
            new)
                # For 'new' command: support flags before or after workspace name
                # Check if previous word needs a value
                case "$prev" in
                    --branch)
                        # Complete with git branches
                        local branches
                        branches=$(cd "$git_root" 2>/dev/null && git branch --format='%(refname:short)' 2>/dev/null || true)
                        COMPREPLY=($(compgen -W "$branches" -- "$cur"))
                        return 0
                        ;;
                esac

                # Always show available flags as suggestions
                local flags="--branch --attach --rm --reset -- --help"
                # Filter out already used flags
                local available_flags=""
                for flag in $flags; do
                    local found=0
                    for ((i=2; i<cword; i++)); do
                        if [ "${COMP_WORDS[i]}" = "$flag" ]; then
                            found=1
                            break
                        fi
                    done
                    if [ $found -eq 0 ]; then
                        available_flags="$available_flags $flag"
                    fi
                done
                COMPREPLY=($(compgen -W "$available_flags" -- "$cur"))
                return 0
                ;;
            start)
                # start command: workspace name at position 2, then optional flags
                if [ $cword -eq 2 ]; then
                    # Position 2: complete workspace name or help flag
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--help" -- "$cur"))
                    else
                        COMPREPLY=($(compgen -W "$tasks" -- "$cur"))
                    fi
                else
                    # Position 3+: show -- and --help flags
                    COMPREPLY=($(compgen -W "-- --help" -- "$cur"))
                fi
                return 0
                ;;
            attach|stop|reset|rm)
                # These commands: workspace name at position 2, then optional flags
                if [ $cword -eq 2 ]; then
                    # Position 2: complete workspace name or help flag
                    if [[ "$cur" == -* ]]; then
                        COMPREPLY=($(compgen -W "--help" -- "$cur"))
                    else
                        COMPREPLY=($(compgen -W "$tasks" -- "$cur"))
                    fi
                else
                    # Position 3+: only help flags
                    COMPREPLY=($(compgen -W "--help" -- "$cur"))
                fi
                return 0
                ;;
            list)
                # Only help flag
                COMPREPLY=($(compgen -W "--help" -- "$cur"))
                return 0
                ;;
            --help|-h)
                # Main help was requested, no more completion
                COMPREPLY=()
                return 0
                ;;
            *)
                COMPREPLY=()
                return 0
                ;;
        esac
    fi
}

# Register completion for both full path and basename
complete -F _workspaces_completion workspaces
complete -F _workspaces_completion ./scripts/workspaces
complete -F _workspaces_completion ./workspaces
