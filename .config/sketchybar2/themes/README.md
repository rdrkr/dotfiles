# SketchyBar Theme System

A modern, semantic color theme system for SketchyBar with industry-standard naming conventions.

## 🎨 Design Philosophy

### Semantic Naming

Colors are named by **purpose**, not appearance:

```bash
# ✅ Purpose-based (clear intent)
TEXT_PRIMARY, BACKGROUND_SECONDARY, FEEDBACK_ERROR, ACCENT_PRIMARY

# ❌ Appearance-based (unclear usage)
WHITE, GRAY, RED, BLUE
```

### Theme Independence

- **Same code works across all themes** - switch themes without changing configuration
- **Automatic adaptation** - colors change based on semantic meaning
- **Consistent behavior** - similar purposes always look similar

## 🏗️ Color Architecture

### **Surface Colors** (Backgrounds & Layers)

```bash
BACKGROUND_PRIMARY      # Main app background
BACKGROUND_SECONDARY    # Card/section backgrounds
BACKGROUND_TERTIARY     # Subtle section backgrounds
SURFACE_OVERLAY         # Modal/popup backgrounds
SURFACE_ELEVATED        # Raised card backgrounds
```

### **Content Colors** (Text & Icons)

```bash
TEXT_PRIMARY           # Main content text
TEXT_SECONDARY         # Supporting text
TEXT_TERTIARY          # Subtle/disabled text
TEXT_INVERSE           # Text on colored backgrounds
ICON_PRIMARY           # Main icons
ICON_SECONDARY         # Supporting icons
```

### **Interactive Colors** (Actions & Controls)

```bash
ACCENT_PRIMARY         # Primary brand actions
ACCENT_SECONDARY       # Secondary actions
INTERACTIVE_HOVER      # Hover states
INTERACTIVE_ACTIVE     # Pressed states
INTERACTIVE_DISABLED   # Disabled states
INTERACTIVE_FOCUS      # Focus outlines
```

### **Feedback Colors** (Status & Alerts)

```bash
FEEDBACK_SUCCESS       # Success states (✅)
FEEDBACK_WARNING       # Warning states (⚠️)
FEEDBACK_ERROR         # Error states (❌)
FEEDBACK_INFO          # Informational states (ℹ️)
```

### **Border Colors** (Dividers & Outlines)

```bash
BORDER_PRIMARY         # Main borders
BORDER_SECONDARY       # Subtle borders
BORDER_FOCUS           # Focus outlines
BORDER_DIVIDER         # Section separators
```

## 🎯 Available Themes

- **🌸 Catppuccin** - Modern pastel theme with soothing colors
- **🌃 Tokyo Night** - Dark theme with bright blue accents
- **🍂 Gruvbox** - Warm retro color scheme with earth tones
- **❄️ Nord** - Arctic, minimalist blue palette
- **🧛 Dracula** - Dark theme with vibrant purple accents

## 🛠️ Using Themes

### Basic Usage

```bash
# Cycle to the next theme
../themes/theme-manager.sh

# Apply a specific theme
../themes/theme-manager.sh tokyo-night

# Load the current theme's colors (for scripts)
source <(../themes/theme-manager.sh load)
```

### Shell Integration

Add to your `.zshrc` or `.bashrc`:

```bash
alias theme='~/.config/sketchybar/themes/theme-manager.sh'
```

Then use: `theme` to cycle, or `theme nord` to apply a specific theme.

## 🆕 Creating New Themes

Creating a new theme is simple and requires no manual script editing. The theme manager will automatically discover any valid theme file.

### Step 1: Copy Template

All theme files must follow the `<name>.theme.sh` naming convention.

```bash
cp template.sh my-awesome-theme.theme.sh
```

### Step 2: Customize Colors

Edit your new `my-awesome-theme.theme.sh` file and change the color values to match your desired palette:

```bash
# Example: Ocean theme
export BACKGROUND_PRIMARY=0xff0f1419      # Deep ocean blue
export TEXT_PRIMARY=0xffe6e1cf            # Light sand
export ACCENT_PRIMARY=0xff36a3d9          # Ocean blue
export FEEDBACK_SUCCESS=0xff7fd962        # Sea green
export FEEDBACK_ERROR=0xfff07178          # Coral red
```

### Step 3: Apply Your Theme

Your theme is now instantly available. Apply it using the `theme-manager.sh` script:

```bash
../themes/theme-manager.sh my-awesome-theme
```

The theme manager automatically lists, validates, and manages your new theme.

## ✅ Theme Validation

Validate your theme has all required colors:

```bash
./validate-themes.sh
```

This ensures your theme is complete and compatible.

## 📋 Required Colors

Every theme must define these semantic colors:

### Core Requirements

- **Surfaces**: `BACKGROUND_PRIMARY`, `BACKGROUND_SECONDARY`, `BACKGROUND_TERTIARY`
- **Content**: `TEXT_PRIMARY`, `TEXT_SECONDARY`, `ICON_PRIMARY`
- **Interactive**: `ACCENT_PRIMARY`, `INTERACTIVE_HOVER`, `INTERACTIVE_FOCUS`
- **Feedback**: `FEEDBACK_SUCCESS`, `FEEDBACK_WARNING`, `FEEDBACK_ERROR`
- **Borders**: `BORDER_PRIMARY`, `BORDER_FOCUS`

