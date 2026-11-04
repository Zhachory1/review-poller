#!/bin/bash
# One polling pass: run the pr-review skill once per head SHA of each open,
# non-draft PR assigned to the authenticated gh user. launchd runs it on an
# interval and never overlaps runs of the same job.
set -euo pipefail

: "${PR_REVIEW_AGENT_CMD:?set PR_REVIEW_AGENT_CMD to a non-interactive agent command that takes the prompt as its last argument}"
STATE_DIR="${PR_REVIEW_STATE_DIR:-$HOME/.local/state/autopraxis}"
SEEN="$STATE_DIR/pr-review-seen"
mkdir -p "$STATE_DIR"
touch "$SEEN"

me="$(gh api user --jq .login)"
prs="$(gh search prs --assignee @me --state open --limit 100 --json repository,number,url,isDraft,author \
  --jq ".[] | select((.isDraft | not) and .author.login != \"$me\") | [.repository.nameWithOwner, .number, .url] | @tsv")"

[ -n "$prs" ] || exit 0
while IFS=$'\t' read -r repo number url; do
  sha="$(gh pr view "$number" -R "$repo" --json headRefOid --jq .headRefOid)"
  key="$repo#$number@$sha"
  if grep -Fxq "$key" "$SEEN"; then continue; fi
  echo "$(date -u +%FT%TZ) reviewing $key"
  prompt="Use the pr-review skill to review $url at head SHA $sha. Post the review per the skill's delivery contract."
  if /bin/bash -c "$PR_REVIEW_AGENT_CMD \"\$1\"" pr-review-poller "$prompt" </dev/null; then
    echo "$key" >> "$SEEN"
  else
    echo "$(date -u +%FT%TZ) review failed for $key; will retry next pass" >&2
  fi
done <<< "$prs"
