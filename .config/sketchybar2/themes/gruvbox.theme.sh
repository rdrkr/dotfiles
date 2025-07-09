#!/usr/bin/env sh

# Gruvbox Theme - Semantic Version
# Industry-standard semantic naming with Gruvbox color values

#===============================================================================
# SURFACE COLORS (backgrounds, cards, overlays)
#===============================================================================

export SURFACE_BASE=0xff282828            # Main app background (Gruvbox dark0_hard)
export SURFACE_CONTAINER_PRIMARY=0x903c3836    # Primary section backgrounds (Gruvbox dark1)
export SURFACE_CONTAINER_SECONDARY=0x90504945  # Secondary section backgrounds (Gruvbox dark2)
export SURFACE_OVERLAY=0xff1d2021         # Modal/popup backgrounds (Gruvbox bg0_h)
export SURFACE_ELEVATED=0xff3c3836        # Raised card backgrounds (Gruvbox dark1)

#===============================================================================
# CONTENT COLORS (text, icons)
#===============================================================================

export CONTENT_PRIMARY=0xffebdbb2         # Main content text and icons (Gruvbox light0)
export CONTENT_SECONDARY=0xffd5c4a1       # Supporting content (Gruvbox light1)
export CONTENT_TERTIARY=0xffa89984        # Subtle/disabled content (Gruvbox gray)
export CONTENT_INVERSE=0xff282828         # Content on colored backgrounds (Gruvbox dark0_hard)
export CONTENT_DISABLED=0xffa89984        # Disabled content state (Gruvbox gray)

#===============================================================================
# INTERACTIVE COLORS (buttons, links, controls)
#===============================================================================

export INTERACTIVE_PRIMARY=0xff83a598     # Primary brand actions and focus (Gruvbox aqua)
export INTERACTIVE_SECONDARY=0xffd3869b   # Secondary actions (Gruvbox purple)
export INTERACTIVE_SELECTED=0xffebdbb2    # Selected/active items (Gruvbox light0)

export INTERACTIVE_HOVER=0x60ebdbb2       # Hover states (Gruvbox light0 with transparency)
export INTERACTIVE_ACTIVE=0x8083a598      # Pressed states (Gruvbox aqua with transparency)
export INTERACTIVE_DISABLED=0x40a89984    # Disabled states (Gruvbox gray)
export INTERACTIVE_FOCUS=0xff83a598       # Focus outlines (Gruvbox aqua)

#===============================================================================
# STATE COLORS (alerts, status, semantic states)
#===============================================================================

export STATE_SUCCESS=0xffb8bb26          # Success states (Gruvbox green)
export STATE_WARNING=0xfffabd2f          # Warning states (Gruvbox yellow)
export STATE_CAUTION=0xfffabd2f          # Medium warning level (Gruvbox yellow)
export STATE_ERROR=0xfffb4934            # Error states (Gruvbox red)
export STATE_INFO=0xff458588             # Informational states (Gruvbox blue)

#===============================================================================
# BORDER COLORS (dividers, outlines)
#===============================================================================

export BORDER_PRIMARY=0xffa89984          # Main borders (Gruvbox gray)
export BORDER_SECONDARY=0xff665c54        # Subtle borders (Gruvbox dark4)
export BORDER_FOCUS=0xff83a598            # Focus outlines (Gruvbox aqua)
export BORDER_DIVIDER=0xff504945          # Section separators (Gruvbox dark2)

#===============================================================================
# SPECIALIZED SYSTEM COLORS
#===============================================================================

# Workspace states (specific semantic meanings)
export WORKSPACE_FOCUSED=0x9983a598       # Currently focused workspace with focused app (semi-transparent aqua)
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
