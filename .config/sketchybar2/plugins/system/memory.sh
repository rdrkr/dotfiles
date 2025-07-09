#!/bin/sh

# Memory usage monitoring
# Gets memory usage percentage

# Source current theme
source "$HOME/.config/sketchybar/config/source_theme.sh"

# Get memory info using vm_stat
VM_STAT=$(vm_stat)
PAGE_SIZE=$(vm_stat | head -1 | awk '{print $8}')

# Extract memory values (in pages)
PAGES_FREE=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
PAGES_ACTIVE=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
PAGES_INACTIVE=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
PAGES_SPECULATIVE=$(echo "$VM_STAT" | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//')
PAGES_WIRED=$(echo "$VM_STAT" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')

# Calculate total memory
TOTAL_PAGES=$((PAGES_FREE + PAGES_ACTIVE + PAGES_INACTIVE + PAGES_SPECULATIVE + PAGES_WIRED))
USED_PAGES=$((PAGES_ACTIVE + PAGES_INACTIVE + PAGES_SPECULATIVE + PAGES_WIRED))

# Calculate percentage
if [ "$TOTAL_PAGES" -gt 0 ]; then
    MEMORY_USAGE=$(echo "scale=1; $USED_PAGES * 100 / $TOTAL_PAGES" | bc)
    MEMORY_INT=$(echo "$MEMORY_USAGE" | cut -d. -f1)
else
    exit 0
fi

# Set color based on usage using new semantic colors
if [ "$MEMORY_INT" -ge 85 ]; then
  COLOR=$STATE_ERROR     # High memory usage - red
elif [ "$MEMORY_INT" -ge 70 ]; then
  COLOR=$STATE_WARNING   # Medium-high memory usage - orange
elif [ "$MEMORY_INT" -ge 50 ]; then
  COLOR=$STATE_CAUTION          # Medium memory usage
else
  COLOR=$INTERACTIVE_PRIMARY    # Low memory usage - accent blue
fi

# Update the item
sketchybar --set "$NAME" label="${MEMORY_USAGE}%" label.color="$COLOR"
