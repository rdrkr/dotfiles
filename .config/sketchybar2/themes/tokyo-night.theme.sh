#!/usr/bin/env sh

# Tokyo Night Theme - Semantic Version
# Industry-standard semantic naming with Tokyo Night color values

#===============================================================================
# SURFACE COLORS (backgrounds, cards, overlays)
#===============================================================================

export SURFACE_BASE=0xff1a1b26            # Main app background (Tokyo Night bg)
export SURFACE_CONTAINER_PRIMARY=0x9024283b    # Primary section backgrounds (Tokyo Night bg_dark)
export SURFACE_CONTAINER_SECONDARY=0x90414868  # Secondary section backgrounds (Tokyo Night bg_highlight)
export SURFACE_OVERLAY=0xff16161e         # Modal/popup backgrounds (Tokyo Night bg_darker)
export SURFACE_ELEVATED=0xff24283b        # Raised card backgrounds (Tokyo Night bg_dark)

#===============================================================================
# CONTENT COLORS (text, icons)
#===============================================================================

export CONTENT_PRIMARY=0xffc0caf5         # Main content text and icons (Tokyo Night fg)
export CONTENT_SECONDARY=0xffa9b1d6       # Supporting content (Tokyo Night fg_dark)
export CONTENT_TERTIARY=0xff565f89        # Subtle/disabled content (Tokyo Night comment)
export CONTENT_INVERSE=0xff1a1b26         # Content on colored backgrounds (Tokyo Night bg)
export CONTENT_DISABLED=0xff565f89        # Disabled content state (Tokyo Night comment)

#===============================================================================
# INTERACTIVE COLORS (buttons, links, controls)
#===============================================================================

export INTERACTIVE_PRIMARY=0xff7aa2f7     # Primary brand actions and focus (Tokyo Night blue)
export INTERACTIVE_SECONDARY=0xffbb9af7   # Secondary actions (Tokyo Night purple)
export INTERACTIVE_SELECTED=0xffc0caf5    # Selected/active items (Tokyo Night fg)

export INTERACTIVE_HOVER=0x60c0caf5       # Hover states (Tokyo Night fg with transparency)
export INTERACTIVE_ACTIVE=0x807aa2f7      # Pressed states (Tokyo Night blue with transparency)
export INTERACTIVE_DISABLED=0x40565f89    # Disabled states (Tokyo Night comment)
export INTERACTIVE_FOCUS=0xff7aa2f7       # Focus outlines (Tokyo Night blue)

#===============================================================================
# STATE COLORS (alerts, status, semantic states)
#===============================================================================

export STATE_SUCCESS=0xff9ece6a          # Success states (Tokyo Night green)
export STATE_WARNING=0xffe0af68          # Warning states (Tokyo Night yellow)
export STATE_CAUTION=0xffe0af68          # Medium warning level (Tokyo Night yellow)
export STATE_ERROR=0xfff7768e            # Error states (Tokyo Night red)
export STATE_INFO=0xff7dcfff             # Informational states (Tokyo Night cyan)

#===============================================================================
# BORDER COLORS (dividers, outlines)
#===============================================================================

export BORDER_PRIMARY=0xff565f89          # Main borders (Tokyo Night comment)
export BORDER_SECONDARY=0xff3b4261        # Subtle borders (Tokyo Night border)
export BORDER_FOCUS=0xff7aa2f7            # Focus outlines (Tokyo Night blue)
export BORDER_DIVIDER=0xff414868          # Section separators (Tokyo Night bg_highlight)

#===============================================================================
# SPECIALIZED SYSTEM COLORS
#===============================================================================

# Workspace states (specific semantic meanings)
export WORKSPACE_FOCUSED=0x997aa2f7       # Currently focused workspace with focused app (semi-transparent blue)
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