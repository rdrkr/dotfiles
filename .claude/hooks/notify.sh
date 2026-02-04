#!/bin/bash
title="$1"
default_body="${2:-Finished}"

# Read input from stdin
input=$(cat)

# Try to extract 'reason' from JSON input
if [ -n "$input" ]; then
  reason=$(echo "$input" | /opt/homebrew/bin/jq -r '.reason // empty' 2>/dev/null)
fi

if [ -n "$reason" ]; then
  body="$reason"
else
  body="$default_body"
fi

osascript -e "display notification \"${body}\" with title \"${title}\" sound name \"Submarine\""
