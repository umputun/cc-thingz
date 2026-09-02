#!/bin/bash
# generate release notes from PRs/MRs and commits
# usage: get-notes.sh <platform>
# platform: github, gitlab, or gitea
# outputs: release notes grouped by type (features, improvements, fixes)

set -e

platform="$1"

if [ -z "$platform" ]; then
    echo "error: platform required (github, gitlab, gitea)" >&2
    exit 1
fi

# reject anything else rather than falling through every branch below and returning
# commit-only notes with exit 0, which reads as a successful run that just found no PRs
case "$platform" in
    github|gitlab|gitea) ;;
    *)
        echo "error: unknown platform: $platform (expected github, gitlab or gitea)" >&2
        exit 1
        ;;
esac

# fetch tags from remote to ensure we have the latest
git fetch origin --tags 2>/dev/null || true

# get last tag
last_tag=$(git describe --tags --abbrev=0 --match "v*" 2>/dev/null || echo "")

# get tag date in UTC (empty if no tag). jq compares these timestamps as strings, and
# the forge APIs report merge times in UTC with a 'Z' suffix, so the tag date must be
# rendered the same way. %aI would keep the author's local offset, which makes the
# string compare wrong by that offset -- PRs merged just after the tag get dropped.
# creatordate is the tag's own time (tagger time for annotated tags, committer time for
# lightweight ones); the tagged commit's *author* date survives rebases and cherry-picks
# and can predate the tag by days, which re-lists already-released PRs
# initialised unconditionally: an untagged repo would otherwise read whatever an
# inherited environment variable named tag_date held and filter PRs against it
tag_date=""
if [ -n "$last_tag" ]; then
    tag_date=$(TZ=UTC git for-each-ref --format='%(creatordate:format-local:%Y-%m-%dT%H:%M:%SZ)' "refs/tags/$last_tag" 2>/dev/null)
    if [ -z "$tag_date" ]; then
        # || true: set -e would otherwise kill the run with git's bare exit code and no
        # message if the tag resolves for describe but not for log
        tag_date=$(TZ=UTC git log -1 --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd "$last_tag" 2>/dev/null) || true
    fi
fi

# temp files for collecting entries
features=$(mktemp)
improvements=$(mktemp)
fixes=$(mktemp)
other=$(mktemp)
forge_out=$(mktemp)
forge_err=$(mktemp)
shaped=$(mktemp)
page_out=$(mktemp)
pages=$(mktemp)
trap 'rm -f "$features" "$improvements" "$fixes" "$other" "$forge_out" "$forge_err" "$shaped" "$page_out" "$pages"' EXIT

