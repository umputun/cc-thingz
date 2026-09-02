#!/bin/bash
# validate Codex marketplace structure and Codex-specific override resolution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MARKETPLACE="$REPO_ROOT/.agents/plugins/marketplace.json"
CODEX_ROOT="$REPO_ROOT/plugins/codex"
VALIDATOR_ROOT="$REPO_ROOT/.github/scripts/codex-validators"

TMP_ROOT="$(mktemp -d)"
case "$TMP_ROOT" in
    /tmp/*|/private/tmp/*|/private/var/*|/var/folders/*) ;;
    *) echo "FATAL: unsafe temp path: $TMP_ROOT" >&2; exit 1 ;;
esac
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

for plugin in "$CODEX_ROOT"/*; do
    [ -d "$plugin" ] || continue
    PYTHONDONTWRITEBYTECODE=1 python3 "$VALIDATOR_ROOT/validate_plugin.py" "$plugin"
done

while IFS= read -r -d '' skill_md; do
    PYTHONDONTWRITEBYTECODE=1 python3 "$VALIDATOR_ROOT/quick_validate.py" "${skill_md%/SKILL.md}"
done < <(find "$CODEX_ROOT" -path '*/skills/*/SKILL.md' -print0)

python3 - "$REPO_ROOT" "$MARKETPLACE" <<'PY'
import ast
import json
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
marketplace = json.loads(pathlib.Path(sys.argv[2]).read_text())
entries = marketplace["plugins"]
expected = {
    "brainstorm",
    "planning",
    "release-tools",
    "review",
    "skill-eval",
    "thinking-tools",
    "workflow",
}
expected_skills = {
    "brainstorm": {"brainstorm"},
    "planning": {"exec", "make", "plan-review"},
    "release-tools": {"last-tag", "new"},
    "review": {"git-review", "pr", "writing-style"},
    "skill-eval": {"skill-eval"},
    "thinking-tools": {"ask-codex", "dialectic", "root-cause-investigator"},
    "workflow": {"backlog", "clarify", "learn", "md-copy", "txt-copy", "wrong"},
}
component_pairs = {
    "plugins/brainstorm/skills/brainstorm/SKILL.md": "plugins/codex/brainstorm/skills/brainstorm/SKILL.md",
    "plugins/planning/agents/plan-review.md": "plugins/codex/planning/skills/plan-review/SKILL.md",
    "plugins/planning/commands/make.md": "plugins/codex/planning/skills/make/SKILL.md",
    "plugins/planning/skills/exec/SKILL.md": "plugins/codex/planning/skills/exec/SKILL.md",
    "plugins/release-tools/skills/last-tag/SKILL.md": "plugins/codex/release-tools/skills/last-tag/SKILL.md",
    "plugins/release-tools/skills/new/SKILL.md": "plugins/codex/release-tools/skills/new/SKILL.md",
    "plugins/review/skills/git-review/SKILL.md": "plugins/codex/review/skills/git-review/SKILL.md",
    "plugins/review/skills/pr/SKILL.md": "plugins/codex/review/skills/pr/SKILL.md",
    "plugins/review/skills/writing-style/SKILL.md": "plugins/codex/review/skills/writing-style/SKILL.md",
    "plugins/skill-eval/hooks/hooks.json": "plugins/codex/skill-eval/hooks/hooks.json",
    "plugins/thinking-tools/skills/ask-codex/SKILL.md": "plugins/codex/thinking-tools/skills/ask-codex/SKILL.md",
    "plugins/thinking-tools/skills/dialectic/SKILL.md": "plugins/codex/thinking-tools/skills/dialectic/SKILL.md",
    "plugins/thinking-tools/skills/root-cause-investigator/SKILL.md": "plugins/codex/thinking-tools/skills/root-cause-investigator/SKILL.md",
    "plugins/workflow/skills/backlog/SKILL.md": "plugins/codex/workflow/skills/backlog/SKILL.md",
    "plugins/workflow/skills/clarify/SKILL.md": "plugins/codex/workflow/skills/clarify/SKILL.md",
    "plugins/workflow/skills/learn/SKILL.md": "plugins/codex/workflow/skills/learn/SKILL.md",
    "plugins/workflow/skills/md-copy/SKILL.md": "plugins/codex/workflow/skills/md-copy/SKILL.md",
    "plugins/workflow/skills/txt-copy/SKILL.md": "plugins/codex/workflow/skills/txt-copy/SKILL.md",
    "plugins/workflow/skills/wrong/SKILL.md": "plugins/codex/workflow/skills/wrong/SKILL.md",
}
claude_only_components = {
    # Codex replaces these prompt and agent hook handlers with the mapped planning skills.
    "plugins/planning/hooks/hooks.json",
}
codex_only_components = {
    # Codex exposes the skill-eval hook instructions as both a trusted hook and a skill.
    "plugins/codex/skill-eval/skills/skill-eval/SKILL.md",
}


def is_component(path):
    return (
        path.name == "SKILL.md"
        or (path.parent.name in {"agents", "commands"} and path.suffix == ".md")
        or (path.parent.name == "hooks" and path.name == "hooks.json")
    )


claude_components = {
    path.relative_to(root).as_posix()
    for path in (root / "plugins").rglob("*")
    if path.is_file() and "plugins/codex/" not in path.as_posix() and is_component(path)
}
codex_components = {
    path.relative_to(root).as_posix()
    for path in (root / "plugins/codex").rglob("*")
    if path.is_file() and is_component(path)
}
assert claude_components == set(component_pairs) | claude_only_components, (
    f"Claude component parity classification differs: "
    f"unclassified={sorted(claude_components - set(component_pairs) - claude_only_components)}, "
    f"stale={sorted((set(component_pairs) | claude_only_components) - claude_components)}"
)
assert codex_components == set(component_pairs.values()) | codex_only_components, (
    f"Codex component parity classification differs: "
    f"unclassified={sorted(codex_components - set(component_pairs.values()) - codex_only_components)}, "
    f"stale={sorted((set(component_pairs.values()) | codex_only_components) - codex_components)}"
)

names = {entry["name"] for entry in entries}
assert names == expected, f"marketplace names differ: {sorted(names)}"
assert set(marketplace) == {"name", "interface", "plugins"}
assert isinstance(marketplace["name"], str) and marketplace["name"].strip()
assert set(marketplace["interface"]) == {"displayName"}
assert isinstance(marketplace["interface"]["displayName"], str)
assert marketplace["interface"]["displayName"].strip()

for entry in entries:
    name = entry["name"]
    assert set(entry) == {"name", "source", "policy", "category"}, f"{name}: invalid marketplace entry"
    assert set(entry["source"]) == {"source", "path"}, f"{name}: invalid marketplace source"
    assert set(entry["policy"]) <= {"installation", "authentication", "products"}, name
    assert isinstance(entry["category"], str) and entry["category"].strip(), name
    plugin_root = root / entry["source"]["path"]
    manifest = json.loads((plugin_root / ".codex-plugin/plugin.json").read_text())
    claude = json.loads((root / "plugins" / name / ".claude-plugin/plugin.json").read_text())
    assert manifest["name"] == name
    assert manifest["version"] == claude["version"], name
    assert manifest["skills"] == "./skills/"
    skills = {path.parent.name for path in (plugin_root / "skills").glob("*/SKILL.md")}
    assert skills == expected_skills[name], f"{name}: {sorted(skills)}"
    assert entry["source"]["source"] == "local"
    assert entry["policy"]["installation"] == "AVAILABLE"
    assert entry["policy"]["authentication"] == "ON_INSTALL"

