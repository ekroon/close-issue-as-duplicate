#!/bin/bash

# Script to close a GitHub issue as duplicate using gh CLI
# Usage: ./close-issue-duplicate.sh org/repo#123 [org/repo#456]
# If no duplicate issue is provided, it will just close the issue as duplicate without reference

set -euo pipefail

# Check if arguments are provided
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <issue_to_close> [duplicate_of_issue]"
    echo "Format: org/repo#<issue_number> [org/repo#<issue_number>]"
    echo "Example: $0 octocat/Hello-World#42 octocat/Hello-World#15"
    echo "Example: $0 octocat/Hello-World#42"
    echo ""
    echo "The first issue will be closed as a duplicate."
    echo "If a second issue is provided, it will be referenced as the original."
    exit 1
fi

# Parse the input arguments
ISSUE_TO_CLOSE="$1"
DUPLICATE_OF_ISSUE="${2:-}"

# Function to validate input format
validate_input() {
    local input="$1"
    local label="$2"
    
    if [[ ! "$input" =~ ^[^/]+/[^#]+#[0-9]+$ ]]; then
        echo "Error: Invalid format for $label. Expected format: org/repo#<issue_number>"
        echo "Example: octocat/Hello-World#42"
        exit 1
    fi
}

# Function to parse repo info
parse_repo_info() {
    local input="$1"
    local repo_part="${input%#*}"  # Everything before #
    local issue_number="${input##*#}"  # Everything after #
    local owner="${repo_part%/*}"  # Everything before /
    local repo="${repo_part#*/}"   # Everything after /
    
    echo "$owner" "$repo" "$issue_number"
}

# Validate issue to close
validate_input "$ISSUE_TO_CLOSE" "issue to close"

# Parse issue to close
read -r CLOSE_OWNER CLOSE_REPO CLOSE_ISSUE_NUMBER <<< "$(parse_repo_info "$ISSUE_TO_CLOSE")"

# Initialize variables for duplicate issue
DUP_OWNER=""
DUP_REPO=""
DUP_ISSUE_NUMBER=""

# If duplicate issue is provided, validate and parse it
if [ -n "$DUPLICATE_OF_ISSUE" ]; then
    validate_input "$DUPLICATE_OF_ISSUE" "duplicate of issue"
    read -r DUP_OWNER DUP_REPO DUP_ISSUE_NUMBER <<< "$(parse_repo_info "$DUPLICATE_OF_ISSUE")"
    
    echo "Closing issue #$CLOSE_ISSUE_NUMBER in $CLOSE_OWNER/$CLOSE_REPO as duplicate of #$DUP_ISSUE_NUMBER in $DUP_OWNER/$DUP_REPO..."
    
    # Verify the duplicate issue exists
    echo "Verifying duplicate issue exists..."
    DUP_ISSUE_CHECK=$(gh api graphql -f query="
query {
  repository(owner: \"$DUP_OWNER\", name: \"$DUP_REPO\") {
    issue(number: $DUP_ISSUE_NUMBER) {
      id
      title
      state
    }
  }
}" --jq '.data.repository.issue')

    if [ "$DUP_ISSUE_CHECK" = "null" ]; then
        echo "Error: Duplicate issue #$DUP_ISSUE_NUMBER not found in $DUP_OWNER/$DUP_REPO"
        exit 1
    fi

    DUP_ISSUE_STATE=$(echo "$DUP_ISSUE_CHECK" | jq -r '.state')
    DUP_ISSUE_TITLE=$(echo "$DUP_ISSUE_CHECK" | jq -r '.title')

    echo "✓ Found duplicate issue: #$DUP_ISSUE_NUMBER ($DUP_ISSUE_STATE) - $DUP_ISSUE_TITLE"
else
    echo "Closing issue #$CLOSE_ISSUE_NUMBER in $CLOSE_OWNER/$CLOSE_REPO as duplicate..."
fi

# Get the issue ID for the issue to close
echo "Getting issue ID for issue to close..."
CLOSE_ISSUE_ID=$(gh api graphql -f query="
query {
  repository(owner: \"$CLOSE_OWNER\", name: \"$CLOSE_REPO\") {
    issue(number: $CLOSE_ISSUE_NUMBER) {
      id
      title
      state
    }
  }
}" --jq '.data.repository.issue.id')

if [ -z "$CLOSE_ISSUE_ID" ] || [ "$CLOSE_ISSUE_ID" = "null" ]; then
    echo "Error: Issue #$CLOSE_ISSUE_NUMBER not found in $CLOSE_OWNER/$CLOSE_REPO"
    exit 1
fi

CLOSE_ISSUE_INFO=$(gh api graphql -f query="
query {
  repository(owner: \"$CLOSE_OWNER\", name: \"$CLOSE_REPO\") {
    issue(number: $CLOSE_ISSUE_NUMBER) {
      title
      state
    }
  }
}" --jq '.data.repository.issue')

CLOSE_ISSUE_STATE=$(echo "$CLOSE_ISSUE_INFO" | jq -r '.state')
CLOSE_ISSUE_TITLE=$(echo "$CLOSE_ISSUE_INFO" | jq -r '.title')

echo "✓ Found issue to close: #$CLOSE_ISSUE_NUMBER ($CLOSE_ISSUE_STATE) - $CLOSE_ISSUE_TITLE"

# Check if the issue is already closed
if [ "$CLOSE_ISSUE_STATE" = "CLOSED" ]; then
    echo "Warning: Issue #$CLOSE_ISSUE_NUMBER is already closed"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Add a comment before closing if duplicate issue is specified
if [ -n "$DUPLICATE_OF_ISSUE" ]; then
    echo "Adding duplicate reference comment..."
    DUPLICATE_COMMENT="Duplicate of $DUP_OWNER/$DUP_REPO#$DUP_ISSUE_NUMBER"
    
    gh api \
      --method POST \
      "/repos/$CLOSE_OWNER/$CLOSE_REPO/issues/$CLOSE_ISSUE_NUMBER/comments" \
      -f body="$DUPLICATE_COMMENT" \
      --jq '"Added comment: \(.body)"' > /dev/null
else
    echo "Adding duplicate closure comment..."
    CURRENT_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    DUPLICATE_COMMENT="Closed as duplicate by @ekroon on $CURRENT_DATE"
    
    gh api \
      --method POST \
      "/repos/$CLOSE_OWNER/$CLOSE_REPO/issues/$CLOSE_ISSUE_NUMBER/comments" \
      -f body="$DUPLICATE_COMMENT" \
      --jq '"Added comment: \(.body)"' > /dev/null
fi

# Close the issue as duplicate using GraphQL mutation
echo "Closing issue as duplicate..."
RESULT=$(gh api graphql -f query="
mutation {
  closeIssue(input: {
    issueId: \"$CLOSE_ISSUE_ID\",
    stateReason: DUPLICATE
  }) {
    issue {
      number
      state
      stateReason
      url
    }
  }
}" --jq '.data.closeIssue.issue')

ISSUE_URL=$(echo "$RESULT" | jq -r '.url')
ISSUE_STATE=$(echo "$RESULT" | jq -r '.state')
ISSUE_STATE_REASON=$(echo "$RESULT" | jq -r '.stateReason')

echo "✅ Successfully closed issue #$CLOSE_ISSUE_NUMBER as $ISSUE_STATE_REASON"
echo "   Issue URL: $ISSUE_URL"

if [ -n "$DUPLICATE_OF_ISSUE" ]; then
    echo "   Duplicate of: $DUP_OWNER/$DUP_REPO#$DUP_ISSUE_NUMBER"
else
    echo "   Closed as duplicate without specific reference"
fi
