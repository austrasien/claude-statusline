#!/usr/bin/env bash
# Compte les sous-agents visibles (en cours / finis / échoués) pour statusline.sh.
# N'écrit rien sur stdout : les lignes du panneau d'agents gardent leur rendu par défaut.
input=$(cat)

session_id=$(jq -r '.session_id // empty' <<<"$input")
[[ -z $session_id ]] && exit 0

dir="${XDG_RUNTIME_DIR:-/tmp}/claude-statusline"
mkdir -p "$dir"
jq -r '[.tasks // [] | .[].status]
  | "\(map(select(. == "running")) | length) \(map(select(. == "completed")) | length) \(map(select(. == "failed" or . == "killed")) | length)"' \
  <<<"$input" > "$dir/agents-$session_id"
