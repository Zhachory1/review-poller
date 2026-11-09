# review-poller

> **Moved:** this poller now lives in [Zhachory1/pr-pollers](https://github.com/Zhachory1/pr-pollers) with the review, maintain, and build pollers together. New installs should use that repo; its install steps replace this one. This repo stays working for existing installs.


A macOS launchd job that runs the [autopraxis](https://github.com/Zhachory1/autopraxis) `pr-review` skill on every open GitHub PR assigned to you. It reviews each PR once per head SHA, and reviews it again after a new push.

## Install

Ask your coding agent:

> Install the review poller from https://github.com/Zhachory1/review-poller by following its SKILL.md.

The agent clones this repo to `~/.local/share/review-poller`, checks `gh`, `jq`, and `pr-review`, asks you for your agent command and poll interval, loads a LaunchAgent, and adds a short note to your global agent instructions (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, or `~/AGENTS.md`) so your agent knows the poller is running. Uninstall removes the note.

Reviews post under your own GitHub account and can `APPROVE` or `REQUEST_CHANGES`. The poller never merges.

## Operate

- Logs: `~/Library/Logs/pr-review-poller.log`
- Update: automatic. Each pass switches to the newest release tag. If a release changes install steps, the log tells you to ask your agent to "update the review poller".
- Stop or uninstall: ask your agent to "uninstall the review poller". It follows the Uninstall section of `SKILL.md`.
- Re-review a SHA: the poller skips any SHA you already reviewed on GitHub, so push a new commit or ask your agent to run `pr-review` by hand.
- Test: `./test.sh` (needs `jq`)

## Release (maintainer)

Teammates run tagged releases only, so changes on `main` reach nobody until you tag them. Installed pollers switch to a new `v*` tag on their next pass, so a pushed tag runs on every teammate's Mac within one poll interval, under their GitHub account. Tag only what you would run yourself. To undo a bad release, push a newer tag with the fix.

```bash
./test.sh
git tag -a v0.2.0 -m "What changed and whether users must redo any install step"
git push origin v0.2.0
```

If the tag message says install steps changed, tell testers to ask their agent to "update the review poller".
