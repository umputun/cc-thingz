---
name: pr
description: Comprehensive PR/issue review - analyzes architecture, tests, identifies unrelated changes mixed in, drafts review comment or issue comment. Use when user asks to review a PR, check a PR, look at PR changes, or comment on an issue.
argument-hint: '<pr-or-issue-number>'
allowed-tools: Bash, Read, Grep, Glob, Write, Skill, AskUserQuestion, Task
---

# PR Review Skill

Comprehensive pull request review that analyzes code quality, architecture, test coverage, and identifies scope creep (unrelated changes mixed into the PR).

## Activation Triggers

- "review pr 123", "check pr 123", "look at pr 123"
- "review the pr", "what do you think about this pr"
- "review draft pr", "check the open pr"
- "comment on issue 42", "look at issue 42", "review issue 42"

## Workflow

```
1. Fetch PR metadata + discussion history + merge status
1.5. Ask review mode: Full (default) or Quick
--- Full path ---
2. Setup worktree, launch subagent for deep analysis (read files, validate, architecture, scope creep, cleanup)
3. Present condensed findings from subagent, ask to proceed
4. Resolve open questions (if any)
5. Draft review comment
--- Quick path ---
Q1. Read diff inline, summarize what/why/size
Q2. Flag obvious issues from diff
Q3. Draft review comment
```

## Phase 0: Detect PR vs Issue

Determine if the target is a PR or an issue. If a URL is provided, check if it contains `/pull/` or `/issues/`. If just a number, detect type:
```bash
gh pr view <number> --json number 2>/dev/null && echo "PR" || echo "ISSUE"
```

- **PR** → proceed with full PR review workflow (Phase 1 onwards)
- **Issue** → use the **Issue Comment Flow** below, skip all PR-specific phases

### Issue Comment Flow

For issues, skip worktree/diff/architecture analysis. Focus on understanding the issue and drafting a helpful comment.

1. **Fetch issue details and discussion**:
```bash
gh issue view <number> --json title,body,author,state,labels,comments,createdAt
```

2. **Read the full discussion** - understand what was reported, what others said, whether there are linked PRs

3. **Investigate the codebase** if the issue references specific code, files, or behavior:
   - search for relevant files, read them
   - understand the reported problem in context

4. **Draft a comment** addressing the issue - could be: analysis of root cause, a proposed approach, questions for clarification, or acknowledgment with next steps

5. **Post as a regular comment** (not a review):
```bash
cat > /tmp/issue-comment.md << 'COMMENT_END'
<comment content>
COMMENT_END
gh issue comment <number> --body-file /tmp/issue-comment.md
```

Use AskUserQuestion before posting:
```
question: "Post this comment to issue #<number>?"
header: "Comment"
options:
  - Post (post as shown above)
  - Edit (tell me what to change)
  - Cancel (discard draft)
```

After posting → done. No worktree cleanup needed for issues.

---

## Phase 1: Fetch PR Metadata and Discussion History

Get PR number from $ARGUMENTS. If not provided, list recent PRs and ask user to select:

```bash
# if no PR number provided, list recent PRs
gh pr list --limit 5 --state all

# get PR details
gh pr view <number> --json title,body,additions,deletions,changedFiles,files,author,state,headRefName

# get all comments (PR comments and review comments)
gh pr view <number> --json comments,reviews
```

Capture:
- **title**: what the PR claims to do
- **body**: detailed description, linked issues
- **files**: list of changed files with additions/deletions per file
- **scope**: total additions/deletions, number of files
- **discussion history**: all comments and reviews with authors and timestamps

### 1.1 Analyze Discussion History

Before reviewing, understand what has already been discussed:

```bash
# get PR comments (general discussion)
gh api repos/{owner}/{repo}/issues/<number>/comments --jq '.[] | "[\(.user.login)] \(.body)"'

# get review comments (inline code comments)
gh api repos/{owner}/{repo}/pulls/<number>/comments --jq '.[] | "[\(.user.login) on \(.path):\(.line)] \(.body)"'

# get reviews with their state (approved, changes_requested, commented)
gh api repos/{owner}/{repo}/pulls/<number>/reviews --jq '.[] | "[\(.user.login) - \(.state)] \(.body)"'
```

