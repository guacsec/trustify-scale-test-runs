#!/bin/bash

# Fetches merged PRs from guacsec/trustify and injects them into markers.json
# as the "trustify-prs" group. Requires gh (GitHub CLI) and jq.

set -euo pipefail

cd "$(dirname "$0")"

MARKERS_FILE="publish/markers.json"
REPO="guacsec/trustify"
GROUP="trustify-prs"

if ! command -v gh &> /dev/null; then
    echo "Warning: gh CLI not found, skipping PR marker generation"
    exit 0
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not found"
    exit 1
fi

if [ ! -f "$MARKERS_FILE" ]; then
    echo "Error: ${MARKERS_FILE} not found"
    exit 1
fi

# Determine start date from the earliest report
REPORTS=(publish/reports/report-*.json)
if [ -f "${REPORTS[0]}" ]; then
    EARLIEST=$(basename "${REPORTS[0]}" | sed 's/report-\([0-9-]*\)T.*/\1/')
else
    EARLIEST=""
fi
SINCE="${EARLIEST:-2026-04-01}"

echo "Fetching merged PRs from ${REPO} since ${SINCE}..."

if ! PR_MARKERS=$(gh api --paginate \
    "search/issues?q=repo:${REPO}+is:pr+is:merged+merged:>=${SINCE}&per_page=100&sort=created&order=asc" \
    --jq '[.items[] | {date: (.pull_request.merged_at[:10]), label: ("#\(.number)"), title: .title}]' \
    | jq -s 'add | sort_by(.date)'); then
    echo "Warning: Failed to fetch PRs from ${REPO}, skipping PR marker update"
    exit 0
fi
PR_COUNT=$(echo "$PR_MARKERS" | jq 'length')
echo "Found ${PR_COUNT} merged PRs"

jq --argjson prs "$PR_MARKERS" --arg group "$GROUP" \
    '.markers[$group] = $prs' \
    "$MARKERS_FILE" > "${MARKERS_FILE}.tmp" \
    && mv "${MARKERS_FILE}.tmp" "$MARKERS_FILE"

echo "Updated ${MARKERS_FILE} with ${PR_COUNT} PR markers"
