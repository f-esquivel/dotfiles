#!/bin/bash
# Pre-tool hook: validate git commit messages against project commitlint config
# Falls back to basic conventional commit regex if no commitlint found
# Exit 0 = allow, Exit 2 = block with message

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only intercept git commit commands
if ! echo "$COMMAND" | grep -qE '^git commit\b'; then
  exit 0
fi

# Extract commit message from -m flag (macOS-compatible)
MSG=$(echo "$COMMAND" | sed -nE 's/.*-m[[:space:]]+"([^"]+)".*/\1/p')
if [ -z "$MSG" ]; then
  MSG=$(echo "$COMMAND" | sed -nE "s/.*-m[[:space:]]+'([^']+)'.*/\1/p")
fi
# Handle heredoc pattern: -m "$(cat <<'EOF' ... EOF )"
if [ -z "$MSG" ]; then
  MSG=$(echo "$COMMAND" | sed -nE 's/.*-m[[:space:]]+"\$\(cat <<.*//p')
fi

# If no message extracted (amend without -m, heredoc, etc.), allow through
if [ -z "$MSG" ]; then
  exit 0
fi

# Resolve project directory from hook context or PWD
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Strategy 1: Use project's commitlint if available
if [ -f "$PROJECT_DIR/node_modules/.bin/commitlint" ]; then
  # Use the project's commitlint with its own config
  RESULT=$(echo "$MSG" | "$PROJECT_DIR/node_modules/.bin/commitlint" 2>&1)
  STATUS=$?
  if [ $STATUS -ne 0 ]; then
    echo "BLOCKED by project commitlint:" >&2
    echo "$RESULT" >&2
    exit 2
  fi
  exit 0
fi

# Strategy 2: Check for global commitlint
if command -v commitlint &>/dev/null; then
  RESULT=$(cd "$PROJECT_DIR" && echo "$MSG" | commitlint 2>&1)
  STATUS=$?
  if [ $STATUS -ne 0 ]; then
    echo "BLOCKED by commitlint:" >&2
    echo "$RESULT" >&2
    exit 2
  fi
  exit 0
fi

# Strategy 3: Fallback — basic conventional commit regex
PATTERN='^(feat|fix|hotfix|refactor|perf|style|docs|test|build|ci|dx|deps|security|chore)(\(.+\))?(!)?: .+'

if ! echo "$MSG" | grep -qE "$PATTERN"; then
  echo "BLOCKED: Commit message doesn't follow conventional commits format." >&2
  echo "Expected: type(scope): description" >&2
  echo "Example: feat(auth): add magic link support" >&2
  echo "(no commitlint config found in project, using default rules)" >&2
  exit 2
fi

# Check lowercase after colon
DESC=$(echo "$MSG" | sed -E 's/^[^:]+: //')
FIRST_CHAR=$(echo "$DESC" | cut -c1)
if echo "$FIRST_CHAR" | grep -qE '^[A-Z]'; then
  echo "BLOCKED: Description after colon must start with lowercase." >&2
  echo "Got: $MSG" >&2
  exit 2
fi

exit 0
