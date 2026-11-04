# review-poller

A macOS launchd job that runs the [autopraxis](https://github.com/Zhachory1/autopraxis) `pr-review` skill on every open GitHub PR assigned to you. It reviews each PR once per head SHA, and reviews it again after a new push.

## Install

Ask your coding agent:

> Install the review poller from https://github.com/Zhachory1/review-poller by following its SKILL.md.

The agent clones this repo to `~/.local/share/review-poller`, checks `gh`, `jq`, and `pr-review`, asks you for your agent command and poll interval, loads a LaunchAgent, and adds a short note to your global agent instructions (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, or `~/AGENTS.md`) so your agent knows the poller is running. Uninstall removes the note.

Reviews post under your own GitHub account and can `APPROVE` or `REQUEST_CHANGES`. The poller never merges.

## Operate

- Logs: `~/Library/Logs/pr-review-poller.log`
- Stop or uninstall: ask your agent to "uninstall the review poller". It follows the Uninstall section of `SKILL.md`.
- Re-review a SHA: delete its line from `~/.local/state/autopraxis/pr-review-seen`
- Test: `./test.sh` (needs `jq`)