# categorize entry by conventional commit prefix
# usage: categorize "description" "suffix"
# suffix is "#123 @author" for PRs or "abc1234" for commits
categorize() {
    local desc="$1"
    local suffix="$2"
    local lower_desc
    lower_desc=$(echo "$desc" | tr '[:upper:]' '[:lower:]')

    # strip conventional prefix for cleaner output
    local clean_desc
    clean_desc=$(echo "$desc" | sed -E 's/^(feat|fix|refactor|perf|chore|docs|style|build|ci|test)(\([^)]*\))?[[:space:]]*:[[:space:]]*//')

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

# run a forge CLI, collecting its output, and abort when it fails. at the head of a
# `cli | jq | while` pipeline the CLI's exit status is discarded (a pipeline reports
# only its last command) and its diagnostics went to /dev/null, so a missing,
# unauthenticated or rate-limited CLI read as "this release has no PRs" -- the same
# silent exit-0 hole the unknown-platform guard above closes, by the far more common
# route. an absent binary lands here too: bash reports 127 with its own message
run_forge_to() {
    local destination="$1"
    shift
    if ! "$@" >"$destination" 2>"$forge_err"; then
        echo "error: $1 failed: $(cat "$forge_err")" >&2
        exit 1
    fi
}

run_forge() {
    run_forge_to "$forge_out" "$@"
}

# print the length of a forge response after verifying that it is a JSON array.
# pagination needs this before collect_prs shapes the final response, so malformed
# JSON must get the same explicit jq diagnostic rather than a bare set -e exit
json_array_length() {
    local source="$1"
    local count
    if ! count=$(jq -er \
        'if type == "array" then length else error("expected a JSON array") end' \
        <"$source" 2>"$forge_err"); then
        echo "error: jq failed to inspect the $platform PR list: $(cat "$forge_err")" >&2
        exit 1
    fi
    echo "$count"
}

# gh pr list has no page flag. grow its total limit until the returned array is
# shorter than requested; the final response then contains every merged PR. a fixed
# limit exits 0 when truncated, which makes incomplete notes look authoritative
run_github_prs() {
    local fields="$1"
    local limit=50
    local count
    while true; do
        run_forge gh pr list --state merged --limit "$limit" --json "$fields"
        count=$(json_array_length "$forge_out")
        [ "$count" -lt "$limit" ] && break
        limit=$((limit * 2))
    done
}

# glab exposes a page number but reads only one 30-item page by default. request the
# API maximum explicitly and combine pages until the first short response
run_gitlab_prs() {
    local page=1
    local per_page=100
    local count
    : >"$pages"
    while true; do
        run_forge_to "$page_out" glab mr list --merged -F json \
            --page "$page" --per-page "$per_page"
        count=$(json_array_length "$page_out")
        cat "$page_out" >>"$pages"
        printf '\n' >>"$pages"
        [ "$count" -lt "$per_page" ] && break
        page=$((page + 1))
    done
    if ! jq -s 'add' "$pages" >"$forge_out" 2>"$forge_err"; then
        echo "error: jq failed to combine the gitlab MR pages: $(cat "$forge_err")" >&2
        exit 1
    fi
}

# feed collected PR/MR JSON through jq and categorize each entry
# usage: collect_prs <jq args...>
# jq's exit status is checked too: an absent jq (not installed by default on macOS)
# would otherwise drain the pipeline and leave the same "no PRs" notes. it does not
# catch a forge renaming a field -- jq reads a missing key as null and still exits 0,
# so the row is either dropped by a select() or interpolated into the entry as the
# text "null". only a type change errors out. the field names are pinned by tests instead:
# github by 11, 11b, 12 and 12d in tests/test-release-tools.sh, gitlab by 12b and 12c
collect_prs() {
    if ! jq -r "$@" <"$forge_out" >"$shaped" 2>"$forge_err"; then
        echo "error: jq failed to shape the $platform PR list: $(cat "$forge_err")" >&2
        exit 1
    fi
    while IFS=$'\t' read -r title suffix; do
        categorize "$title" "$suffix"
    done <"$shaped"
}

# collect PRs/MRs.
# the $date inside each filter is a jq variable bound by --arg in collect_prs, not a
# shell expansion -- the directive covers the whole if-statement below
# shellcheck disable=SC2016
if [ "$platform" = "github" ]; then
    if [ -n "$tag_date" ]; then
        run_github_prs number,title,mergedAt,author
        collect_prs --arg date "$tag_date" \
            '.[] | select(.mergedAt > $date) | "\(.title)\t#\(.number) @\(.author.login)"'
    else
        run_github_prs number,title,author
        collect_prs '.[] | "\(.title)\t#\(.number) @\(.author.login)"'
    fi
elif [ "$platform" = "gitlab" ]; then
    run_gitlab_prs
    if [ -n "$tag_date" ]; then
        collect_prs --arg date "$tag_date" \
            '.[] | select(.merged_at > $date) | "\(.title)\t!\(.iid) @\(.author.username)"'
    else
        collect_prs '.[] | "\(.title)\t!\(.iid) @\(.author.username)"'
    fi
elif [ "$platform" = "gitea" ]; then
    # `tea pr list` cannot supply merged-PR metadata: its `--state` accepts only
    # all|open|closed, and `--output json` serializes the printable table, so every value
    # is a flat string and no field it offers is a merged flag or a merge timestamp.
    # warn and fall through to commit-derived notes -- aborting here would make every
    # gitea release impossible, which is worse than the degraded notes gitea has always
    # produced. a real arm needs `tea api /repos/{owner}/{repo}/pulls?state=closed`,
    # whose raw REST payload does carry merged, merged_at, number and user.login
    echo "warning: gitea PR metadata is unavailable, notes are commit-derived only" >&2
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
