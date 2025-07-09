#!/usr/bin/env bash

# SketchyBar Global Configuration
# This file contains all global variables and paths used throughout the configuration

# Core Directories
export SKETCHYBAR_CONFIG="$HOME/.config/sketchybar"
export ITEM_DIR="$SKETCHYBAR_CONFIG/items"
export PLUGIN_DIR="$SKETCHYBAR_CONFIG/plugins"
export SEGMENT_DIR="$SKETCHYBAR_CONFIG/segments"
export THEME_DIR="$SKETCHYBAR_CONFIG/themes"

# Global Padding and Spacing
export PADDINGS=3
export SEGMENT_SPACING=12

# Load Theme and Icons
source <( "$THEME_DIR/theme-manager.sh" load )  # Load current theme colors
source "$SKETCHYBAR_CONFIG/icons.sh"  # Load all defined icons