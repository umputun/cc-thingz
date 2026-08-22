---
name: backlog
description: Read, work, and maintain a Git repo's deferred-work items in docs/backlog/, one file per item. Use when the user says "backlog", "check backlog", "what's on my backlog", "work the backlog", "address the backlog", "add to backlog", "clean up backlog", or when a review or task produced items that are real but not being fixed now. Owns the item format and the create-then-delete lifecycle.
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, AskUserQuestion
---

# Backlog

`docs/backlog/` at a repo root holds work that is real but not being done now: a defect a change did not
introduce, drift with no user-visible symptom, a fix whose blast radius exceeded its value, an idea worth
keeping. One file per item. It is the maintainer's own list — it never gates anything and never reaches a
contributor.

The directory path is fixed, so every invocation in a repo reads and writes one predictable store.

**Git only.** The lifecycle is expressed in Git — `git rm` to close an item, branch detection before
writing, staging and committing the file. Outside a Git repository, say so plainly and stop; do not
improvise an equivalent in another VCS.

## Item format

`docs/backlog/<slug>.md`. The slug names the defect, not the file it lives in
(`reopen-fallback-ignores-frontmost.md`), so it can be cited from a commit and dedupe is a filename check.

```markdown
---
worth: later
where: internal/window/library.go:537
added: 2026-08-05
---
# reopen fallback ignores the last-frontmost window

`reopen`'s fallback ignores which window was last frontmost once `frontmost` is nil, so a multi-window
user's last-window capture replays only when the exited window happened to be `windows.first`. Surfaced
reviewing PR #370; the fix touches restore ordering, which is why it was deferred rather than done inline.
```

Three frontmatter fields, written once and rewritten only as **Appending** below allows:

- **`worth: yes | no | later`** — the triage call, and the field the list is ordered by:
  - **`yes`** — the value is agreed and it should be fixed. Says nothing about schedule: an item
    blocked on an upstream release is still `yes` if nobody disputes it is worth doing.
  - **`later`** — the value decision itself is unresolved, not the work. The body must name the unknown
    or the condition that would settle it; without that it is a `yes` or a `no` in disguise.
  - **`no`** — a decision not to fix, kept so the same finding is not rediscovered and re-argued by the
    next review that touches the file. Keep a `no` only while that rationale still earns its place; once
    it does not, delete the file rather than carrying it.
- **`where: path:line`** — omit when the item is not anchored to one place. The dedupe key alongside
  the slug, compared only when both items have one; two items missing it are not thereby the same item.
- **`added: YYYY-MM-DD`** — never updated, so it reads as age. A year-old item is itself information.
  Zero-pad it so the values sort lexically.

The H1 is the title. The body below it has no required sections — repro, what was tried, the review that
surfaced it, links, a snippet, in whatever shape suits. A two-line item stays two lines, a gnarly one gets
a page. Two items owe one sentence each, which a two-line body can carry: a `later` names the unknown that
would settle its value decision, and a `no` records why the fix was rejected, without which it cannot do
the anti-rediscovery job it is kept for.

## Lifecycle

Create the file. When the work lands, `git rm` it in the commit that lands the fix — not a separate cleanup
commit. There is no checkbox, no in-progress marker: the staged deletion is the state. Dropping an item
decided against is the same operation with a different reason.

## A slug as the argument

`/workflow:backlog <slug>` names one item: `docs/backlog/<slug>.md`, the file name without its extension. Read
that file alone, verify its `where` the same way step 2 below does when it has one, and go straight to the fix-or-drop
question for it — skip the listing, which is not what was asked for. A slug matching no file is a
mistake worth saying plainly: report it and list what is there instead of guessing at the nearest name.

## Reading and working the list

1. Glob `docs/backlog/*.md` from the repo root and read each file's frontmatter and H1. If the directory
   does not exist, say so plainly and offer to start one — do not create it empty.