copy_pairs = {
    "plugins/planning/skills/exec/scripts/append-progress.sh": "plugins/codex/planning/skills/exec/scripts/append-progress.sh",
    "plugins/planning/skills/exec/scripts/create-branch.sh": "plugins/codex/planning/skills/exec/scripts/create-branch.sh",
    "plugins/planning/skills/exec/scripts/detect-branch.sh": "plugins/codex/planning/skills/exec/scripts/detect-branch.sh",
    "plugins/planning/skills/exec/scripts/detect-vcs.sh": "plugins/codex/planning/skills/exec/scripts/detect-vcs.sh",
    "plugins/planning/skills/exec/scripts/init-progress.sh": "plugins/codex/planning/skills/exec/scripts/init-progress.sh",
    "plugins/planning/skills/exec/scripts/move-plan.sh": "plugins/codex/planning/skills/exec/scripts/move-plan.sh",
    "plugins/planning/skills/exec/scripts/stage-and-commit.sh": "plugins/codex/planning/skills/exec/scripts/stage-and-commit.sh",
    "plugins/release-tools/skills/new/scripts/calc-version.sh": "plugins/codex/release-tools/skills/new/scripts/calc-version.sh",
    "plugins/release-tools/skills/new/scripts/detect-platform.sh": "plugins/codex/release-tools/skills/new/scripts/detect-platform.sh",
    "plugins/release-tools/skills/new/scripts/get-notes.sh": "plugins/codex/release-tools/skills/new/scripts/get-notes.sh",
}

