#!/bin/bash

# Usage: ./test-bc-review.sh <PR_NUMBER>

if [ -z "$1" ]; then
  echo "Usage: $0 <PR_NUMBER>"
  exit 1
fi

PR_NUMBER=$1

echo "Fetching PR #$PR_NUMBER info..."
PR_DATA=$(gh pr view $PR_NUMBER --json headRefName,headRefOid,baseRefName,baseRefOid,state,headRepository)

# Extract data
HEAD_SHA=$(echo "$PR_DATA" | jq -r '.headRefOid')
BASE_SHA=$(echo "$PR_DATA" | jq -r '.baseRefOid')
HEAD_REF=$(echo "$PR_DATA" | jq -r '.headRefName')
BASE_REF=$(echo "$PR_DATA" | jq -r '.baseRefName')
STATE=$(echo "$PR_DATA" | jq -r '.state')
HEAD_REPO=$(echo "$PR_DATA" | jq -r '.headRepository.nameWithOwner')

echo "PR State: $STATE"
echo "Base: $BASE_REF ($BASE_SHA)"
echo "Head: $HEAD_REF ($HEAD_SHA)"

# Try to checkout the PR branch (works for open PRs)
if [ "$STATE" = "OPEN" ]; then
  echo "Checking out open PR..."
  gh pr checkout $PR_NUMBER
else
  # For merged/closed PRs, fetch and checkout the head commit
  echo "PR is $STATE. Fetching PR commits..."

  # Fetch the PR ref
  git fetch origin pull/$PR_NUMBER/head:pr-$PR_NUMBER 2>/dev/null || {
    echo "Could not fetch PR ref. Trying head SHA..."
    git fetch origin $HEAD_SHA 2>/dev/null || {
      echo "Warning: Could not fetch PR commits. Analysis will be based on available git history."
    }
  }

  # Checkout the head commit
  if git rev-parse pr-$PR_NUMBER >/dev/null 2>&1; then
    git checkout pr-$PR_NUMBER
  elif git rev-parse $HEAD_SHA >/dev/null 2>&1; then
    git checkout $HEAD_SHA
  else
    echo "Warning: Could not checkout PR commits. Staying on current branch."
    echo "Analysis may be limited."
  fi
fi

echo ""
echo "Running BC review with Claude Code..."
echo ""

claude --dangerously-skip-permissions << EOF
REPO: woocommerce/woocommerce
PR NUMBER: $PR_NUMBER

PRIMARY OBJECTIVE: Backwards Compatibility (BC) Review for WooCommerce/WordPress

Only report on BC risks and required deprecations. Ignore styling, formatting, comments, and pure test/doc changes unless they mask a BC concern.

Output format (strict):
- Summary: Overall risk [None|Low|Medium|High] and a 2 to 4 sentence rationale.
- Findings: For each item → [Severity: Low|Medium|High] file:line — what changed, how it breaks, affected integrators, likelihood, mitigation/replacement, and a short example when relevant.
- Deprecations Needed: list items that require deprecation with proposed replacement API and @deprecated notes (or _deprecated_* / wc_deprecated_*).
- Testing Focus: targeted regression areas (e.g., checkout, gateways, subscriptions) with concrete steps.
- Communication: changelog entry, labels, docs/migration-guide updates, outreach to extension developers.
- Confidence: a percentage and one-sentence justification.

Scope to analyze:
- PHP: public/protected API signature/visibility changes; default param or type-hint changes; thrown exceptions; removed/renamed hooks (do_action, apply_filters); template changes under templates/**; REST params/response shapes; DB/schema/options changes; global constants/vars; composer constraints.
- JS/Blocks: block names/attributes; script/style handle names, dependencies, and load order; REST schemas; data-store selectors/actions; settings/options keys.
- Ecosystem impact: payment gateways, popular Woo extensions (Subscriptions/Bookings/Memberships), themes customizing templates, custom checkout flows.

Method:
- Prefer exact citations with file:line for every item (from the diff and repo).
- Provide mitigation or migration guidance for each breaking/deprecation.
- If uncertain, state what evidence is missing and rate likelihood.
- Use inline comments for line-specific concerns and one top-level summary comment.

Ignore/limit noise and cost:
- Exclude generated/binary/third-party content (e.g., vendor/**, node_modules/**, build/**, dist/**, *.min.*, translations *.mo/*.po).
- Focus on files changed in this PR and related API touch points.

If no BC issues are found, explicitly state: 'No breaking changes detected' and explain why, including deprecation sufficiency and ecosystem considerations.
EOF