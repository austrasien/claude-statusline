#!/usr/bin/env bash
# Status line Claude Code, sur deux lignes :
#   1. hostname │ titre de session │ repo:branche (+modifs, rafraîchies toutes les 30 s) │ PR │ sous-agents
#   2. modèle + effort │ contexte │ conso 5h (+ reset) │ conso 7j (+ reset)
input=$(cat)

# Un seul appel à jq : champs séparés par \x1f (non blanc, donc les champs vides sont conservés)
IFS=$'\x1f' read -r session_id session_name cwd repo_owner repo_name pr_number pr_state \
  model effort fast ctx_pct ctx_size ctx_used h5_pct h5_reset d7_pct d7_reset < <(
  jq -r '[.session_id, .session_name, .workspace.current_dir, .workspace.repo.owner,
          .workspace.repo.name, .pr.number, .pr.review_state, .model.display_name,
          .effort.level, .fast_mode, .context_window.used_percentage,
          .context_window.context_window_size, .context_window.total_input_tokens,
          .rate_limits.five_hour.used_percentage, .rate_limits.five_hour.resets_at,
          .rate_limits.seven_day.used_percentage, .rate_limits.seven_day.resets_at]
         | map(if . == null or . == false then "" else tostring end) | join("\u001f")' <<<"$input")

dim=$'\e[2m'; bold=$'\e[1m'; reset=$'\e[0m'
green=$'\e[32m'; yellow=$'\e[33m'; red=$'\e[31m'; cyan=$'\e[36m'; magenta=$'\e[35m'

# Couleur selon le pourcentage : vert < 50, jaune < 80, rouge sinon
color() {
  local p=${1%.*}
  if (( p < 50 )); then printf '%s' "$green"; elif (( p < 80 )); then printf '%s' "$yellow"; else printf '%s' "$red"; fi
}

# Durée restante jusqu'à un timestamp Unix : 2h14 / 3j05h / 12m
until_ts() {
  local s=$(( $1 - $(date +%s) ))
  (( s < 0 )) && s=0
  local d=$(( s / 86400 )) h=$(( s % 86400 / 3600 )) m=$(( s % 3600 / 60 ))
  if (( d > 0 )); then printf '%dj%02dh' "$d" "$h"
  elif (( h > 0 )); then printf '%dh%02d' "$h" "$m"
  else printf '%dm' "$m"; fi
}

# Tokens lisibles : 850 / 23k / 1M / 1.5M
tok() {
  local n=$1
  if (( n >= 1000000 )); then
    local t=$(( n / 100000 ))
    if (( t % 10 == 0 )); then printf '%dM' $(( t / 10 )); else printf '%d.%dM' $(( t / 10 )) $(( t % 10 )); fi
  elif (( n >= 1000 )); then printf '%dk' $(( n / 1000 ))
  else printf '%d' "$n"; fi
}

join() {
  local sep=" ${dim}│${reset} " out="" p
  for p in "$@"; do
    [[ -z $p ]] && continue
    [[ -n $out ]] && out+="$sep"
    out+="$p"
  done
  printf '%s' "$out"
}

# --- Ligne 1 : session, repo, PR, sous-agents ---
l1=()

# Hostname coloré par machine : omarchy jaune orangé, forge fuchsia (#ff2ec4 du plugin network)
host=${HOSTNAME:-$(hostname)}
case $host in
  omarchy) hc=$'\e[1;38;2;255;193;7m' ;;
  forge)   hc=$'\e[1;38;2;255;46;196m' ;;
  *)       hc="" ;;
esac
l1+=("${hc}@${host}${reset}")

[[ -n $session_name ]] && l1+=("${bold}${session_name}${reset}")

if [[ -n $cwd ]] && top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
  if [[ -n $repo_name ]]; then repo="${repo_owner:+$repo_owner/}$repo_name"; else repo=${top##*/}; fi
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  [[ -z $branch ]] && branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  # git status est coûteux sur un gros repo : résultat mis en cache 30 s par repo
  cache_dir="${XDG_RUNTIME_DIR:-/tmp}/claude-statusline"
  dirty_file="$cache_dir/dirty-$(printf '%s' "$top" | md5sum | cut -c1-12)"
  if [[ -f $dirty_file ]] && (( EPOCHSECONDS - $(stat -c %Y "$dirty_file") < 30 )); then
    dirty=$(<"$dirty_file")
  else
    dirty=$(git -C "$cwd" status --porcelain 2>/dev/null | wc -l)
    mkdir -p "$cache_dir" && printf '%s' "$dirty" > "$dirty_file"
  fi
  s="${cyan}${repo}${reset}${dim}:${reset}${magenta}${branch}${reset}"
  (( dirty > 0 )) && s+=" ${yellow}±${dirty}${reset}"
  l1+=("$s")
elif [[ -n $cwd ]]; then
  l1+=("${dim}${cwd##*/}${reset}")
fi

if [[ -n $pr_number ]]; then
  case $pr_state in
    approved) c=$green ;; changes_requested) c=$red ;; *) c=$dim ;;
  esac
  l1+=("PR ${c}#${pr_number}${pr_state:+ $pr_state}${reset}")
fi

# Compteurs écrits par subagent-statusline.sh ; ignorés s'ils datent de plus de 15 s
agents_file="${XDG_RUNTIME_DIR:-/tmp}/claude-statusline/agents-${session_id}"
if [[ -n $session_id && -f $agents_file ]] && (( $(date +%s) - $(stat -c %Y "$agents_file") <= 15 )); then
  read -r running done failed < "$agents_file"
  if (( running + done + failed > 0 )); then
    s="agents"
    (( running > 0 )) && s+=" ${yellow}${running} en cours${reset}"
    (( done > 0 )) && s+=" ${green}${done} finis${reset}"
    (( failed > 0 )) && s+=" ${red}${failed} échoués${reset}"
    l1+=("$s")
  fi
fi

# --- Ligne 2 : modèle, contexte, limites ---
l2=()

m="$model"
[[ -n $effort ]] && m+=" ${dim}(${effort})${reset}"
[[ $fast == true ]] && m+=" ${yellow}⚡${reset}"
l2+=("$m")

if [[ -n $ctx_pct ]]; then
  s="ctx $(color "$ctx_pct")${ctx_pct%.*}%${reset}"
  [[ -n $ctx_size ]] && s+=" ${dim}$(tok "${ctx_used:-0}")/$(tok "$ctx_size")${reset}"
  l2+=("$s")
fi

if [[ -n $h5_pct ]]; then
  s="5h $(color "$h5_pct")${h5_pct%.*}%${reset}"
  [[ -n $h5_reset ]] && s+=" ${dim}↻ $(until_ts "$h5_reset")${reset}"
  l2+=("$s")
fi

if [[ -n $d7_pct ]]; then
  s="7j $(color "$d7_pct")${d7_pct%.*}%${reset}"
  [[ -n $d7_reset ]] && s+=" ${dim}↻ $(until_ts "$d7_reset")${reset}"
  l2+=("$s")
fi

line1=$(join "${l1[@]}")
line2=$(join "${l2[@]}")
[[ -n $line1 ]] && printf '%s\n' "$line1"
printf '%s' "$line2"
