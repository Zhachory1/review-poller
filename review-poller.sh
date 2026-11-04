#!/bin/bash
# One polling pass: run the pr-review skill once per head SHA of each open,
# non-draft PR assigned to the authenticated gh user. launchd runs it on an
# interval and never overlaps runs of the same job.
set -euo pipefail

# Self-update to the newest v* tag, then re-exec so the pass runs one version end to end.
# Keep this block first and stable: a release that breaks it cannot update its way out.
dir="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${PR_REVIEW_UPDATED:-}" ] && git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  export PR_REVIEW_UPDATED=1
  if git -C "$dir" fetch -q --tags 2>/dev/null; then
    cur="$(git -C "$dir" describe --tags --exact-match 2>/dev/null || true)"
    latest="$(git -C "$dir" tag -l 'v*' --sort=-v:refname | head -1)"
    if [ -n "$latest" ] && [ "$cur" != "$latest" ]; then
      if git -C "$dir" -c advice.detachedHead=false checkout -q "$latest" 2>/dev/null; then
        echo "$(date -u +%FT%TZ) updated ${cur:-untagged} -> $latest"
        if [ -n "$cur" ] && ! git -C "$dir" diff --quiet "$cur" "$latest" -- SKILL.md; then
          echo "$(date -u +%FT%TZ) $latest changes install steps; ask your agent to update the review poller" >&2
        fi
        exec /bin/bash "$dir/review-poller.sh" "$@"
      fi
      echo "$(date -u +%FT%TZ) could not check out $latest (local changes?); staying on ${cur:-current}" >&2
    fi
  else
    echo "$(date -u +%FT%TZ) tag fetch failed; staying on current version" >&2
  fi
fi

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
  # GitHub is the source of truth: skip if this user already reviewed this exact SHA (by hand, another machine, or a run that posted then failed).
  reviewed="$(gh api "repos/$repo/pulls/$number/reviews" --paginate \
    --jq ".[] | select(.user.login == \"$me\" and .commit_id == \"$sha\") | .id")"
  if [ -n "$reviewed" ]; then echo "$key" >> "$SEEN"; continue; fi
  echo "$(date -u +%FT%TZ) reviewing $key"
  prompt="Use the pr-review skill to review $url at head SHA $sha. Post the review per the skill's delivery contract."
  if /bin/bash -c "$PR_REVIEW_AGENT_CMD \"\$1\"" pr-review-poller "$prompt" </dev/null; then
    echo "$key" >> "$SEEN"
  else
    echo "$(date -u +%FT%TZ) review failed for $key; will retry next pass" >&2
  fi
done <<< "$prs"
