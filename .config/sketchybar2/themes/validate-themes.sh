#!/usr/bin/env bash

# Theme Validation Script
# Checks that all themes have the required color definitions

# Detect the correct theme directory dynamically
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're running from repo root or themes directory
if [[ "$SCRIPT_DIR" == */themes ]]; then
    # Running from themes directory (or called from themes dir)
    THEME_DIR="$SCRIPT_DIR"
else
    # Running from repo root (CI scenario)
    THEME_DIR="$SCRIPT_DIR/themes"
fi
# Get themes from the theme manager
THEMES=($("$THEME_DIR/theme-manager.sh" list))

# Required core colors that all themes must have
REQUIRED_COLORS=(
    # Surface Colors (backgrounds, cards, overlays)
    "SURFACE_BASE"
    "SURFACE_CONTAINER_PRIMARY"
    "SURFACE_CONTAINER_SECONDARY"
    "SURFACE_OVERLAY"
    "SURFACE_ELEVATED"
    "SEGMENT_PRIMARY"
    "SEGMENT_SECONDARY"

    # Content Colors (text, icons)
    "CONTENT_PRIMARY"
    "CONTENT_SECONDARY"
    "CONTENT_TERTIARY"
    "CONTENT_INVERSE"
    "CONTENT_DISABLED"

    # Interactive Colors (buttons, links, controls)
    "INTERACTIVE_PRIMARY"
    "INTERACTIVE_SECONDARY"
    "INTERACTIVE_SELECTED"
    "INTERACTIVE_HOVER"
    "INTERACTIVE_ACTIVE"
    "INTERACTIVE_DISABLED"
    "INTERACTIVE_FOCUS"

    # State Colors (alerts, status, semantic states)
    "STATE_SUCCESS"
    "STATE_WARNING"
    "STATE_CAUTION"
    "STATE_ERROR"
    "STATE_INFO"

    # Border Colors (dividers, outlines)
    "BORDER_PRIMARY"
    "BORDER_SECONDARY"
    "BORDER_FOCUS"
    "BORDER_DIVIDER"

    # Workspace Colors (workspace states)
    "WORKSPACE_FOCUSED"
    "WORKSPACE_ACTIVE"
    "WORKSPACE_UNFOCUSED"
    "WORKSPACE_OCCUPIED"
    "WORKSPACE_EMPTY"

    # Typography
    "FONT"
    "FONT_FAMILY_PRIMARY"
    "FONT_FAMILY_ICONS"
    "FONT_FAMILY_SYSTEM"
    "FONT_SIZE_SMALL"
    "FONT_SIZE_MEDIUM"
    "FONT_SIZE_LARGE"

    # Essential SketchyBar Variables
    "TRANSPARENT"
    "POPUP_BACKGROUND_COLOR"
    "POPUP_SHADOW_COLOR"
)

# Terminal colors for output (avoid conflicts with theme colors)
TERM_RED='\033[0;31m'
TERM_GREEN='\033[0;32m'
TERM_YELLOW='\033[1;33m'
TERM_BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${TERM_BLUE}🎨 Theme Validation Report${NC}"
echo "=================================================="

TOTAL_ERRORS=0

for theme in "${THEMES[@]}"; do
    echo ""
    echo -e "${TERM_BLUE}Checking theme: ${TERM_YELLOW}$theme${NC}"

    theme_file="$THEME_DIR/$theme.theme.sh"

    if [ ! -f "$theme_file" ]; then
        echo -e "  ${TERM_RED}❌ Theme file not found: $theme_file${NC}"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        continue
    fi

    # Source the theme to check for colors
    source "$theme_file"

    MISSING_COLORS=()

    for color in "${REQUIRED_COLORS[@]}"; do
        # Check if the color variable is defined and not empty
        if [ -z "${!color}" ]; then
            MISSING_COLORS+=("$color")
        fi
    done

    if [ ${#MISSING_COLORS[@]} -eq 0 ]; then
        echo -e "  ${TERM_GREEN}✅ All required colors defined${NC}"
    else
        echo -e "  ${TERM_RED}❌ Missing colors (${#MISSING_COLORS[@]}):${NC}"
        for missing in "${MISSING_COLORS[@]}"; do
            echo -e "     - $missing"
        done
        TOTAL_ERRORS=$((TOTAL_ERRORS + ${#MISSING_COLORS[@]}))
    fi
done

echo ""
echo "=================================================="
if [ $TOTAL_ERRORS -eq 0 ]; then
    echo -e "${TERM_GREEN}🎉 All themes are valid! No errors found.${NC}"
else
    echo -e "${TERM_RED}⚠️  Found $TOTAL_ERRORS validation errors.${NC}"
    echo -e "${TERM_YELLOW}💡 Use the template at themes/_template.sh to fix missing colors.${NC}"
fi

exit $TOTAL_ERRORS
