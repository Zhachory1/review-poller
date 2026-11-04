---
name: review-poller
description: "Install, update, or remove a macOS launchd poller that runs the autopraxis pr-review skill on every open GitHub PR where the user is in the assignee field, once per head SHA. Triggers: install review poller, set up PR review agent, auto-review assigned PRs, stop review poller, uninstall review poller, review poller broken."
---

# Review Poller

`review-poller.sh` runs one pass. For each open, non-draft PR assigned to the `gh` user, excluding PRs the user authored, it runs the `pr-review` skill once per head SHA. A new push gets a new review. A failed run is retried on the next pass. Reviewed keys (`repo#pr@sha`) live in `~/.local/state/autopraxis/pr-review-seen`. The `pr-review` idempotency marker also stops duplicate posts on GitHub.

Install only on macOS. When the user asks you to install the poller, do these steps:

- **Clone.** `git clone https://github.com/Zhachory1/review-poller ~/.local/share/review-poller`, or `git -C ~/.local/share/review-poller pull` if it is already there. launchd runs the script from this path, so do not move it.
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
- **Reset.** To review a SHA again, delete its line from the seen file.

launchd does not start a second run of a job while the first is still running, so the poller needs no lock. The first pass reviews every assigned PR, so tell the user how many are open before you load the plist.

## Uninstall

When the user asks you to stop, remove, or uninstall the poller, or says it is broken, do these steps:

- **Unload.** Run `launchctl bootout gui/$(id -u)/com.autopraxis.pr-review-poller`. This also stops a review that is running now. If it fails with `3: No such process`, the job is already unloaded; continue.
- **Remove plist.** Delete `~/Library/LaunchAgents/com.autopraxis.pr-review-poller.plist`, so the job does not load again at the next login.
- **Verify.** `launchctl print gui/$(id -u)/com.autopraxis.pr-review-poller` must fail. If it still succeeds, report this to the user and stop.
- **Ask before you delete data.** If the poller is broken, show the user the last 50 lines of `~/Library/Logs/pr-review-poller.log` first. Then ask if they also want to delete the log, the seen file `~/.local/state/autopraxis/pr-review-seen`, and the clone `~/.local/share/review-poller`. Delete only what they approve. If they keep the seen file, a later reinstall does not review the same SHAs again.

Reviews that are already posted stay on GitHub. Uninstall does not remove the `pr-review` skill or autopraxis.
