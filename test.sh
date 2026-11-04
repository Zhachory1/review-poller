#!/bin/bash
# Fake gh + fake agent; checks one review per head SHA, skips drafts/self-authored PRs, retries failures.
set -euo pipefail
cd "$(dirname "$0")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo aaa > "$tmp/sha"
cat > "$tmp/gh" <<FAKE
#!/bin/bash
jqf=""; prev=""; for a in "\$@"; do [ "\$prev" = "--jq" ] && jqf="\$a"; prev="\$a"; done
case "\$1 \$2" in
  "api user") json='{"login":"me"}' ;;
  "search prs") json='[{"repository":{"nameWithOwner":"o/r"},"number":1,"url":"https://github.com/o/r/pull/1","isDraft":false,"author":{"login":"bob"}},{"repository":{"nameWithOwner":"o/r"},"number":2,"url":"u2","isDraft":true,"author":{"login":"bob"}},{"repository":{"nameWithOwner":"o/r"},"number":3,"url":"u3","isDraft":false,"author":{"login":"me"}}]' ;;
  "pr view") json="{\"headRefOid\":\"\$(cat $tmp/sha)\"}" ;;
esac
printf '%s' "\$json" | jq -r "\$jqf"
FAKE
chmod +x "$tmp/gh"
export PATH="$tmp:$PATH" PR_REVIEW_STATE_DIR="$tmp/state" PR_REVIEW_AGENT_CMD="echo >> $tmp/agent.log"
fail() { echo "FAIL: $*" >&2; exit 1; }

./review-poller.sh >/dev/null; ./review-poller.sh >/dev/null
[ "$(wc -l < "$tmp/agent.log")" -eq 1 ] || fail "expected one review for PR 1 at aaa"
grep -q 'pull/1 at head SHA aaa' "$tmp/agent.log" || fail "wrong prompt"

echo bbb > "$tmp/sha"; ./review-poller.sh >/dev/null
[ "$(wc -l < "$tmp/agent.log")" -eq 2 ] || fail "new SHA not re-reviewed"
grep -q "head SHA bbb" "$tmp/agent.log" || fail "wrong prompt for new SHA"

echo ccc > "$tmp/sha"; PR_REVIEW_AGENT_CMD=false ./review-poller.sh >/dev/null 2>&1
grep -q ccc "$tmp/state/pr-review-seen" && fail "failed review marked seen"
echo "ok"
