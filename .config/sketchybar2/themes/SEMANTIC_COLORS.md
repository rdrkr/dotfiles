# Semantic Color System for SketchyBar

A modern, industry-standard semantic color system designed for maintainability, consistency, and ease of theme creation.

## 🎯 Design Philosophy

### Semantic Naming Over Appearance

Colors are named by **purpose**, not appearance:

```bash
# ✅ Purpose-based (clear intent)
CONTENT_PRIMARY, INTERACTIVE_PRIMARY, STATE_SUCCESS, SEGMENT_PRIMARY

# ❌ Appearance-based (unclear usage)  
WHITE, GRAY, RED, BLUE
```

### Universal Theme Compatibility

- **Same configuration works across all themes**
- **Automatic color adaptation** based on semantic meaning
- **Consistent behavior** - similar purposes always look similar

## 🏗️ New Semantic Color Architecture

### **Surface Colors** (Backgrounds & Containers)

```bash
SURFACE_BASE                  # Main app background
SURFACE_CONTAINER_PRIMARY     # Primary section backgrounds  
SURFACE_CONTAINER_SECONDARY   # Secondary section backgrounds
SURFACE_OVERLAY               # Modal/popup backgrounds
SURFACE_ELEVATED              # Raised card backgrounds
SEGMENT_PRIMARY               # Primary segment backgrounds (visual grouping)
SEGMENT_SECONDARY             # Secondary segment backgrounds
```

### **Content Colors** (Text & Icons - Unified System)

```bash
CONTENT_PRIMARY        # Main content text and icons
CONTENT_SECONDARY      # Supporting content
CONTENT_TERTIARY       # Subtle/disabled content
CONTENT_INVERSE        # Content on colored backgrounds
CONTENT_DISABLED       # Disabled content state
```

### **Interactive Colors** (Actions & Controls)

```bash
INTERACTIVE_PRIMARY    # Primary brand actions and focus
INTERACTIVE_SECONDARY  # Secondary actions
INTERACTIVE_SELECTED   # Selected/active items
INTERACTIVE_HOVER      # Hover states
INTERACTIVE_ACTIVE     # Pressed states
INTERACTIVE_DISABLED   # Disabled states
INTERACTIVE_FOCUS      # Focus outlines
```

### **State Colors** (Status & Feedback)

```bash
STATE_SUCCESS          # Success states (✅)
STATE_WARNING          # Warning states (⚠️)
STATE_CAUTION          # Medium warning level (⚡)
STATE_ERROR            # Error states (❌)
STATE_INFO             # Informational states (ℹ️)
```

### **Workspace Colors** (Specific Semantic Meanings)

```bash
WORKSPACE_FOCUSED      # Currently focused workspace with focused app
WORKSPACE_ACTIVE       # Active workspace (current but no focused app)
WORKSPACE_UNFOCUSED    # Inactive workspaces
WORKSPACE_OCCUPIED     # Workspaces with windows
WORKSPACE_EMPTY        # Empty workspaces
```

### **Border Colors** (Dividers & Outlines)

```bash
BORDER_PRIMARY         # Main borders
BORDER_SECONDARY       # Subtle borders
BORDER_FOCUS           # Focus outlines
BORDER_DIVIDER         # Section separators
```

## 📋 Usage Examples

### Basic Configuration

```bash
# Segment backgrounds
sketchybar --set my_segment background.color=$SEGMENT_PRIMARY

# Content styling
sketchybar --set my_item icon.color=$CONTENT_PRIMARY \
                         label.color=$CONTENT_PRIMARY

# Interactive states
sketchybar --set my_button background.color=$INTERACTIVE_PRIMARY \
                           label.color=$CONTENT_INVERSE

# Status indication
if [ "$cpu_usage" -gt 80 ]; then
    COLOR=$STATE_ERROR      # High CPU - red
elif [ "$cpu_usage" -gt 60 ]; then
    COLOR=$STATE_WARNING    # Medium-high CPU - orange
elif [ "$cpu_usage" -gt 40 ]; then
    COLOR=$STATE_CAUTION    # Medium CPU - yellow
else
    COLOR=$STATE_SUCCESS    # Low CPU - green
fi
```

### Workspace Configuration