code_equivalent_pairs = {
    "plugins/planning/scripts/launch-plan-review.sh": "plugins/codex/planning/scripts/launch-plan-review.sh",
    "plugins/planning/scripts/plan-annotate.py": "plugins/codex/planning/scripts/plan-annotate.py",
    "plugins/review/skills/git-review/scripts/git-review.py": "plugins/codex/review/skills/git-review/scripts/git-review.py",
}

adapted_pairs = {
    "plugins/brainstorm/scripts/resolve-rules.sh": "plugins/codex/brainstorm/scripts/resolve-rules.sh",
    "plugins/planning/scripts/resolve-rules.sh": "plugins/codex/planning/scripts/resolve-rules.sh",
    "plugins/planning/skills/exec/scripts/customize-file.sh": "plugins/codex/planning/skills/exec/scripts/customize-file.sh",
    "plugins/planning/skills/exec/scripts/resolve-file.sh": "plugins/codex/planning/skills/exec/scripts/resolve-file.sh",
    "plugins/planning/skills/exec/scripts/run-codex.sh": "plugins/codex/planning/skills/exec/scripts/run-codex.sh",
    "plugins/planning/skills/exec/scripts/run-external-review.sh": "plugins/codex/planning/skills/exec/scripts/run-external-review.sh",
    "plugins/skill-eval/hooks/skill-forced-eval-hook.sh": "plugins/codex/skill-eval/hooks/skill-forced-eval-hook.sh",
}

claude_only_scripts = {
    "plugins/planning/scripts/plan-review-hook.py",
}
behaviour_checked_adaptations = {
    "plugins/codex/brainstorm/scripts/resolve-rules.sh",
    "plugins/codex/planning/scripts/resolve-rules.sh",
    "plugins/codex/planning/skills/exec/scripts/customize-file.sh",
    "plugins/codex/planning/skills/exec/scripts/resolve-file.sh",
    "plugins/codex/planning/skills/exec/scripts/run-codex.sh",
    "plugins/codex/planning/skills/exec/scripts/run-external-review.sh",
    "plugins/codex/skill-eval/hooks/skill-forced-eval-hook.sh",
}
classified_sources = set(copy_pairs) | set(code_equivalent_pairs) | set(adapted_pairs)
classified_codex = set(copy_pairs.values()) | set(code_equivalent_pairs.values()) | set(adapted_pairs.values())
claude_scripts = {
    path.relative_to(root).as_posix()
    for path in (root / "plugins").rglob("*")
    if path.suffix in {".py", ".sh"} and "plugins/codex/" not in path.as_posix()
}
codex_scripts = {
    path.relative_to(root).as_posix()
    for path in (root / "plugins/codex").rglob("*")
    if path.suffix in {".py", ".sh"}
}
assert claude_scripts == classified_sources | claude_only_scripts, (
    f"Claude script parity classification differs: unclassified={sorted(claude_scripts - classified_sources - claude_only_scripts)}, "
    f"stale={sorted((classified_sources | claude_only_scripts) - claude_scripts)}"
)
assert codex_scripts == classified_codex, (
    f"Codex script parity classification differs: unclassified={sorted(codex_scripts - classified_codex)}, "
    f"stale={sorted(classified_codex - codex_scripts)}"
)
assert behaviour_checked_adaptations == set(adapted_pairs.values())

