---
name: last-tag
description: Show commits since the last git tag in a formatted table. Use when user asks "what changed since last release", "commits since last tag", "last-tag", "what's new", or wants to see recent unreleased changes.
allowed-tools: Bash, AskUserQuestion
---

# Last Tag - Commits Since Last Release

Show commits since the last git tag in a formatted table with optional details.

## Activation Triggers

- "last tag", "last-tag", "since last tag"
- "what changed since last release"
- "commits since last tag"
- "what's new", "unreleased changes"

## Workflow

**Important**: Avoid `$()` command substitution in Bash tool - use sequential steps.

1. Fetch tags from remote and get the last tag:
```bash
git fetch origin --tags
```
Then get the last tag:
```bash
git describe --tags --abbrev=0
```
Store this value (e.g., `v1.2.3`) for use in subsequent commands.

2. Get commits since that tag with format `date|author|hash|subject` (substitute TAG with actual value):
```bash
git log TAG..HEAD --format="%ad|%an|%h|%s" --date=short
```

3. Check if all commits have the same author - extract unique authors from step 2 output.
If only one unique author name appears in all rows, it's a single author.

4. Format output:

**If single author** (count = 1):
```
Last tag: v1.2.3
Author: John Doe

| Date       | Commit  | Description                    |
|------------|---------|--------------------------------|
| 2025-12-20 | abc1234 | fix: resolve null pointer      |
| 2025-12-19 | def5678 | feat: add user authentication  |
```

**If multiple authors** (count > 1):
```
Last tag: v1.2.3

| Date       | Author   | Commit  | Description                    |
|------------|----------|---------|--------------------------------|
| 2025-12-20 | John Doe | abc1234 | fix: resolve null pointer      |
| 2025-12-19 | Jane Doe | def5678 | feat: add user authentication  |
```

**If no tag exists**:
```
No tags found in repository
```

**If no commits since tag**:
```
Last tag: v1.2.3
No commits since this tag
```

## Interactive Details

After displaying the table, use AskUserQuestion:

```
question: "Show commit details?"
header: "Details"
options:
  - label: "All commits"
    description: "Show full details for each commit"
  - label: "None"
    description: "Skip details"
  - label: "Specific commit"
    description: "Enter commit hash to inspect"
```

**If "All commits"**: For each commit, run:
```bash
git show --stat --format="Commit: %h%nAuthor: %an <%ae>%nDate: %ad%n%n%s%n%n%b" --date=short HASH
```
This shows: commit hash, author with email, date, subject, body, and file change stats.

**If "None"**: End.

**If "Specific commit"** or user enters hash via "Other": Run the same `git show` command for that commit only.
