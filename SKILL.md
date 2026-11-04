---
name: review-poller
description: "Install, update, or remove a macOS launchd poller that runs the autopraxis pr-review skill on every open GitHub PR where the user is in the assignee field, once per head SHA. Triggers: install review poller, update review poller, set up PR review agent, auto-review assigned PRs, stop review poller, uninstall review poller, review poller broken."
---

# Review Poller

`review-poller.sh` runs one pass. For each open, non-draft PR assigned to the `gh` user, excluding PRs the user authored, it runs the `pr-review` skill once per head SHA. A new push gets a new review. A failed run is retried on the next pass. Before each run it asks GitHub whether the user already has a review on that PR at that exact SHA, and skips if so. This covers reviews made by hand, from another machine, or by a run that posted and then exited with an error. Reviewed keys (`repo#pr@sha`) are cached in `~/.local/state/autopraxis/pr-review-seen` to save API calls.

Install only on macOS. When the user asks you to install the poller, do these steps:

- **Clone.** Run `git clone https://github.com/Zhachory1/review-poller ~/.local/share/review-poller`, then check out the newest release tag: `git -C ~/.local/share/review-poller checkout "$(git -C ~/.local/share/review-poller tag --sort=-v:refname | head -1)"`. If the folder already exists, follow Update instead. launchd runs the script from this path, so do not move it.
- **Check pr-review.** The poller tells the user's agent to use the `pr-review` skill from [autopraxis](https://github.com/Zhachory1/autopraxis). If that agent does not have it, install it with the `npx @zhachory1/autopraxis@latest install --target <target>` command from autopraxis `INSTALL.md` that matches the agent.
- **Check auth.** Confirm `gh auth status` succeeds and `jq` is installed. Reviews post as this GitHub account.
- **Agent command.** Ask the user for their agent command. It must run non-interactively, take the prompt as its last argument, and have permission to run `gh`, for example `claude -p --permission-mode acceptEdits --allowedTools "Bash(gh:*)"`. Use exactly what the user gives you; do not guess.
- **Interval.** Ask how often to poll (default 600 seconds).
- **Write plist.** Write `~/Library/LaunchAgents/com.autopraxis.pr-review-poller.plist` with this template. Fill in the absolute path of `~/.local/share/review-poller/review-poller.sh`, the agent command, and a `PATH` that contains `gh`, `jq`, and the agent CLI (`dirname "$(command -v gh)"`, etc.). XML-escape the values (`&` → `&amp;`, `<` → `&lt;`, `"` → `&quot;`). Set `StartInterval` to the chosen interval.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.autopraxis.pr-review-poller</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>POLLER_PATH</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>TOOL_PATH:/usr/bin:/bin</string>
    <key>PR_REVIEW_AGENT_CMD</key><string>AGENT_CMD</string>
  </dict>
  <key>StartInterval</key><integer>600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>HOME/Library/Logs/pr-review-poller.log</string>
  <key>StandardErrorPath</key><string>HOME/Library/Logs/pr-review-poller.log</string>
</dict></plist>
```

- **Load.** Run `plutil -lint` on the plist, then `launchctl bootstrap gui/$(id -u) <plist>`. If the job is already loaded (update), run `launchctl bootout gui/$(id -u)/com.autopraxis.pr-review-poller` first. Check `~/Library/Logs/pr-review-poller.log` after the first run.
- **Tell the agent.** Add the block below to the user's global agent instructions so their interactive agent knows the poller exists. Use the file that the user's agent reads: `~/.claude/CLAUDE.md` for Claude Code, `~/.codex/AGENTS.md` for Codex, otherwise `~/AGENTS.md`. If you are not sure, ask. Create the file if it does not exist. If the markers already exist, replace the text between them; do not add a second block. Show the user the file path and the block before you write.

```markdown
<!-- review-poller:start -->
## Local PR review poller

A launchd job (`com.autopraxis.pr-review-poller`) runs on this Mac. It runs the `pr-review` skill on each open, non-draft PR assigned to me, once per head SHA, and posts the review as me.