for source_path, codex_path in {**copy_pairs, **code_equivalent_pairs, **adapted_pairs}.items():
    assert (root / source_path).is_file(), f"classified Claude script is missing: {source_path}"
    assert (root / codex_path).is_file(), f"classified Codex script is missing: {codex_path}"

for source_path, copy_path in copy_pairs.items():
    source = (root / source_path).read_bytes()
    copy = (root / copy_path).read_bytes()
    assert copy == source, f"Codex copy drifted from {source_path}: {copy_path}"

def python_code(path):
    source = path.read_text()
    first_line = source.splitlines()[0]
    tree = ast.parse(source, filename=str(path))
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if (
            isinstance(body, list)
            and body
            and isinstance(body[0], ast.Expr)
            and isinstance(body[0].value, ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            del body[0]
    return first_line, ast.dump(tree, include_attributes=False)


for source_path, codex_path in code_equivalent_pairs.items():
    source = root / source_path
    codex = root / codex_path
    if source.suffix == ".py":
        equal = python_code(source) == python_code(codex)
    else:
        source_text = source.read_text()
        old = '# empty stdout signals "no annotations", so the hook and /planning:make loop proceed.'
        new = '# empty stdout signals "no annotations", so the hook and planning:make loop proceed.'
        assert source_text.count(old) == 1, f"expected launch comment changed in {source_path}"
        equal = source_text.replace(old, new) == codex.read_text()
    assert equal, f"Codex script code drifted from {source_path}: {codex_path}"

planning_files = {
    "skills/exec/references/prompts/codex-review.md",
    "skills/exec/references/prompts/finalizer.md",
    "skills/exec/references/prompts/fixer.md",
    "skills/exec/references/prompts/progress-file.md",
    "skills/exec/references/prompts/review.md",
    "skills/exec/references/prompts/stats.md",
    "skills/exec/references/prompts/task.md",
}
planning_root = root / "plugins/codex/planning"
missing = sorted(path for path in planning_files if not (planning_root / path).is_file())
assert not missing, f"planning package is missing: {missing}"

exec_skill = (planning_root / "skills/exec/SKILL.md").read_text()
make_skill = (planning_root / "skills/make/SKILL.md").read_text()
external_review_prompt = (planning_root / "skills/exec/references/prompts/codex-review.md").read_text()
stats_prompt = (planning_root / "skills/exec/references/prompts/stats.md").read_text()
assert "later iterations as `git diff`" not in exec_skill, "committed fixer changes need a full-range re-review"
assert "Every iteration uses `DIFF_COMMAND` = `git diff DEFAULT_BRANCH...HEAD`" in external_review_prompt, (
    "external review prompt does not preserve committed fixer changes"
)
assert exec_skill.index("## Step 12: Complete terminal actions") < exec_skill.index(
    "## Step 13: Produce run summary"
), "run summary occurs before terminal completion actions"
assert "grep -E '\\[(decision|deviation)\\]'" in exec_skill, (
    "completion collector does not match timestamped decision markers"
)
assert "- Plan move: <outcome or n/a>" in stats_prompt, "run summary omits the plan-move outcome"
assert "- Progress file: PROGRESS_FILE_PATH" in stats_prompt, "run summary omits its progress file"
assert "Skip external review for Mercurial." in exec_skill, (
    "Mercurial is not excluded from the Git-only external-review loop"
)
assert "unless the user provided a Mercurial-native override" not in exec_skill, (
    "unsupported Mercurial external-review override is still advertised"
)
assert "If it exits 127 and stderr contains the script-owned `run-external-review:` marker" in exec_skill, (
    "tool-unavailable exit 127 is not distinguished from reviewer failure"
)
assert "Treat any other non-zero exit as reviewer failure" in exec_skill, (
    "unmarked or non-127 reviewer failures are not rejected"
)
assert "Both\nmay come only from the user-level file" in exec_skill, (
    "project configuration can select an executable or plan path"
)
assert "`external_review_iterations`, and `finalize_enabled`." in exec_skill, (
    "project configuration can override an untrusted key"
)
assert "`task_retries` from 0 through 3" in exec_skill, "task retries have no upper bound"
assert "`review_iterations` and `external_review_iterations` from 0 through 10" in exec_skill, (
    "review iterations have no upper bound"
)
implementation_modes = make_skill.rsplit("- **Implement**:", 1)[1].split("- **Done**:", 1)[0]
assert implementation_modes.count("- **Interactive**:") == 1, "duplicate Interactive implementation mode"
assert implementation_modes.count("- **Autonomous**:") == 1, "duplicate Autonomous implementation mode"

hook_root = root / "plugins/codex/skill-eval/hooks"
hook = json.loads((hook_root / "hooks.json").read_text())
command = hook["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"]
assert command == "sh ${PLUGIN_ROOT}/hooks/skill-forced-eval-hook.sh"
hook_script = hook_root / "skill-forced-eval-hook.sh"
assert hook_script.is_file()
assert os.stat(hook_script).st_mode & 0o111, "skill-eval hook is not executable"
PY

if grep -RInE \
    'CLAUDE_PLUGIN|AskUserQuestion|EnterPlanMode|EnterWorktree|TodoWrite|Bash tool|subagent_type|\$\{user_config|allowed-tools:' \
    "$CODEX_ROOT" --exclude-dir='hooks' --include='*.md' --include='*.txt' --include='*.sh' --include='*.py'; then
    echo "Codex package contains a Claude-only runtime instruction" >&2
    exit 1
fi

WORK_DIR="$TMP_ROOT/work"
CODEX_HOME="$TMP_ROOT/codex-home"
mkdir -p "$WORK_DIR/.codex" "$CODEX_HOME/cc-thingz/brainstorm" "$CODEX_HOME/cc-thingz/planning/exec-plan/prompts"

printf 'user brainstorm\n' >"$CODEX_HOME/cc-thingz/brainstorm/test-rules.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/brainstorm/scripts/resolve-rules.sh" test-rules.md)"
test "$actual" = "user brainstorm"

printf 'project brainstorm\n' >"$WORK_DIR/.codex/test-rules.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/brainstorm/scripts/resolve-rules.sh" test-rules.md)"
test "$actual" = "project brainstorm"

