#!/usr/bin/env sh

# Dracula Theme - Semantic Version
# Industry-standard semantic naming with Dracula color values

#===============================================================================
# SURFACE COLORS (backgrounds, cards, overlays)
#===============================================================================

export SURFACE_BASE=0xff282a36            # Main app background (Dracula background)
export SURFACE_CONTAINER_PRIMARY=0x9044475a    # Primary section backgrounds (Dracula current-line)
export SURFACE_CONTAINER_SECONDARY=0x906272a4  # Secondary section backgrounds (Dracula selection)
export SURFACE_OVERLAY=0xff21222c         # Modal/popup backgrounds (Dracula darker)
export SURFACE_ELEVATED=0xff44475a        # Raised card backgrounds (Dracula current-line)

#===============================================================================
# CONTENT COLORS (text, icons)
#===============================================================================

export CONTENT_PRIMARY=0xfff8f8f2         # Main content text and icons (Dracula foreground)
export CONTENT_SECONDARY=0xffe2e4e8       # Supporting content (Dracula comment lighter)
export CONTENT_TERTIARY=0xff6272a4        # Subtle/disabled content (Dracula comment)
export CONTENT_INVERSE=0xff282a36         # Content on colored backgrounds (Dracula background)
export CONTENT_DISABLED=0xff6272a4        # Disabled content state (Dracula comment)

#===============================================================================
# INTERACTIVE COLORS (buttons, links, controls)
#===============================================================================

export INTERACTIVE_PRIMARY=0xffbd93f9     # Primary brand actions and focus (Dracula purple)
export INTERACTIVE_SECONDARY=0xffff79c6   # Secondary actions (Dracula pink)
export INTERACTIVE_SELECTED=0xfff8f8f2    # Selected/active items (Dracula foreground)

export INTERACTIVE_HOVER=0x60f8f8f2       # Hover states (Dracula foreground with transparency)
export INTERACTIVE_ACTIVE=0x80bd93f9      # Pressed states (Dracula purple with transparency)
export INTERACTIVE_DISABLED=0x406272a4    # Disabled states (Dracula comment)
export INTERACTIVE_FOCUS=0xffbd93f9       # Focus outlines (Dracula purple)

#===============================================================================
# STATE COLORS (alerts, status, semantic states)
#===============================================================================

export STATE_SUCCESS=0xff50fa7b          # Success states (Dracula green)
export STATE_WARNING=0xfff1fa8c          # Warning states (Dracula yellow)
export STATE_CAUTION=0xfff1fa8c          # Medium warning level (Dracula yellow)
export STATE_ERROR=0xffff5555            # Error states (Dracula red)
export STATE_INFO=0xff8be9fd             # Informational states (Dracula cyan)

#===============================================================================
# BORDER COLORS (dividers, outlines)
#===============================================================================

export BORDER_PRIMARY=0xff6272a4          # Main borders (Dracula comment)
export BORDER_SECONDARY=0xff44475a        # Subtle borders (Dracula current-line)
export BORDER_FOCUS=0xffbd93f9            # Focus outlines (Dracula purple)
export BORDER_DIVIDER=0xff44475a          # Section separators (Dracula current-line)

#===============================================================================
# SPECIALIZED SYSTEM COLORS
#===============================================================================

# Workspace states (specific semantic meanings)
export WORKSPACE_FOCUSED=0x99bd93f9       # Currently focused workspace with focused app (semi-transparent purple)
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
