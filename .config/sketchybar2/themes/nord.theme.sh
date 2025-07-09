#!/usr/bin/env sh

# Nord Theme - Semantic Version
# Industry-standard semantic naming with Nord color values

#===============================================================================
# SURFACE COLORS (backgrounds, cards, overlays)
#===============================================================================

export SURFACE_BASE=0xff2e3440            # Main app background (Nord polar-night-0)
export SURFACE_CONTAINER_PRIMARY=0x903b4252    # Primary section backgrounds (Nord polar-night-1)
export SURFACE_CONTAINER_SECONDARY=0x90434c5e  # Secondary section backgrounds (Nord polar-night-2)
export SURFACE_OVERLAY=0xff242933         # Modal/popup backgrounds (Nord darker)
export SURFACE_ELEVATED=0xff3b4252        # Raised card backgrounds (Nord polar-night-1)

#===============================================================================
# CONTENT COLORS (text, icons)
#===============================================================================

export CONTENT_PRIMARY=0xffeceff4         # Main content text and icons (Nord snow-storm-2)
export CONTENT_SECONDARY=0xffe5e9f0       # Supporting content (Nord snow-storm-1)
export CONTENT_TERTIARY=0xff81a1c1        # Subtle/disabled content (Nord frost-3)
export CONTENT_INVERSE=0xff2e3440         # Content on colored backgrounds (Nord polar-night-0)
export CONTENT_DISABLED=0xff81a1c1        # Disabled content state (Nord frost-3)

#===============================================================================
# INTERACTIVE COLORS (buttons, links, controls)
#===============================================================================

export INTERACTIVE_PRIMARY=0xff5e81ac     # Primary brand actions and focus (Nord frost-0)
export INTERACTIVE_SECONDARY=0xffb48ead   # Secondary actions (Nord aurora-4)
export INTERACTIVE_SELECTED=0xffeceff4    # Selected/active items (Nord snow-storm-2)

export INTERACTIVE_HOVER=0x60eceff4       # Hover states (Nord snow-storm-2 with transparency)
export INTERACTIVE_ACTIVE=0x805e81ac      # Pressed states (Nord frost-0 with transparency)
export INTERACTIVE_DISABLED=0x4081a1c1    # Disabled states (Nord frost-3)
export INTERACTIVE_FOCUS=0xff5e81ac       # Focus outlines (Nord frost-0)

#===============================================================================
# STATE COLORS (alerts, status, semantic states)
#===============================================================================

export STATE_SUCCESS=0xffa3be8c          # Success states (Nord aurora-2)
export STATE_WARNING=0xffebcb8b          # Warning states (Nord aurora-1)
export STATE_CAUTION=0xffebcb8b          # Medium warning level (Nord aurora-1)
export STATE_ERROR=0xffbf616a            # Error states (Nord aurora-0)
export STATE_INFO=0xff88c0d0             # Informational states (Nord frost-1)

#===============================================================================
# BORDER COLORS (dividers, outlines)
#===============================================================================

export BORDER_PRIMARY=0xff81a1c1          # Main borders (Nord frost-3)
export BORDER_SECONDARY=0xff4c566a        # Subtle borders (Nord polar-night-3)
export BORDER_FOCUS=0xff5e81ac            # Focus outlines (Nord frost-0)
export BORDER_DIVIDER=0xff434c5e          # Section separators (Nord polar-night-2)

#===============================================================================
# SPECIALIZED SYSTEM COLORS
#===============================================================================

# Workspace states (specific semantic meanings)
export WORKSPACE_FOCUSED=0x995e81ac       # Currently focused workspace with focused app (semi-transparent frost-0)
export WORKSPACE_ACTIVE=$INTERACTIVE_HOVER # Active workspace (current but no focused app)
export WORKSPACE_UNFOCUSED=$CONTENT_TERTIARY # Inactive workspaces
export WORKSPACE_OCCUPIED=$STATE_SUCCESS   # Workspaces with windows
export WORKSPACE_EMPTY=$CONTENT_TERTIARY   # Empty workspaces

# Segment backgrounds (for visual grouping)
export SEGMENT_PRIMARY=$SURFACE_CONTAINER_PRIMARY    # Primary segments
export SEGMENT_SECONDARY=$SURFACE_CONTAINER_SECONDARY # Secondary segments

#===============================================================================
# TYPOGRAPHY (fonts and text styling)
#===============================================================================

export FONT_FAMILY_PRIMARY="MesloLGS Nerd Font"        # Main UI font
export FONT_FAMILY_ICONS="sketchybar-app-font"         # App icon font with ligatures
export FONT_FAMILY_SYSTEM="SF Pro"                     # System font for special cases

export FONT_SIZE_SMALL=11                              # Small text
export FONT_SIZE_MEDIUM=13                             # Regular text  
export FONT_SIZE_LARGE=16                              # Large text/icons

# Main font variable used in sketchybar config
export FONT="$FONT_FAMILY_PRIMARY"                     # Default font for sketchybar

#===============================================================================
# SKETCHYBAR MAPPINGS
#===============================================================================

# Essential SketchyBar mappings
export TRANSPARENT=0x00000000            # Transparent background for main bar
export POPUP_BACKGROUND_COLOR=$SURFACE_OVERLAY
export POPUP_SHADOW_COLOR=0x60000000
