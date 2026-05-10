#!/bin/bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "block-dangerous-git: 'jq' is required but not installed." >&2
  echo "Install with 'brew install jq' (macOS) or 'apt-get install jq' (Debian/Ubuntu)." >&2
  exit 1
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

DANGEROUS_PATTERNS=(
  "(^|[[:space:]&|;])git[[:space:]]+push([[:space:]]|$)"
  "(^|[[:space:]&|;])git[[:space:]]+reset[[:space:]]+--hard"
  "(^|[[:space:]&|;])git[[:space:]]+clean[[:space:]]+-f"
  "(^|[[:space:]&|;])git[[:space:]]+branch[[:space:]]+-D"
  "(^|[[:space:]&|;])git[[:space:]]+checkout[[:space:]]+\\."
  "(^|[[:space:]&|;])git[[:space:]]+restore[[:space:]]+\\."
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    echo "BLOCKED: '$COMMAND' matches dangerous pattern '$pattern'. The user has prevented you from doing this." >&2
    exit 2
  fi
done

exit 0
