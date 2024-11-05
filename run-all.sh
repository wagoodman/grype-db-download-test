#!/usr/bin/env bash
set -euo pipefail

. vars.sh

SESSION_NAME="deployment"

if ! tmux has-session -t $SESSION_NAME 2>/dev/null; then
    tmux new-session -d -s $SESSION_NAME -n "deployments" "bash -c \"echo 'hit enter to kill';read; tmux kill-session -t $SESSION_NAME\""
fi

create_payload

step "Starting deployment"
for region in "${regions[@]}"; do
    pass "$region"

    tmux split-window -v -t $SESSION_NAME -l 50% "/bin/bash -c '$(pwd)/run.sh $region; echo \"Test in $region complete (hit enter to exit)\"; read'"
    tmux select-layout -t $SESSION_NAME tiled
done

tmux attach -t $SESSION_NAME