Summarize discussion:
- What issues were raised by reviewers?
- What was the PR author's response?
- Are there unresolved threads or pending questions?
- What has already been addressed vs still open?

**Check automated reviews (Copilot, etc.)**: Read any automated review comments - they can have valuable findings. If Copilot or other bots flagged real issues, verify them and include in your review if valid. Don't dismiss automated feedback just because it's automated.

**CRITICAL - Check for inline suggestions:**
```bash
# get inline review comments (where actual suggestions live)
gh api repos/{owner}/{repo}/pulls/<number>/comments --jq '.[] | "[\(.user.login) on \(.path):\(.line // .original_line)]\n\(.body)\n---"'
```

Look specifically for:
- **Suggested changes** - code blocks with `suggestion` tags containing proposed fixes
- **Inline comments** - specific line-by-line feedback
- **Security/bug warnings** - automated tools often catch real issues

The review body is often just a summary. The **inline comments** are where the real feedback is.

**Important**: Do not re-raise issues that were already discussed and resolved. Focus on new findings or unaddressed concerns.

### 1.2 Check Merge Status

Check if PR is mergeable and CI status:

```bash
gh pr view <number> --json mergeable,mergeStateStatus,statusCheckRollup
```

Report:
- **mergeable**: MERGEABLE (no conflicts) or CONFLICTING (needs rebase)
- **mergeStateStatus**: CLEAN (ready), BLOCKED (checks failing), BEHIND (needs update)
- **statusCheckRollup**: CI check results (build, tests, lint)

If PR has conflicts or is behind, note this early - it may explain "deletions" in the diff that are actually just missing commits from the base branch.

Print summary:
```
PR #<number>: <title>
Author: <author> | State: <state>
+<additions>/-<deletions> across <changedFiles> files
Merge status: <mergeable> | <mergeStateStatus>
CI: <pass/fail summary>

Discussion: <N> comments, <M> reviews
- Resolved: <list of addressed issues>
- Open: <list of unresolved questions>
```

## Phase 1.5: Select Review Mode

After presenting the Phase 1 summary, ask the user to choose review depth:

```
question: "Review mode for PR #<number>?"
header: "Mode"
options:
  - Full review (Recommended) — clone, run tests/linter, architecture analysis, scope creep detection
  - Quick review — diff-only, summarize what/why/size, flag obvious issues
```

- **Full review** → continue to Phase 2 (existing deep analysis)
- **Quick review** → jump to Quick Review path below

## Quick Review Path

Lightweight review based on diff and metadata only. No worktree, no subagent, no test/linter execution.

### Q1. Read and Summarize Diff

```bash
gh pr diff <number>
```

From the diff and Phase 1 metadata, present:

- **What**: 2-3 sentence summary of what the PR does
- **Why**: purpose/motivation (from PR body, linked issues, or inferred from changes)
- **Size**: +additions/-deletions across N files - small/medium/large assessment
- **Files changed**: grouped list (code, tests, config, docs)

### Q2. Flag Obvious Issues

Scan the diff for issues detectable without full file context:

- Obvious bugs (nil dereference, unchecked errors, off-by-one)
- Missing error handling in new code
- Hardcoded values that should be configurable
- TODO/FIXME/HACK comments added
- Test files missing for new code files
- Large functions added (50+ lines)
- Unrelated changes mixed in (files that don't match PR purpose)

If nothing found, say so explicitly.

### Q3. Proceed to Draft

After presenting the summary and any flagged issues, skip directly to Phase 5 (Draft Review Comment). All Phase 5 rules apply: check previous comments, use writing-style skill, don't restate what the PR does.

**No worktree cleanup needed** since quick review never creates one.

## Phase 2: Deep Analysis via Subagent

**CRITICAL: Delegate all file reading, validation, and architecture analysis to a subagent** to protect the main conversation's context window. The subagent does the heavy lifting and returns a condensed report.

### 2.1 Setup Worktree (in main conversation)

Create the worktree before launching the subagent:

```bash
# fetch the PR ref directly (does NOT affect current checkout)
git fetch origin pull/<number>/head:pr-<number>

# create worktree from the fetched ref
git worktree add "/tmp/pr-review-<number>" pr-<number>
```

**Do NOT use `gh pr checkout`** - it switches the main repo's branch, which is disruptive during a review.

### 2.2 Launch Analysis Subagent

Use the **Task tool** with `subagent_type: "general-purpose"` to run the full analysis. Pass all context the subagent needs in the prompt:

```
prompt: |
  You are reviewing PR #<number> for <repo>.

  **PR metadata:**
  - Title: <title>
  - Description: <body>
  - Files: <file list from Phase 1>
  - Discussion summary: <from Phase 1.1>

  **Worktree location:** /tmp/pr-review-<number>
  **Repo location:** <repo_path>

  **Your tasks (do all of these):**

  1. **Read changed files** - read each changed file in full from the worktree
     to understand context, not just the diff. Focus on what the code actually
     does vs what the PR description claims.

  2. **Run validation** - from the worktree directory:
     - Run project test suite (e.g., `npm test`, `pytest`, `go test ./...`, etc.)
     - Run project linter (e.g., `eslint .`, `ruff check`, `golangci-lint run`, etc.)
     - Run race/concurrency checks if applicable (e.g., thread sanitizer, `-race` flag, etc.)
     Detect project type from files present (package.json, pyproject.toml, go.mod, Cargo.toml, etc.)
     Record all failures.

  3. **Architecture analysis** - check for:
     - Over-engineering (unnecessary abstractions, premature generalization)
     - Pattern violations (inconsistent with existing codebase)
     - Error handling issues
     - Concurrency issues
     - Security concerns
     - Test quality (fake tests, missing coverage)

  4. **Scope creep detection** - categorize each file as:
     - Core (implements PR purpose)
     - Supporting (tests, config for core changes)
     - Related cleanup (minor fixes in touched files)
     - Unrelated (doesn't connect to PR purpose)

  **IMPORTANT: Do NOT clean up the worktree.** The main conversation handles cleanup after all review phases complete.

  **Return a structured report with these sections:**
  - **Functionality**: 3-5 sentence explanation of what the PR does
  - **Key decisions**: notable implementation choices
  - **Validation results**: test pass/fail, linter issues, race conditions
  - **Architecture issues**: list with file:line references
  - **Over-engineering**: specific instances with simpler alternatives
  - **Scope creep**: unrelated files with explanation
  - **Positives**: what's done well
  - **Open questions**: design decisions that need user input

  Be specific - use file:line references. Skip sections with no findings.
```

### 2.3 Receive Report

The subagent returns a condensed report. This is what enters the main conversation context - not the raw file contents or diff.

## Phase 3: Present Findings, Ask to Proceed

Present the subagent's report to the user.

Use AskUserQuestion to confirm next step:

```
question: "How would you like to proceed?"
header: "Continue?"
options:
  - Draft review comment (proceed to Phase 5)
  - Investigate specific finding (ask subagent for details)
  - Done (end review without posting)
```

If user selects "Investigate specific finding", launch another targeted subagent to dig into the specific area, then ask again.

## Phase 4: Resolve Open Questions

If the subagent report contains open questions (design decisions needing user input), ask about EACH one specifically before proceeding:

```
question: "Section type change: Logger.PrintSection(string) → Logger.PrintSection(Section). Accept typed approach for compile-time safety?"
header: "Decision"
options:
  - Accept (keep typed Section approach)
  - Reject (revert to string-based)
  - Need more context
```

Wait for user response on each open question. If user selects:
- **Accept**: note for review comment
- **Reject**: note objection for review comment
- **Need more context**: launch targeted subagent to investigate, then ask again
- **Other** (custom input): incorporate user's feedback

Repeat for all open questions before proceeding.

## Phase 5: Draft Review Comment

Only proceed when user explicitly asks to draft/post the review.

### 5.1 Check Previous Comments (Critical)

**NEVER duplicate what the user already said in their previous comments.**

Before drafting, review the discussion history from Phase 1.1:
- What did the USER (not other reviewers) already comment on this PR?
- What issues did the USER already raise?
- What recommendations did the USER already make?

**Exclude from draft**:
- Architecture assessments the user already posted
- Issues the user already pointed out
- Questions the user already asked
- Any point the user already made, even if phrased differently

**Include in draft only**:
- NEW findings not mentioned by the user before
- Updates on issues (e.g., "tests still failing after fix attempt")
- Responses to contributor's questions to the user
- User's decision on open questions from Phase 4
- Valid issues from automated reviews (Copilot, etc.) that weren't addressed

If user already covered everything and there's nothing new → say "no new findings to add" and don't draft.

### 5.2 Draft Comment

Activate writing-style skill for proper tone:

```
/review:writing-style
```

**CRITICAL: Don't restate what the PR does.** The author knows what they built. Focus only on:
- Issues that need fixing
- Questions about unclear decisions
- LGTM if everything is fine

**Keep it casual and brief.** Examples of good review comments:

```markdown
LGTM
```

```markdown
lgtm. one minor thing - `loadPatterns` could filter in a single pass instead of two, but not a blocker
```

```markdown
couple issues:

1. test failure in `TestFoo` - looks like missing mock setup
2. linter complains about unused param on line 42

otherwise looks good
```

```markdown
I don't get why we need the Factory pattern here - there's only one implementation. could simplify to just `NewNotifier()` directly?
```

**Only add sections if there are actual issues:**

- **Issues** - test failures, linter errors, bugs (numbered list)
- **Questions** - unclear design decisions, missing context
- **Complexity concerns** - if over-engineered, suggest simpler alternative

**Omit sections with no findings.** For clean PRs, just "LGTM" is fine.

**Code examples**: when suggesting fixes, always show proper error handling - never ignore errors even in snippets.

## Output

### Display Draft First

Always display the complete draft review as a text block before asking:

```
--- Draft Review Comment ---
**Overall impression**

<actual review content here>

**Issues to address**
...
--- End Draft ---
```

### Ask User via AskUserQuestion

Use AskUserQuestion tool with these options:

```
question: "Post this review to PR #<number>?"
header: "Review"
options:
  - Approve (post review and approve)
  - Comment (post as review comment, no approval)
  - Request changes (post review requesting changes)
  - Edit (tell me what to change)
  - Cancel (discard draft)
```

### Handle Response

**Approve / Comment / Request changes**: Write to temp file and post as a formal PR review (not a regular comment). This ensures GitHub marks the review as done and it appears in `latestReviews`:
```bash
# write to temp file to avoid escaping issues
cat > /tmp/pr-review.md << 'REVIEW_END'
<review content>
REVIEW_END
# use --approve, --comment, or --request-changes based on user's choice
gh pr review <number> --body-file /tmp/pr-review.md --comment
```

**After Approve - offer to merge**:

When the user selected "Approve" and the approval was posted successfully, analyze the PR commits to recommend a merge strategy:

```bash
# check commit history for the PR
gh pr view <number> --json commits --jq '.commits[] | "\(.oid[:8]) \(.messageHeadline)"'
```

**Strategy recommendation logic:**
- **Rebase and merge (recommended)** when: commits are clean, well-structured, each with a meaningful message, no "fix typo" / "wip" / "fixup" noise
- **Squash and merge (recommended)** when: multiple messy commits (wip, fixup, typo fixes, "address review"), or a single logical change spread across noisy commits
- **Merge commit** when: branch has meaningful merge history worth preserving (rare)

Present the recommendation with reasoning:

```
# example for clean commits:
question: "PR #<number> approved. Merge strategy? (3 clean commits: 'add auth middleware', 'add auth tests', 'update docs')"
header: "Merge"
options:
  - Rebase and merge (Recommended) — preserves clean commit history
  - Squash and merge — collapse into single commit
  - Merge commit — creates merge commit
  - Skip — don't merge

# example for messy commits:
question: "PR #<number> approved. Merge strategy? (5 commits including 'wip', 'fix lint', 'address review')"
header: "Merge"
options:
  - Squash and merge (Recommended) — cleans up noisy commit history
  - Rebase and merge — preserves all commits as-is
  - Merge commit — creates merge commit
  - Skip — don't merge
```

If user selects a merge strategy:
```bash
# --rebase, --squash, or --merge based on user's choice
gh pr merge <number> --rebase --delete-branch
```

If merge fails (CI not passing, conflicts, branch protection), report the error and move on to cleanup.

**Edit**: Ask user for specific changes, update draft, display again, and repeat the ask.

**Cancel**: Acknowledge and stop.

### Cleanup Worktree

**After the review is fully complete** (comment posted, user cancelled, or user said "Done"), clean up:

```bash
cd <repo_path>
git worktree remove "/tmp/pr-review-<number>" --force 2>/dev/null || true
git branch -D pr-<number> 2>/dev/null || true
```

This must happen AFTER all phases are done - the worktree is needed for follow-up investigations in Phases 3-4.

## Examples

### Simple review (no issues)
```
User: "review pr 42"
→ Phase 1: fetch metadata, +150/-30, 5 files
→ Phase 2: launch subagent → reads files, tests pass, lint clean, no issues
→ Phase 3: present condensed report - adds retry logic with exponential backoff
→ User: "post the review"
→ Phase 5: draft and post "LGTM"
```

### Review with scope creep and questions
```
User: "review pr 58"
→ Phase 1: fetch metadata, +2k/-100, 25 files
→ Phase 2: launch subagent → reads 25 files, 1 test timeout, CacheFactory unnecessary,
    unrelated changes in config.yaml and Logger interface
→ Phase 3: present condensed report
→ User: "why does it use interface instead of concrete client?"
  → launch targeted subagent to investigate → interface allows mocking
→ User: "draft the review"
→ Phase 5: draft review highlighting issues, post to PR
```

### Review with over-engineering
```
User: "review pr 73"
→ Phase 1: fetch metadata, +800/-50, 12 files
→ Phase 2: launch subagent → reads files, tests pass, OVER-ENGINEERING:
    NotifierFactory, NotifierBuilder, NotifierRegistry for single email sender
→ Phase 3: present condensed report - suggest simplifying to EmailNotifier
→ User: "yeah, way too complex. draft the review"
→ Phase 5: draft review with specific simplification suggestions
```

### Quick review (trusted contributor)
```
User: "review pr 95"
→ Phase 1: fetch metadata, +200/-30, 6 files
→ Phase 1.5: [AskUserQuestion] "Review mode?" → user selects Quick
→ Q1: read diff, summarize: adds configurable tenant for auth
→ Q2: no obvious issues, tests included
→ Q3: draft and post "lgtm"
```

### Review with open questions
```
User: "review pr 89"
→ Phase 1: fetch metadata, +400/-50, 8 files
→ Phase 2: launch subagent → reads files, 2 test failures, open question
    about Section type change
→ Phase 3: present condensed report
→ Phase 4: [AskUserQuestion] "Section type change: Accept typed approach?"
  → User: "Accept"
→ User: "draft the review"
→ Phase 5: draft review noting test failures, user's acceptance of Section approach
```

## Notes

- **NEVER duplicate user's previous comments** - check what user already said in discussion history and exclude from draft
- **proper error handling in code suggestions** - never ignore errors even in example snippets; always show proper error checks
- **subagent for heavy lifting** - all file reading, validation, and architecture analysis runs in a subagent to protect main context window. Only the condensed report enters the main conversation
- **interactive by design** - pause for questions after presenting findings (Phase 3) and after resolving open questions (Phase 4)
- **explain non-obvious patterns** - don't assume user understands clever implementations
- **simplicity bias** - always ask "could this be simpler?" and suggest concrete alternatives
- **project patterns matter** - code should look like it belongs in the existing codebase
- **over-engineering is a bug** - unnecessary abstraction is as problematic as missing abstraction
- never switch the main repo's branch during review - use `git fetch` + worktree
- use writing-style skill for review comments
- be specific about file:line when noting issues
- distinguish "unrelated but acceptable" (linter fixes) from "unrelated and problematic" (refactoring)
- draft locally first, confirm before posting to PR
- let user guide when to proceed vs when to discuss more
