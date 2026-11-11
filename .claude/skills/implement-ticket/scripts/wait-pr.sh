#!/usr/bin/env bash
# Wait on a pull request until it needs attention, then print one RESULT= line.
#
# Usage: bash wait-pr.sh <pr-number> <ci|merge> [interval-seconds] [max-minutes]
#   ci    : returns as soon as the PR is ready (green), conflicting, failing, or closed.
#   merge : returns when the PR is merged or closed, or when it turns conflicting or failing.
#
# RESULT values: green | no-checks | conflict | ci-failed | merged | closed | timeout
set -euo pipefail

pr="${1:?pr number required}"
mode="${2:?mode required (ci|merge)}"
interval="${3:-30}"
max_minutes="${4:-60}"
no_checks_grace=300 # seconds without any check before concluding there is no CI

case "$mode" in ci | merge) ;; *) echo "unknown mode: $mode" >&2; exit 2 ;; esac

start=$(date +%s)
deadline=$((start + max_minutes * 60))

gh_failures=0

while :; do
  # A transient gh/network error must not end the wait without a RESULT line.
  if ! json=$(gh pr view "$pr" --json state,mergeable,statusCheckRollup,url 2>/dev/null); then
    gh_failures=$((gh_failures + 1))
    echo "$(date "+%H:%M:%S") gh pr view failed ($gh_failures)" >&2
    if ((gh_failures >= 5)); then
      echo "RESULT=timeout gh-unavailable"
      exit 0
    fi
    sleep "$interval"
    continue
  fi
  gh_failures=0
  json=$(jq '.statusCheckRollup //= []' <<<"$json")
  state=$(jq -r '.state' <<<"$json")
  mergeable=$(jq -r '.mergeable' <<<"$json")
  total=$(jq '.statusCheckRollup | length' <<<"$json")
  # CheckRun entries have status/conclusion; StatusContext entries have state.
  pending=$(jq '[.statusCheckRollup[]
    | select((.status // "COMPLETED") != "COMPLETED" or (.state // "") == "PENDING" or (.state // "") == "EXPECTED")]
    | length' <<<"$json")
  failed=$(jq -r '[.statusCheckRollup[]
    | select((.conclusion // .state // "") | IN("FAILURE","CANCELLED","TIMED_OUT","ACTION_REQUIRED","ERROR","STARTUP_FAILURE"))
    | (.name // .context)] | join(", ")' <<<"$json")

  echo "$(date '+%H:%M:%S') state=$state mergeable=$mergeable checks=$total pending=$pending failed=[${failed}]"

  result=""
  if [[ "$state" == "MERGED" ]]; then
    result="merged"
  elif [[ "$state" == "CLOSED" ]]; then
    result="closed"
  elif [[ "$mergeable" == "CONFLICTING" ]]; then
    result="conflict"
  elif [[ -n "$failed" ]]; then
    result="ci-failed"
  elif [[ "$mode" == "ci" && "$mergeable" == "MERGEABLE" && "$pending" -eq 0 ]]; then
    if [[ "$total" -gt 0 ]]; then
      result="green"
    elif (($(date +%s) - start >= no_checks_grace)); then
      result="no-checks"
    fi
  fi

  if [[ -n "$result" ]]; then
    echo "RESULT=$result $(jq -r '.url' <<<"$json")"
    exit 0
  fi

  if (($(date +%s) >= deadline)); then
    echo "RESULT=timeout $(jq -r '.url' <<<"$json")"
    exit 0
  fi

  sleep "$interval"
done