mkdir -p "$CODEX_HOME/cc-thingz/planning"
printf 'user planning\n' >"$CODEX_HOME/cc-thingz/planning/planning-rules.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/scripts/resolve-rules.sh" planning-rules.md)"
test "$actual" = "user planning"

printf 'project planning\n' >"$WORK_DIR/.codex/planning-rules.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/scripts/resolve-rules.sh" planning-rules.md)"
test "$actual" = "project planning"

printf 'user task prompt\n' >"$CODEX_HOME/cc-thingz/planning/exec-plan/prompts/task.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/resolve-file.sh" prompts/task.md)"
test "$actual" = "user task prompt"

mkdir -p "$WORK_DIR/.codex/exec-plan/prompts"
printf 'project task prompt\n' >"$WORK_DIR/.codex/exec-plan/prompts/task.md"
actual="$(cd "$WORK_DIR" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/resolve-file.sh" prompts/task.md)"
test "$actual" = "project task prompt"

SYMLINK_WORK="$TMP_ROOT/symlink-work"
OUTSIDE_FILE="$TMP_ROOT/outside-secret"
mkdir -p "$SYMLINK_WORK/.codex/exec-plan/prompts"
printf 'outside secret\n' >"$OUTSIDE_FILE"
ln -s "$OUTSIDE_FILE" "$SYMLINK_WORK/.codex/brainstorm-rules.md"
ln -s "$OUTSIDE_FILE" "$SYMLINK_WORK/.codex/planning-rules.md"
ln -s "$OUTSIDE_FILE" "$SYMLINK_WORK/.codex/exec-plan/prompts/task.md"

set +e
actual="$(cd "$SYMLINK_WORK" && CODEX_HOME="$CODEX_HOME" \
    bash "$CODEX_ROOT/brainstorm/scripts/resolve-rules.sh" brainstorm-rules.md 2>"$TMP_ROOT/brainstorm-symlink.err")"
