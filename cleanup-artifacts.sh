#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") -t TOKEN -u URL -p PROJECT_ID [-d]

Delete all job artifacts for a GitLab project.

Options:
    -t TOKEN        GitLab Private/Personal Access Token
    -u URL          GitLab instance URL (e.g. https://gitlab.example.com)
    -p PROJECT_ID   Numeric project ID
    -d              Dry-run: only show what would be deleted
    -h              Show this help
EOF
    exit 1
}

TOKEN=""
GITLAB_URL=""
PROJECT_ID=""
DRY_RUN=false

while getopts "t:u:p:dh" opt; do
    case "$opt" in
        t) TOKEN="$OPTARG" ;;
        u) GITLAB_URL="${OPTARG%/}" ;;
        p) PROJECT_ID="$OPTARG" ;;
        d) DRY_RUN=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "$TOKEN" || -z "$GITLAB_URL" || -z "$PROJECT_ID" ]]; then
    echo "Error: -t, -u, and -p are required." >&2
    usage
fi

API_BASE="$GITLAB_URL/api/v4/projects/$PROJECT_ID"

api_get() {
    curl -s --header "PRIVATE-TOKEN: $TOKEN" "$1"
}

api_delete() {
    curl -s -o /dev/null -w "%{http_code}" --request DELETE --header "PRIVATE-TOKEN: $TOKEN" "$1"
}

echo "Fetching jobs with artifacts for project $PROJECT_ID..."
echo "  API: $API_BASE/jobs"

page=1
per_page=100
job_ids=()
total_jobs=0

while true; do
    echo -n "  Page $page: fetching... "
    response=$(api_get "$API_BASE/jobs?per_page=$per_page&page=$page&order_by=created_at&sort=asc")

    # Check for API error (error responses are objects, not arrays)
    if echo "$response" | jq -e 'type == "object"' >/dev/null 2>&1; then
        echo "ERROR"
        echo "API Error: $response" >&2
        exit 1
    fi

    count=$(echo "$response" | jq 'length')
    echo -n "$count jobs"

    if [[ "$count" -eq 0 ]]; then
        echo " (empty, done)"
        break
    fi

    total_jobs=$((total_jobs + count))

    # Extract job IDs that have artifacts, sorted oldest first
    ids=$(echo "$response" | jq -r '[.[] | select(.artifacts != null and (.artifacts | length > 0))] | sort_by(.created_at) | .[].id')

    if [[ -z "$ids" ]]; then
        echo ", 0 with artifacts"
        page=$((page + 1))
        continue
    fi

    artifact_count=0
    while IFS= read -r id; do
        job_ids+=("$id")
        artifact_count=$((artifact_count + 1))
    done <<< "$ids"

    echo ", $artifact_count with artifacts"

    if [[ "$count" -lt "$per_page" ]]; then
        break
    fi

    page=$((page + 1))
done

echo "Scanned $total_jobs jobs across $page page(s)."

total=${#job_ids[@]}

if [[ "$total" -eq 0 ]]; then
    echo "No job artifacts found."
    exit 0
fi

if $DRY_RUN; then
    echo "[DRY-RUN] Found $total jobs with artifacts:"
    for id in "${job_ids[@]}"; do
        echo "  Job #$id"
    done
    echo "[DRY-RUN] No artifacts were deleted. Remove -d to delete."
    exit 0
fi

echo "Found $total jobs with artifacts. Deleting..."

success=0
failed=0

for id in "${job_ids[@]}"; do
    status=$(api_delete "$API_BASE/jobs/$id/artifacts")
    current=$((success + failed + 1))

    if [[ "$status" -eq 204 ]]; then
        echo "  [$current/$total] Job #$id — deleted"
        success=$((success + 1))
    else
        echo "  [$current/$total] Job #$id — failed (HTTP $status)" >&2
        failed=$((failed + 1))
    fi
done

echo ""
echo "Done. $success deleted, $failed failed."

if [[ "$failed" -gt 0 ]]; then
    exit 1
fi