```bash
# Different workspace states
if [ "$workspace" = "$current_workspace" ]; then
    if [ "$has_focused_app" = "true" ]; then
        BG_COLOR=$WORKSPACE_FOCUSED     # Currently focused with app
    else
        BG_COLOR=$WORKSPACE_ACTIVE      # Active but no focused app
    fi
else
    BG_COLOR=$WORKSPACE_UNFOCUSED       # Inactive workspace
fi
```

## 🎯 Clean Semantic System

### Pure Semantic Approach

The system now uses **only** semantic color names - no legacy variables:

```bash
# All configurations use semantic names
icon.color=$CONTENT_PRIMARY
label.color=$CONTENT_PRIMARY
background.color=$SEGMENT_PRIMARY

# Status-based color assignment
if [ "$cpu_usage" -gt 80 ]; then
    COLOR=$STATE_ERROR
elif [ "$cpu_usage" -gt 40 ]; then
    COLOR=$STATE_CAUTION
else
    COLOR=$STATE_SUCCESS
fi
```

### Variable Migration Complete

```bash
# Old names → New semantic names (migration completed)
TEXT_PRIMARY          → CONTENT_PRIMARY
ICON_PRIMARY          → CONTENT_PRIMARY  
ACCENT_PRIMARY        → INTERACTIVE_PRIMARY
FEEDBACK_SUCCESS      → STATE_SUCCESS
BACKGROUND_1          → SEGMENT_PRIMARY
WORKSPACE_ACTIVE      → WORKSPACE_FOCUSED
```

## 🎨 Theme-Specific Color Examples

### STATE_SUCCESS Across Themes

```bash
# Catppuccin: Soft, pastel green
STATE_SUCCESS=0xffa6da95

# Tokyo Night: Bright, vibrant green  
STATE_SUCCESS=0xff9ece6a

# Gruvbox: Warm, earthy green
STATE_SUCCESS=0xffb8bb26

# Nord: Cool, arctic green
STATE_SUCCESS=0xffa3be8c

# Dracula: Vivid, electric green
STATE_SUCCESS=0xff50fa7b
```

### INTERACTIVE_PRIMARY Across Themes

```bash
# Catppuccin: Gentle blue
INTERACTIVE_PRIMARY=0xff8aadf4

# Tokyo Night: Electric blue
INTERACTIVE_PRIMARY=0xff7aa2f7

# Gruvbox: Earthy aqua
INTERACTIVE_PRIMARY=0xff83a598

# Nord: Frost blue
INTERACTIVE_PRIMARY=0xff5e81ac

# Dracula: Vibrant purple
INTERACTIVE_PRIMARY=0xffbd93f9
```

## ✨ Key Benefits

### 1. **Theme Independence**

Configuration code works across all themes without modification.

### 2. **Clear Intent**

Variable names immediately communicate their purpose and usage context.

### 3. **Consistent Behavior**  

Similar UI elements look appropriately similar across different themes.

### 4. **Easy Theme Creation**

Logical color categories make it intuitive to assign colors when creating new themes.

### 5. **Maintainable Code**

Semantic names make code self-documenting and easier to understand.

### 6. **Future-Proof**

Adding new themes or color variations doesn't require configuration changes.

## 🛠️ Implementation Details

### Color Format

All colors use ARGB hex format:

```bash
export COLOR_NAME=0xffrrggbb
#                   ^^ ^^ ^^
#                   |  |  └─ Blue (00-FF)
#                   |  └──── Green (00-FF)  
#                   └─────── Red (00-FF)
# Alpha channel (ff = opaque, lower values = transparent)
```

### Variable Structure

```bash
# Primary semantic definitions
export SURFACE_BASE=0xff1a1b26
export CONTENT_PRIMARY=0xffc0caf5
export INTERACTIVE_PRIMARY=0xff7aa2f7

# Backward compatibility aliases
export BACKGROUND_PRIMARY=$SURFACE_BASE
export TEXT_PRIMARY=$CONTENT_PRIMARY
export ACCENT_PRIMARY=$INTERACTIVE_PRIMARY
```

---

**The semantic color system provides a robust foundation for consistent, maintainable, and beautiful SketchyBar themes.** 🎨✨

*This system follows industry standards from Google Material Design, Adobe Spectrum, Apple Human Interface Guidelines, and other leading design systems.*