### System Integration

- **Status**: `STATUS_SUCCESS`, `STATUS_WARNING`, `STATUS_ERROR`
- **Workspaces**: `WORKSPACE_ACTIVE`, `WORKSPACE_HOVER`
- **SketchyBar**: `TRANSPARENT`, `ICON_COLOR`, `LABEL_COLOR`
- **Typography**: `FONT`, `FONT_FAMILY_PRIMARY`, `FONT_SIZE_*`

## 🎨 Design Guidelines

### Color Accessibility

- Maintain **4.5:1 contrast ratio** for text
- Test with **color blindness simulators**
- Use **semantic names** to support accessibility tools

### Visual Consistency

- Similar purposes should have **similar brightness/saturation**
- `ACCENT_PRIMARY` should reflect **brand identity**
- `FEEDBACK_*` colors should follow **universal conventions**

### Brand Considerations

- **Primary accent** represents your brand
- **Success/Error** colors follow standard conventions (green/red)
- **Backgrounds** should support comfortable long-term viewing

## 🚀 Advanced Features

### Dynamic Loading

Themes are loaded dynamically without restart:

```bash
# Themes reload automatically via theme-manager.sh
source <(~/.config/sketchybar/themes/theme-manager.sh load)
```

### System Integration

Semantic colors automatically integrate with:

- **Battery status** (charging=success, low=error)
- **CPU monitoring** (high usage=warning, normal=success)
- **Memory monitoring** (high usage=warning)
- **Temperature monitoring** (high temp=error)

### Multi-State Support

Colors adapt to different states:

```bash
# Configuration stays the same
icon.color=$STATUS_SUCCESS

# Colors adapt based on theme:
# Catppuccin: STATUS_SUCCESS = soft green (#a6da95)
# Tokyo Night: STATUS_SUCCESS = bright green (#9ece6a)
# Gruvbox: STATUS_SUCCESS = warm green (#b8bb26)
```

## 🔄 Recent Improvements (2025)

### Performance & Maintainability Updates

- **🧹 Code cleanup**: Removed 37 unused legacy variables from all themes
- **🎨 Workspace highlighting**: Fixed `WORKSPACE_ACTIVE` color transparency for proper visual feedback
- **📝 Font system**: Added consistent `FONT` variable support across all themes
- **⚡ Performance**: Reduced theme file sizes by ~25% for faster loading
- **🛠️ Maintainability**: Simplified codebase with only actively used variables

### What Was Fixed

- **Workspace Colors**: `WORKSPACE_ACTIVE` now uses semi-transparent blue (`0x998aadf4`) for proper highlighting
- **Font Integration**: All themes now properly define `FONT="$FONT_FAMILY_PRIMARY"` for SketchyBar
- **Variable Cleanup**: Removed unused compatibility variables while keeping essential aliases
- **Cross-theme Consistency**: All 5 themes now have identical structure and functionality

### Removed Legacy Variables

```bash
# These variables were removed as they were unused:
BLACK, WHITE, RED, GREEN, BLUE, ORANGE, MAGENTA, GREY
BAR_COLOR, BACKGROUND_3, HOVER_COLOR, ACTIVE_GLOW
GLASS_LIGHT, GLASS_DARK, BATTERY_LOW, CPU_HIGH
GRADIENT_START, SHADOW_COLOR, ICON_HIGHLIGHT
```

### Kept Essential Variables

```bash
# Only variables actually used by SketchyBar are kept:
TRANSPARENT, ICON_COLOR, LABEL_COLOR, FONT
BACKGROUND_1, BACKGROUND_2, POPUP_BACKGROUND_COLOR
ACCENT_COLOR, SUCCESS_COLOR, WARNING_COLOR, ERROR_COLOR
WORKSPACE_ACTIVE, WORKSPACE_INACTIVE, BORDER_FOCUS
```

## 🔧 Technical Details

### File Structure

```text
themes/
├── README.md                 # This documentation
├── template.sh               # Template for new themes
├── catppuccin.theme.sh       # Catppuccin theme
├── tokyo-night.theme.sh      # Tokyo Night theme
├── gruvbox.theme.sh          # Gruvbox theme
├── nord.theme.sh             # Nord theme
├── dracula.theme.sh          # Dracula theme
├── theme-manager.sh          # Consolidated theme script
└── validate-themes.sh        # Validation script
```

### Color Format

All colors use ARGB hex format:

```bash
export COLOR_NAME=0xffrrggbb
#                   ^^ ^^ ^^
#                   |  |  └─ Blue (00-FF)
#                   |  └──── Green (00-FF)
#                   └─────── Red (00-FF)
# Alpha is always FF (opaque) for solid colors
```

---

**Ready to create amazing themes!** 🎨✨

*This theme system follows industry standards from Google Material Design, Adobe Spectrum, and other leading design systems.*