- Do not review those PRs again by hand unless I ask. The poller does it after each push.
- This rule does not apply to a run that the poller starts. Its prompt asks for a review at a specific head SHA; do that review.
- Log: `~/Library/Logs/pr-review-poller.log`. Reviewed SHAs: `~/.local/state/autopraxis/pr-review-seen`.
- The poller skips any SHA I already reviewed on GitHub. To get a new automatic review, push a new commit, or ask you to run `pr-review` by hand.
- To stop, update, or debug the poller, follow `~/.local/share/review-poller/SKILL.md`.
<!-- review-poller:end -->
```

- **Re-review.** The poller never reviews a SHA again once the user has a review on it in GitHub. To review it again, run `pr-review` by hand or push a new commit.

launchd does not start a second run of a job while the first is still running, so the poller needs no lock. The first pass reviews every assigned PR, so tell the user how many are open before you load the plist.

## Update

Releases are git tags (`v0.1.0`, `v0.2.0`, ...). Install only tagged releases, never `main`. From `v0.2.0` on, each pass of the poller fetches tags and switches to the newest `v*` tag on its own, so script fixes apply without the user doing anything. If a new release changes `SKILL.md`, the log says `changes install steps; ask your agent to update the review poller`. If local edits block the switch, the log says `could not check out`. The steps below are for those cases, for a first move to `v0.2.0`, and for rollback.

When the user asks you to update the poller, do these steps:

- **Find versions.** Run `git -C ~/.local/share/review-poller fetch --tags`. The current version is `git -C ~/.local/share/review-poller describe --tags`. The newest is `git -C ~/.local/share/review-poller tag --sort=-v:refname | head -1`. If they match, tell the user they are up to date and stop.
- **Show changes.** Show the user the newest tag's message (`git -C ~/.local/share/review-poller tag -l --format='%(contents)' <new>`) and the files that changed (`git -C ~/.local/share/review-poller diff --stat <current> <new>`). Ask before you continue.
- **Check out.** Run `git -C ~/.local/share/review-poller checkout <new>`. If git refuses because of local changes, show them to the user and stop. Do not discard them.
- **Apply.** If only `review-poller.sh` changed, you are done: launchd reads the script fresh on each run. If `SKILL.md` changed, read it again and redo **Write plist**, **Load**, and **Tell the agent** from Install. Keep the user's agent command, `PATH`, and interval from the current plist; ask only about new settings.
- **Check pr-review.** If the tag message says it needs a newer autopraxis, reinstall the `pr-review` skill with the matching `npx @zhachory1/autopraxis@latest install --target <target> --force` command.
- **Verify.** Check `~/Library/Logs/pr-review-poller.log` after the next run.
- **Roll back or pin.** Auto-update moves back to the newest tag on the next pass. To stay on an older tag, add `PR_REVIEW_UPDATED=1` to the plist `EnvironmentVariables`, check out the tag, and redo **Load**. Remove the variable to resume auto-update.

## Uninstall

When the user asks you to stop, remove, or uninstall the poller, or says it is broken, do these steps:

- **Unload.** Run `launchctl bootout gui/$(id -u)/com.autopraxis.pr-review-poller`. This also stops a review that is running now. If it fails with `3: No such process`, the job is already unloaded; continue.
- **Remove plist.** Delete `~/Library/LaunchAgents/com.autopraxis.pr-review-poller.plist`, so the job does not load again at the next login.
- **Verify.** `launchctl print gui/$(id -u)/com.autopraxis.pr-review-poller` must fail. If it still succeeds, report this to the user and stop.
- **Remove context.** Delete the lines from `<!-- review-poller:start -->` to `<!-- review-poller:end -->`, markers included, from the agent instructions file you wrote at install (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, or `~/AGENTS.md`). Do not change other text in that file.
- **Ask before you delete data.** If the poller is broken, show the user the last 50 lines of `~/Library/Logs/pr-review-poller.log` first. Then ask if they also want to delete the log, the seen file `~/.local/state/autopraxis/pr-review-seen`, and the clone `~/.local/share/review-poller`. Delete only what they approve. A later reinstall skips SHAs already reviewed on GitHub either way; the seen file only saves API calls.

Reviews that are already posted stay on GitHub. Uninstall does not remove the `pr-review` skill or autopraxis.
