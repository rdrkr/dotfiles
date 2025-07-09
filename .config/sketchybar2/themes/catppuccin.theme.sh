#!/usr/bin/env sh

# Catppuccin Macchiato Theme - Semantic Version
# Industry-standard semantic naming with Catppuccin color values

#===============================================================================
# SURFACE COLORS (backgrounds, cards, overlays)
#===============================================================================

export SURFACE_BASE=0xff24273a            # Main app background (Catppuccin base)
export SURFACE_CONTAINER_PRIMARY=0x903c3e4f    # Primary section backgrounds (Catppuccin surface0)
export SURFACE_CONTAINER_SECONDARY=0x90494d64  # Secondary section backgrounds (Catppuccin surface1)
export SURFACE_OVERLAY=0xff1e2030         # Modal/popup backgrounds (Catppuccin mantle)
export SURFACE_ELEVATED=0xff363a4f        # Raised card backgrounds (Catppuccin surface2)

#===============================================================================
# CONTENT COLORS (text, icons)
#===============================================================================

export CONTENT_PRIMARY=0xffcad3f5         # Main content text and icons (Catppuccin text)
export CONTENT_SECONDARY=0xffbcc0cc       # Supporting content (Catppuccin subtext1)
export CONTENT_TERTIARY=0xffa5adcb        # Subtle/disabled content (Catppuccin subtext0)
export CONTENT_INVERSE=0xff181926         # Content on colored backgrounds (Catppuccin base)
export CONTENT_DISABLED=0xff939ab7        # Disabled content state (Catppuccin overlay2)

#===============================================================================
# INTERACTIVE COLORS (buttons, links, controls)
#===============================================================================

export INTERACTIVE_PRIMARY=0xff8aadf4     # Primary brand actions and focus (Catppuccin blue)
export INTERACTIVE_SECONDARY=0xffc6a0f6   # Secondary actions (Catppuccin mauve)
export INTERACTIVE_SELECTED=0xffcad3f5    # Selected/active items (Catppuccin text)

export INTERACTIVE_HOVER=0x60cad3f5       # Hover states (Catppuccin text with transparency)
export INTERACTIVE_ACTIVE=0x808aadf4      # Pressed states (Catppuccin blue with transparency)
export INTERACTIVE_DISABLED=0x40939ab7    # Disabled states (Catppuccin overlay2)
export INTERACTIVE_FOCUS=0xff8aadf4       # Focus outlines (Catppuccin blue)

#===============================================================================
# STATE COLORS (alerts, status, semantic states)
#===============================================================================

export STATE_SUCCESS=0xffa6da95          # Success states (Catppuccin green)
export STATE_WARNING=0xffeed49f          # Warning states (Catppuccin yellow)
export STATE_CAUTION=0xfff5c2e7          # Medium warning level (Catppuccin pink)
export STATE_ERROR=0xffed8796            # Error states (Catppuccin red)
export STATE_INFO=0xff8aadf4             # Informational states (Catppuccin blue)

#===============================================================================
# BORDER COLORS (dividers, outlines)
#===============================================================================

export BORDER_PRIMARY=0xff6e738d          # Main borders (Catppuccin overlay1)
export BORDER_SECONDARY=0xff5b6078        # Subtle borders (Catppuccin overlay0)
export BORDER_FOCUS=0xff8aadf4            # Focus outlines (Catppuccin blue)
export BORDER_DIVIDER=0xff494d64          # Section separators (Catppuccin surface1)

#===============================================================================
# SPECIALIZED SYSTEM COLORS
#===============================================================================

# Workspace states (specific semantic meanings)
export WORKSPACE_FOCUSED=0x998aadf4       # Currently focused workspace with focused app (semi-transparent blue)
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
export TRANSPARENT=0x00000000              # Transparent background for main bar
export POPUP_BACKGROUND_COLOR=$SURFACE_OVERLAY
export POPUP_SHADOW_COLOR=0x60000000


