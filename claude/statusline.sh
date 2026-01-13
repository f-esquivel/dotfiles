#!/bin/bash
# Claude Code status line script
# Displays: [Model] directory | branch (workspace) | ctx: N% | $X.XX

input=$(cat)

# ANSI colors
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
ORANGE="\033[38;5;208m"
BLUE="\033[38;5;75m"
GREEN="\033[38;5;114m"
CYAN="\033[38;5;80m"
YELLOW="\033[38;5;221m"
RED="\033[38;5;203m"
GRAY="\033[38;5;245m"

# Parse JSON input
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // empty')
DIR_NAME="${CURRENT_DIR##*/}"

# Git info (if in a repo)
BRANCH=""
WORKSPACE=""
if [ -n "$CURRENT_DIR" ]; then
    BRANCH=$(git -C "$CURRENT_DIR" branch --show-current 2>/dev/null)
    GIT_EMAIL=$(git -C "$CURRENT_DIR" config user.email 2>/dev/null)
    # Map email domain to workspace name
    case "$GIT_EMAIL" in
        *@outlook.com) WORKSPACE="personal" ;;
        *@ese.plus) WORKSPACE="ese" ;;
        *@designli.co) WORKSPACE="designli" ;;
    esac
fi

# Context window usage
CTX_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
USAGE=$(echo "$input" | jq '.context_window.current_usage // null')
PCT=0
if [ "$USAGE" != "null" ] && [ "$CTX_SIZE" -gt 0 ]; then
    INPUT_TOKENS=$(echo "$USAGE" | jq -r '.input_tokens // 0')
    CACHE_CREATE=$(echo "$USAGE" | jq -r '.cache_creation_input_tokens // 0')
    CACHE_READ=$(echo "$USAGE" | jq -r '.cache_read_input_tokens // 0')
    TOKENS=$((INPUT_TOKENS + CACHE_CREATE + CACHE_READ))
    PCT=$((TOKENS * 100 / CTX_SIZE))
fi

# Context color based on usage
if [ "$PCT" -lt 50 ]; then
    CTX_COLOR="$GREEN"
elif [ "$PCT" -lt 75 ]; then
    CTX_COLOR="$YELLOW"
else
    CTX_COLOR="$RED"
fi

# Cost tracking
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
if [ "$COST" != "0" ] && [ "$COST" != "null" ]; then
    COST_FMT=$(printf "%.2f" "$COST")
else
    COST_FMT=""
fi

# Build status line
STATUS="${BOLD}${ORANGE}[${MODEL}]${RESET}"
[ -n "$DIR_NAME" ] && STATUS="$STATUS ${BLUE}${DIR_NAME}${RESET}"
[ -n "$BRANCH" ] && STATUS="$STATUS ${GRAY}|${RESET} ${GREEN}${BRANCH}${RESET}"
[ -n "$WORKSPACE" ] && STATUS="$STATUS ${DIM}(${WORKSPACE})${RESET}"
STATUS="$STATUS ${GRAY}|${RESET} ${CTX_COLOR}ctx: ${PCT}%${RESET}"
[ -n "$COST_FMT" ] && STATUS="$STATUS ${GRAY}|${RESET} ${CYAN}\$${COST_FMT}${RESET}"

echo -e "$STATUS"
