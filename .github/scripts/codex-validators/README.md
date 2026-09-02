# Codex validators

These scripts are vendored from the OpenAI Codex `plugin-creator` and `skill-creator` system skills
shipped with Codex CLI 0.152.0. They validate plugin manifests, skill frontmatter and instructions,
and optional skill agent metadata in CI. Their Apache 2.0 licence is included in this directory.

Update the validator files and licence together when adopting a newer Codex validation contract.
Keep the Python files byte-identical to their pinned upstream copies. Under this contract, hooks are
discovered from `hooks/hooks.json`; a manifest-level `hooks` field is rejected by the validator.
