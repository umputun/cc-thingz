---
name: txt-copy
description: Copy generated text content to clipboard. Use when user asks to "copy this", "copy to clipboard", "save to clipboard", or after creating emails, messages, letters, or other text content that needs to be shared.
allowed-tools: Bash
---

# Copy Text to Clipboard

Copy generated text content to clipboard via a timestamped temp file.

## Activation Triggers

- "copy this", "copy to clipboard", "save to clipboard"
- "copy the email", "copy the message", "copy the letter"
- After generating text content when user indicates they want to use it
- "I need to paste this", "put it in clipboard"

## Workflow

1. Identify the text content to copy (from recent generation or user-specified)

2. Write to timestamped temp file:
```bash
tmpfile="/tmp/claude-txt-copy-$(date +%s).txt"
cat > "$tmpfile" << 'EOF'
<content here>
EOF
```

3. Copy to clipboard and remove temp file:
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

4. Confirm to user: "Copied to clipboard (N characters)"

## Notes

- Use `cat` with heredoc and single-quoted EOF to preserve exact content
- Temp file uses timestamp to avoid collisions across invocations
- Temp file is removed after clipboard copy