brainstorm_symlink_rc=$?
set -e
test "$brainstorm_symlink_rc" -ne 0
test -z "$actual"
grep -Fq "refusing project rules outside working directory" "$TMP_ROOT/brainstorm-symlink.err"

set +e
actual="$(cd "$SYMLINK_WORK" && CODEX_HOME="$CODEX_HOME" \
    bash "$CODEX_ROOT/planning/scripts/resolve-rules.sh" planning-rules.md 2>"$TMP_ROOT/planning-symlink.err")"
planning_symlink_rc=$?
set -e
test "$planning_symlink_rc" -ne 0
test -z "$actual"
grep -Fq "refusing project rules outside working directory" "$TMP_ROOT/planning-symlink.err"

set +e
actual="$(cd "$SYMLINK_WORK" && CODEX_HOME="$CODEX_HOME" \
    bash "$CODEX_ROOT/planning/skills/exec/scripts/resolve-file.sh" prompts/task.md \
    2>"$TMP_ROOT/prompt-symlink.err")"
prompt_symlink_rc=$?
set -e
test "$prompt_symlink_rc" -ne 0
test -z "$actual"
grep -Fq "refusing project override outside working directory" "$TMP_ROOT/prompt-symlink.err"

PROGRESS_FILE="$TMP_ROOT/progress.log"
bash "$CODEX_ROOT/planning/skills/exec/scripts/append-progress.sh" \
    "$PROGRESS_FILE" "[decision] task 1: use the smaller option"
bash "$CODEX_ROOT/planning/skills/exec/scripts/append-progress.sh" \
    "$PROGRESS_FILE" "[deviation] task 1: skipped unavailable deployment"
decision_lines="$(grep -E '\[(decision|deviation)\]' "$PROGRESS_FILE")"
case "$decision_lines" in
    *"[decision] task 1: use the smaller option"*"[deviation] task 1: skipped unavailable deployment"*) ;;
    *) echo "completion collector missed timestamped decision markers" >&2; exit 1 ;;
esac

CUSTOM_WORK="$TMP_ROOT/custom-work"
mkdir -p "$CUSTOM_WORK"
actual="$(cd "$CUSTOM_WORK" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/customize-file.sh" prompts/review.md)"
test "$actual" = ".codex/exec-plan/prompts/review.md"
cmp "$CUSTOM_WORK/$actual" "$CODEX_ROOT/planning/skills/exec/references/prompts/review.md"

actual="$(cd "$CUSTOM_WORK" && CODEX_HOME="$CODEX_HOME" bash "$CODEX_ROOT/planning/skills/exec/scripts/customize-file.sh" agents/quality.txt --user)"
test "$actual" = "$CODEX_HOME/cc-thingz/planning/exec-plan/agents/quality.txt"
cmp "$actual" "$CODEX_ROOT/planning/skills/exec/references/agents/quality.txt"

FAKE_BIN="$TMP_ROOT/fake-bin"
CAPTURE="$TMP_ROOT/args"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/codex" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$CAPTURE"
EOF
chmod +x "$FAKE_BIN/codex"

CAPTURE="$CAPTURE" PATH="$FAKE_BIN:$PATH" CODEX_MODEL="review-model" \
    bash "$CODEX_ROOT/planning/skills/exec/scripts/run-codex.sh" "review prompt"
cat >"$TMP_ROOT/expected-args" <<'EOF'
exec
--sandbox
read-only
-c
model_reasoning_effort=xhigh
-c
stream_idle_timeout_ms=3600000
-c
model=review-model
review prompt
EOF
cmp "$CAPTURE" "$TMP_ROOT/expected-args"

CAPTURE="$CAPTURE" PATH="$FAKE_BIN:$PATH" CODEX_MODEL="" \
    bash "$CODEX_ROOT/planning/skills/exec/scripts/run-codex.sh" "default prompt"
cat >"$TMP_ROOT/expected-args" <<'EOF'
exec
--sandbox
read-only
-c
model_reasoning_effort=xhigh
-c
stream_idle_timeout_ms=3600000
default prompt
EOF
cmp "$CAPTURE" "$TMP_ROOT/expected-args"

