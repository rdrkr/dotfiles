#!/usr/bin/env sh

# Semantic Theme Template (Industry Standard)
# Based on Material Design, Adobe Spectrum, Atlassian, and Salesforce standards
# Names describe PURPOSE, not appearance

#===============================================================================
# SURFACE COLORS (backgrounds, cards, overlays)
#===============================================================================

export SURFACE_BASE=0xff000000            # Main app background
export SURFACE_CONTAINER_PRIMARY=0xff111111    # Primary section backgrounds  
export SURFACE_CONTAINER_SECONDARY=0xff222222  # Secondary section backgrounds
export SURFACE_OVERLAY=0xff333333         # Modal/popup backgrounds
export SURFACE_ELEVATED=0xff444444        # Raised card backgrounds

#===============================================================================
# CONTENT COLORS (text, icons)
#===============================================================================

export CONTENT_PRIMARY=0xffffffff         # Main content text and icons
export CONTENT_SECONDARY=0xffcccccc       # Supporting content
export CONTENT_TERTIARY=0xff888888        # Subtle/disabled content
export CONTENT_INVERSE=0xff000000         # Content on colored backgrounds
export CONTENT_DISABLED=0xff555555        # Disabled content state

#===============================================================================
# INTERACTIVE COLORS (buttons, links, controls)
#===============================================================================

export INTERACTIVE_PRIMARY=0xff007AFF     # Primary brand actions and focus
export INTERACTIVE_SECONDARY=0xff5856d6   # Secondary actions
export INTERACTIVE_SELECTED=0xffffffff    # Selected/active items

export INTERACTIVE_HOVER=0x60ffffff       # Hover states
export INTERACTIVE_ACTIVE=0x80ffffff      # Pressed states
export INTERACTIVE_DISABLED=0x40888888    # Disabled states
export INTERACTIVE_FOCUS=0xff007AFF       # Focus outlines

#===============================================================================
# STATE COLORS (alerts, status, semantic states)
#===============================================================================

export STATE_SUCCESS=0xff34c759          # Success states
export STATE_WARNING=0xffff9f0a          # Warning states  
export STATE_CAUTION=0xffff9f0a          # Medium warning level
export STATE_ERROR=0xffff3b30            # Error states
export STATE_INFO=0xff007AFF             # Informational states

#===============================================================================
# BORDER COLORS (dividers, outlines)
#===============================================================================

export BORDER_PRIMARY=0xff555555          # Main borders
export BORDER_SECONDARY=0xff333333        # Subtle borders
export BORDER_FOCUS=0xff007AFF            # Focus outlines
export BORDER_DIVIDER=0xff222222          # Section separators

#===============================================================================
# SPECIALIZED SYSTEM COLORS
#===============================================================================

# Workspace states (specific semantic meanings)
export WORKSPACE_FOCUSED=0x99007AFF       # Currently focused workspace with focused app
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
export POPUP_BACKGROUND_COLOR=$SURFACE_OVERLAY
export POPUP_SHADOW_COLOR=0x60000000

# System utilities
export TRANSPARENT=0x00000000            # Transparent background