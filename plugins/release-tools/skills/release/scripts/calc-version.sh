#!/bin/bash
# calculate new semantic version from last tag
# usage: calc-version.sh <release_type>
# release_type: major, minor, hotfix
# outputs: new version (e.g., v1.2.3)

set -e

release_type="$1"

if [ -z "$release_type" ]; then
    echo "error: release type required (major, minor, hotfix)"
    exit 1
fi

# fetch tags from remote to ensure we have the latest
git fetch origin --tags 2>/dev/null || true

# get last tag
last_tag=$(git describe --tags --abbrev=0 --match "v*" 2>/dev/null || echo "")

# first release defaults
if [ -z "$last_tag" ]; then
    case "$release_type" in
        major) echo "v1.0.0" ;;
        minor) echo "v0.1.0" ;;
        hotfix) echo "v0.0.1" ;;
        *) echo "error: invalid type: $release_type"; exit 1 ;;
    esac
    exit 0
fi

# parse version (strip 'v' prefix and any pre-release suffix)
version="${last_tag#v}"
base_version="${version%%-*}"
IFS='.' read -r major minor patch <<< "$base_version"

# validate
if ! [[ "$major" =~ ^[0-9]+$ ]] || ! [[ "$minor" =~ ^[0-9]+$ ]] || ! [[ "$patch" =~ ^[0-9]+$ ]]; then
    echo "error: cannot parse version from $last_tag"
    exit 1
fi

# calculate new version
case "$release_type" in
    major) echo "v$((major + 1)).0.0" ;;
    minor) echo "v${major}.$((minor + 1)).0" ;;
    hotfix) echo "v${major}.${minor}.$((patch + 1))" ;;
    *) echo "error: invalid type: $release_type"; exit 1 ;;
esac