2. **Verify before reporting.** `where` goes stale when a file is renamed or a line moves. For each item
   that has one, check the location still exists and still says what the item claims; report a stale item
   as stale rather than as work. An item without `where` has nothing to verify — carry it through as-is.
3. Report every item, one line each — `yes` first, then `later`, then `no`, oldest `added` first within
   each group. Include `where` for the items that have one. Do not editorialize; the item already carries
   its reasoning.
4. Offer concrete actions with **AskUserQuestion**, never prose, with a recommendation first:
   - **fix a named item now** — name the specific item in the option label, not "fix something";
   - **drop a named item** — a `no` whose rationale has stopped earning its place;
   - **leave it** — report only, nothing changes.

   With more than four items, group them across several questions rather than truncating the list.
5. On "fix it now": do the work under the usual gates — tests, formatters, linters — and `git rm` the file
   in the same commit. Never auto-commit.

## Appending

When a run produces deferred items, offer to append them; never write silently.

**Never add a backlog item to an unrelated work branch.** Repo-wide notes dropped into someone else's
in-progress branch get swept into that branch's diff or vanish with it. Check the branch before creating
the directory or writing any file:

1. Detect the repository's default branch: read `git symbolic-ref refs/remotes/origin/HEAD` and strip
   the `refs/remotes/origin/` prefix. If that command fails or returns nothing — it exits non-zero when
   the ref is not symbolic, which is the usual signal — fall back to two ordered passes with
   `git rev-parse --verify`, remote first and complete before local: `refs/remotes/origin/master`, then
   `refs/remotes/origin/main`, then `refs/remotes/origin/trunk`; only if none of the three resolves, try
   `refs/heads/master`, then `refs/heads/main`, then `refs/heads/trunk`. Never interleave the two passes
   per candidate — a repo migrated to `main` can keep a stale local `master`, and checking local `master`
   before remote `main` picks the dead branch as the default. Probe the full ref paths, so a tag of the
   same name cannot answer for a branch.
2. Compare it with `git branch --show-current`. If no default branch was found at all, say so and take
   the "anywhere else" case below: there is nothing to compare against, so the answer must come from
   the user rather than from a guess.
   - **On the default branch** — write in place.
   - **Anywhere else** — report the current branch by name, or `detached HEAD at <sha>` when the command
     returns nothing, and ask whether to write in this checkout anyway. On yes, write here. On no, change
     nothing: do not create a branch, a worktree, or a temp checkout, do not switch the current checkout,
     and do not pick a destination the user did not name.

**Dedupe before writing**, on `where` first and the slug second. A pre-existing defect surfaces in every
review that touches its file, so the same item arrives repeatedly. If it is already there, say so and leave
it alone. If the new sighting sharpens the description or changes the `worth` call, edit that file in place
rather than adding a second one.

Create `docs/backlog/` if it does not exist — after the branch check above, never before it.

When the files are written, read `git diff --cached --name-only` before offering anything. Nothing has
been staged yet at that point, so anything it lists is pre-existing — including another backlog file from
an earlier run. If it lists anything at all, do not commit: report what is staged and let the user resolve
it, because a plain `git commit` would sweep it in alongside the item. With an empty index, offer the next
step with **AskUserQuestion**, staging the exact paths this invocation created or edited and not the
directory — an item bundled with the run's other changes violates the rule below. Never commit without that
answer. Offer commit and push together: a backlog item is notes with no code in it, and unpushed it stays
invisible from every other machine, so the push is part of filing rather than an upsell.

## Rules

- **Never post a backlog item to a PR, MR, or issue thread** unless the user explicitly asks. These are the
  maintainer's cleanup notes; surfacing them on a contributor's change reads as scope pressure.
- **Never auto-commit** an item file, and never commit it alongside unrelated work.
- **Do not fix an item without being asked.** Reading the backlog is not permission to work it.
- **Prefer deleting to demoting** for an item nobody will ever do and whose reasoning nobody needs — say
  so and offer to drop it. This does not reach a `no` that is still doing its job of stopping a
  rediscovery; that one stays.