CAPTURE="$CAPTURE" PATH="$FAKE_BIN:$PATH" CODEX_NO_OVERRIDES=1 \
    bash "$CODEX_ROOT/planning/skills/exec/scripts/run-codex.sh" "proxy prompt"
cat >"$TMP_ROOT/expected-args" <<'EOF'
exec
--sandbox
read-only
proxy prompt
EOF
cmp "$CAPTURE" "$TMP_ROOT/expected-args"

cat >"$FAKE_BIN/reviewer" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$CAPTURE"
EOF
chmod +x "$FAKE_BIN/reviewer"
CAPTURE="$CAPTURE" PATH="$FAKE_BIN:$PATH" \
    bash "$CODEX_ROOT/planning/skills/exec/scripts/run-external-review.sh" "reviewer --strict" "external prompt"
printf '%s\n' '--strict' 'external prompt' >"$TMP_ROOT/expected-args"
cmp "$CAPTURE" "$TMP_ROOT/expected-args"

set +e
CAPTURE="$CAPTURE" PATH="$FAKE_BIN:$PATH" \
    bash "$CODEX_ROOT/planning/skills/exec/scripts/run-external-review.sh" \
    '${user_config.external_review_cmd}' "external prompt" >"$TMP_ROOT/token.out" 2>"$TMP_ROOT/token.err"
token_rc=$?
set -e
test "$token_rc" -eq 127
grep -Fq "error: run-external-review: external_review_cmd not on PATH: \${user_config.external_review_cmd}" \
    "$TMP_ROOT/token.err"

NO_CODEX_BIN="$TMP_ROOT/no-codex-bin"
mkdir -p "$NO_CODEX_BIN"
ln -s "$(command -v dirname)" "$NO_CODEX_BIN/dirname"
set +e
PATH="$NO_CODEX_BIN" /bin/bash "$CODEX_ROOT/planning/skills/exec/scripts/run-external-review.sh" \
    "" "external prompt" >"$TMP_ROOT/no-codex.out" 2>"$TMP_ROOT/no-codex.err"
no_codex_rc=$?
set -e
test "$no_codex_rc" -eq 127
test ! -s "$TMP_ROOT/no-codex.out"
grep -Fq "error: run-external-review: codex not on PATH and external_review_cmd is not set" \
    "$TMP_ROOT/no-codex.err"

cat >"$FAKE_BIN/reviewer-127" <<'EOF'
#!/bin/sh
exit 127
EOF
cat >"$FAKE_BIN/reviewer-3" <<'EOF'
#!/bin/sh
exit 3
EOF
chmod +x "$FAKE_BIN/reviewer-127" "$FAKE_BIN/reviewer-3"

set +e
PATH="$FAKE_BIN:$PATH" bash "$CODEX_ROOT/planning/skills/exec/scripts/run-external-review.sh" \
    "reviewer-127" "external prompt" >"$TMP_ROOT/reviewer-127.out" 2>"$TMP_ROOT/reviewer-127.err"
reviewer_127_rc=$?
PATH="$FAKE_BIN:$PATH" bash "$CODEX_ROOT/planning/skills/exec/scripts/run-external-review.sh" \
    "reviewer-3" "external prompt" >"$TMP_ROOT/reviewer-3.out" 2>"$TMP_ROOT/reviewer-3.err"
reviewer_3_rc=$?
set -e
test "$reviewer_127_rc" -eq 127
test "$reviewer_3_rc" -eq 3
test ! -s "$TMP_ROOT/reviewer-127.out"
test ! -s "$TMP_ROOT/reviewer-127.err"
test ! -s "$TMP_ROOT/reviewer-3.out"
test ! -s "$TMP_ROOT/reviewer-3.err"

hook_output="$(sh "$CODEX_ROOT/skill-eval/hooks/skill-forced-eval-hook.sh")"
case "$hook_output" in
    *"MANDATORY SKILL EVALUATION"*"Read each selected SKILL.md completely"*) ;;
    *) echo "Codex skill-eval hook output is incomplete" >&2; exit 1 ;;
esac
case "$hook_output" in
    *Claude*|*'Skill('*) echo "Codex skill-eval hook contains Claude-only instructions" >&2; exit 1 ;;
esac

echo "Codex package tests passed"
