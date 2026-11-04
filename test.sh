#!/bin/bash
# Fake gh + fake agent; checks one review per head SHA, skips drafts/self-authored PRs and SHAs already reviewed on GitHub, retries failures.
set -euo pipefail
cd "$(dirname "$0")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo aaa > "$tmp/sha"
# Reviews by someone else, or by me at an older SHA, must not count.
echo '[{"id":1,"user":{"login":"bob"},"commit_id":"aaa"},{"id":2,"user":{"login":"me"},"commit_id":"old"}]' > "$tmp/reviews"
cat > "$tmp/gh" <<FAKE
#!/bin/bash
jqf=""; prev=""; for a in "\$@"; do [ "\$prev" = "--jq" ] && jqf="\$a"; prev="\$a"; done
case "\$1 \$2" in
  "api user") json='{"login":"me"}' ;;
  "search prs") json='[{"repository":{"nameWithOwner":"o/r"},"number":1,"url":"https://github.com/o/r/pull/1","isDraft":false,"author":{"login":"bob"}},{"repository":{"nameWithOwner":"o/r"},"number":2,"url":"u2","isDraft":true,"author":{"login":"bob"}},{"repository":{"nameWithOwner":"o/r"},"number":3,"url":"u3","isDraft":false,"author":{"login":"me"}}]' ;;
  "pr view") json="{\"headRefOid\":\"\$(cat $tmp/sha)\"}" ;;
  "api repos/o/r/pulls/1/reviews") json="\$(cat $tmp/reviews)" ;;
esac
printf '%s' "\$json" | jq -r "\$jqf"
FAKE
chmod +x "$tmp/gh"
export PATH="$tmp:$PATH" PR_REVIEW_STATE_DIR="$tmp/state" PR_REVIEW_AGENT_CMD="echo >> $tmp/agent.log"
# Skip self-update for runs from this checkout so the test never moves the dev working copy to a tag.
export PR_REVIEW_UPDATED=1
fail() { echo "FAIL: $*" >&2; exit 1; }

./review-poller.sh >/dev/null; ./review-poller.sh >/dev/null
[ "$(wc -l < "$tmp/agent.log")" -eq 1 ] || fail "expected one review for PR 1 at aaa"
grep -q 'pull/1 at head SHA aaa' "$tmp/agent.log" || fail "wrong prompt"

echo bbb > "$tmp/sha"; ./review-poller.sh >/dev/null
[ "$(wc -l < "$tmp/agent.log")" -eq 2 ] || fail "new SHA not re-reviewed"
grep -q "head SHA bbb" "$tmp/agent.log" || fail "wrong prompt for new SHA"

echo ccc > "$tmp/sha"; PR_REVIEW_AGENT_CMD=false ./review-poller.sh >/dev/null 2>&1
grep -q ccc "$tmp/state/pr-review-seen" && fail "failed review marked seen"

echo ddd > "$tmp/sha"
echo '[{"id":3,"user":{"login":"me"},"commit_id":"ddd"}]' > "$tmp/reviews"
./review-poller.sh >/dev/null
[ "$(wc -l < "$tmp/agent.log")" -eq 2 ] || fail "SHA already reviewed on GitHub was reviewed again"
grep -Fxq 'o/r#1@ddd' "$tmp/state/pr-review-seen" || fail "SHA reviewed on GitHub not recorded as seen"

unset PR_REVIEW_UPDATED
# Auto-update: a clone on an older tag moves to the newest tag and runs the new code in the same pass.
repo="$tmp/upstream"; inst="$tmp/inst"
git init -q "$repo"
cp review-poller.sh "$repo/"; echo v1 > "$repo/SKILL.md"
git -C "$repo" add -A; git -C "$repo" -c user.name=t -c user.email=t@t commit -qm v1; git -C "$repo" tag v0.1.0
printf '\necho NEW-CODE-RAN\n' >> "$repo/review-poller.sh"
git -C "$repo" -c user.name=t -c user.email=t@t commit -qam v2; git -C "$repo" tag v0.10.0
git clone -q "$repo" "$inst"; git -C "$inst" -c advice.detachedHead=false checkout -q v0.1.0
out="$(/bin/bash "$inst/review-poller.sh" 2>&1)" || fail "auto-update pass failed: $out"
[ "$(git -C "$inst" describe --tags)" = v0.10.0 ] || fail "did not update to newest tag (v0.10.0 sorts above v0.1.0)"
grep -q NEW-CODE-RAN <<< "$out" || fail "new code did not run in the same pass"
grep -q 'updated v0.1.0 -> v0.10.0' <<< "$out" || fail "update not logged"
grep -q 'install steps' <<< "$out" && fail "SKILL.md unchanged but install-step warning logged"

# Install-step change is flagged.
echo v3 > "$repo/SKILL.md"; git -C "$repo" -c user.name=t -c user.email=t@t commit -qam v3; git -C "$repo" tag v0.11.0
out="$(/bin/bash "$inst/review-poller.sh" 2>&1)" || fail "second update pass failed"
grep -q 'install steps' <<< "$out" || fail "SKILL.md change not flagged"

# Fetch failure keeps the current version and the pass still succeeds.
git -C "$inst" remote set-url origin "$tmp/missing"
out="$(/bin/bash "$inst/review-poller.sh" 2>&1)" || fail "pass failed when fetch failed: $out"
[ "$(git -C "$inst" describe --tags)" = v0.11.0 ] || fail "version changed after failed fetch"

echo "ok"
