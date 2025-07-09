# Aerospace Migration Guide

## Overview

This sketchybar configuration has been successfully migrated from yabai to aerospace window management. The migration provides basic workspace management with aerospace integration.

## Key Changes

### 1. Window Management System
- **Before**: Used yabai for space management
- **After**: Uses aerospace for workspace management

### 2. Workspace Display
- **Before**: Static spaces with predefined icons (ghosts)
- **After**: Dynamic workspaces that show pacman for active workspace and ghosts for inactive

### 3. Space Switching
- **Before**: `yabai -m space --focus <space_id>`
- **After**: `aerospace workspace <workspace_id>`

### 4. Features
- Dynamic workspace creation based on aerospace workspaces
- Visual indication of active workspace (pacman icon)
- Click to switch workspaces
- Current workspace display

## Modified Files

### sketchybarrc
- Replaced yabai commands with aerospace commands
- Added dynamic workspace creation based on `aerospace list-workspaces --all`
- Simplified space management without complex app icons
- Integrated aerospace workspace switching

### environment.sh
- Removed static space configuration
- Removed yabai-specific app sorting configuration

### plugins/sort.sh
- Updated to work with aerospace window management
- Simplified sorting functionality

### plugins/space.sh
- Simplified to update workspace icons based on focused workspace
- Uses pacman icon for active workspace, ghost for inactive

### plugins/current_space.sh
- Shows current focused workspace number

## Aerospace Commands Used

```bash
# List all workspaces
aerospace list-workspaces --all

# Get focused workspace
aerospace list-workspaces --focused

# Switch to workspace
aerospace workspace <workspace_id>
```

## Usage

### Basic Workspace Management
- Click on workspace numbers to switch to that workspace
- Active workspace shows pacman icon
- Inactive workspaces show ghost icons
- Current workspace number is displayed in the current_space item

### Workspace Creation
- Aerospace automatically creates workspaces as needed
- No manual workspace configuration required

## Configuration

### Customizing Workspace Appearance
Modify the space configuration in `sketchybarrc`:

```bash
space=(
  script="$PLUGIN_DIR/space.sh"
  label.drawing=off
  icon.padding_left=16
  icon.padding_right=16
  update_freq=1
)
```

### Changing Icons
Modify the icons in `plugins/space.sh`:

```bash
# Active workspace icon
sketchybar --set space.$i icon="$PACMAN"

# Inactive workspace icon  
sketchybar --set space.$i icon="$GHOST"
```

## Troubleshooting

### Aerospace Not Found
Ensure aerospace is installed and running:
```bash
aerospace --version
```

### Workspace Not Updating
Check aerospace workspace status:
```bash
aerospace list-workspaces --focused
```

### Sketchybar Not Starting
Check for configuration errors:
```bash
sketchybar --config ~/.config/sketchybar/sketchybarrc
```

## Benefits of Aerospace Integration

1. **Dynamic Workspaces**: No need to pre-configure spaces
2. **Simple Management**: Easy workspace switching with aerospace commands
3. **Visual Feedback**: Clear indication of active workspace
4. **Modern Architecture**: Uses aerospace's modern window management

## Migration Notes

- The old yabai-based `plugins/spaces.sh` has been removed
- Static space configuration in `environment.sh` is no longer needed
- App sorting functionality has been simplified
- All workspace management is now handled by aerospace
- Complex app icon integration was removed for stability

## Current Status

✅ **Working**: Basic aerospace workspace management
✅ **Working**: Workspace switching via click
✅ **Working**: Visual indication of active workspace
✅ **Working**: Current workspace display

The configuration is now stable and functional with aerospace window management.
