---
name: md-copy
description: Format final answer as markdown and copy to clipboard. Use when user says "copy as markdown", "md copy", "copy formatted", "clipboard", or wants the session's final answer formatted and copied.
allowed-tools: Bash
---

# Markdown Copy

Extract the final answer from this session, convert it to proper markdown format, and copy to clipboard.

## Formatting Rules

1. **No heading elements** (`#`, `##`, etc.) — use **bold** for section titles instead
2. Convert any ASCII tables to proper markdown tables
3. Use *italic* for emphasis and minor notes
4. Preserve code blocks with proper language tags
5. Keep bullet lists and numbered lists
6. Remove any leading spaces or bullet headers (bullet-style)
7. Give the content a nice descriptive title (as bold text, not heading)

## Workflow

1. Identify the final answer/response in this session
2. Format it according to the rules above
3. Write formatted text to a timestamped temp file:
```bash
tmpfile="/tmp/claude-md-copy-$(date +%s).txt"
cat > "$tmpfile" << 'EOF'
<formatted content>
EOF
```
4. Copy to clipboard and remove temp file:
```bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    pbcopy < "$tmpfile"
elif command -v xclip &> /dev/null; then
    xclip -selection clipboard < "$tmpfile"
elif command -v xsel &> /dev/null; then
    xsel --clipboard --input < "$tmpfile"
else
    echo "No clipboard tool found" >&2
fi
rm -f "$tmpfile"
```
5. Report success with character count
