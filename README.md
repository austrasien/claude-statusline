# claude-statusline

A two-line status line for [Claude Code](https://docs.claude.com/en/docs/claude-code/statusline).

```
@omarchy │ Session title │ repo:branch ±3 │ PR #12 approved │ agents 2 en cours 1 finis
Opus 5.5 (medium) │ ctx 5% 49k/1M │ 5h 3% ↻ 3h18 │ 7j 16% ↻ 4j06h
```

- **Line 1**: hostname (coloured per machine), session title, repo and branch with the
  number of changed files, pull request and review state, running/finished/failed subagents.
- **Line 2**: model and effort level (⚡ in fast mode), context window usage, 5-hour and
  7-day rate limits with the time until they reset. Percentages turn green, yellow, then
  red at 50 % and 80 %.

Labels are in French (`j` = days, `en cours` = running, `finis` = finished).

## Install

Requires `bash` 5+, `jq`, `git` and `md5sum`.

```sh
cp statusline.sh subagent-statusline.sh ~/.claude/
chmod +x ~/.claude/statusline.sh ~/.claude/subagent-statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline.sh",
  "padding": 0,
  "refreshInterval": 5
},
"subagentStatusLine": {
  "type": "command",
  "command": "~/.claude/subagent-statusline.sh"
}
```

`subagent-statusline.sh` prints nothing; it only counts subagents into
`$XDG_RUNTIME_DIR/claude-statusline/` so the main status line can show them.
Counts older than 15 s are ignored.

## Customise

- **Host colours**: edit the `case $host in` block in `statusline.sh`. Unlisted hosts
  use the terminal's default colour.
- **Changed-files count**: `git status` is cached for 30 s per repo, so `±N` can lag
  up to 30 s after an edit or commit. The branch name is always live.

## License

MIT
