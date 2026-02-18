#!/bin/bash
# generate release notes from PRs/MRs and commits
# usage: get-notes.sh <platform>
# platform: github, gitlab, or gitea
# outputs: release notes grouped by type (features, improvements, fixes)

set -e

platform="$1"

if [ -z "$platform" ]; then
    echo "error: platform required (github, gitlab, gitea)"
    exit 1
fi

# fetch tags from remote to ensure we have the latest
git fetch origin --tags 2>/dev/null || true

# get last tag
last_tag=$(git describe --tags --abbrev=0 --match "v*" 2>/dev/null || echo "")

# get tag date in UTC ISO format (empty if no tag)
if [ -n "$last_tag" ]; then
    tag_date=$(git log -1 --format=%aI "$last_tag" 2>/dev/null)
fi

# temp files for collecting entries
features=$(mktemp)
improvements=$(mktemp)
fixes=$(mktemp)
other=$(mktemp)
trap "rm -f $features $improvements $fixes $other" EXIT

# categorize entry by conventional commit prefix
# usage: categorize "description" "suffix"
# suffix is "#123 @author" for PRs or "abc1234" for commits
categorize() {
    local desc="$1"
    local suffix="$2"
    local lower_desc=$(echo "$desc" | tr '[:upper:]' '[:lower:]')

    # strip conventional prefix for cleaner output
    local clean_desc=$(echo "$desc" | sed -E 's/^(feat|fix|refactor|perf|chore|docs|style|build|ci|test)(\([^)]*\))?[[:space:]]*:[[:space:]]*//')

    # format: "- description suffix"
    local entry="- ${clean_desc} ${suffix}"

    if [[ "$lower_desc" =~ ^feat ]]; then
        echo "$entry" >> "$features"
    elif [[ "$lower_desc" =~ ^fix ]]; then
        echo "$entry" >> "$fixes"
    elif [[ "$lower_desc" =~ ^(refactor|perf|chore|docs|style|build|ci|test) ]]; then
        echo "$entry" >> "$improvements"
    else
        echo "$entry" >> "$other"
    fi
}

# collect PRs/MRs
if [ "$platform" = "github" ]; then
    if [ -n "$tag_date" ]; then
        gh pr list --state merged --limit 50 --json number,title,mergedAt,author 2>/dev/null | \
            jq -r --arg date "$tag_date" \
            '.[] | select(.mergedAt > $date) | "\(.title)\t#\(.number) @\(.author.login)"' | \
            while IFS=$'\t' read -r title suffix; do
                categorize "$title" "$suffix"
            done
    else
        gh pr list --state merged --limit 20 --json number,title,author 2>/dev/null | \
            jq -r '.[] | "\(.title)\t#\(.number) @\(.author.login)"' | \
            while IFS=$'\t' read -r title suffix; do
                categorize "$title" "$suffix"
            done
    fi
elif [ "$platform" = "gitlab" ]; then
    if [ -n "$tag_date" ]; then
        glab mr list --merged -F json 2>/dev/null | \
            jq -r --arg date "$tag_date" \
            '.[] | select(.merged_at > $date) | "\(.title)\t!\(.iid) @\(.author.username)"' | \
            while IFS=$'\t' read -r title suffix; do
                categorize "$title" "$suffix"
            done
    else
        glab mr list --merged -F json 2>/dev/null | \
            jq -r '.[] | "\(.title)\t!\(.iid) @\(.author.username)"' | \
            while IFS=$'\t' read -r title suffix; do
                categorize "$title" "$suffix"
            done
    fi
elif [ "$platform" = "gitea" ]; then
    if command -v tea &>/dev/null; then
        if [ -n "$tag_date" ]; then
            tea pr list --state merged --output json 2>/dev/null | \
                jq -r --arg date "$tag_date" \
                '.[] | select(.merged > $date) | "\(.title)\t#\(.index) @\(.user.login)"' | \
                while IFS=$'\t' read -r title suffix; do
                    categorize "$title" "$suffix"
                done
        else
            tea pr list --state merged --output json 2>/dev/null | \
                jq -r '.[] | "\(.title)\t#\(.index) @\(.user.login)"' | \
                while IFS=$'\t' read -r title suffix; do
                    categorize "$title" "$suffix"
                done
        fi
    fi
fi

# collect commits (exclude merge commits)
if [ -n "$last_tag" ]; then
    git log "${last_tag}..HEAD" --oneline --no-merges --pretty="%h%x09%s" | \
        while IFS=$'\t' read -r hash msg; do
            categorize "$msg" "$hash"
        done
else
    git log --oneline --no-merges --pretty="%h%x09%s" -20 | \
        while IFS=$'\t' read -r hash msg; do
            categorize "$msg" "$hash"
        done
fi

# build output
output=""

if [ -s "$features" ]; then
    output="**New Features**
$(cat "$features")"
fi

if [ -s "$improvements" ]; then
    [ -n "$output" ] && output="$output

"
    output="${output}**Improvements**
$(cat "$improvements")"
fi

if [ -s "$fixes" ]; then
    [ -n "$output" ] && output="$output

"
    output="${output}**Bug Fixes**
$(cat "$fixes")"
fi

if [ -s "$other" ]; then
    [ -n "$output" ] && output="$output

"
    output="${output}**Other**
$(cat "$other")"
fi

echo "$output"
