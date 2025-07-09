# SketchyBar Configuration Principles

This document outlines the core principles that guide the organization of this SketchyBar configuration.

## Core Principles

### 1. **Separation of Concerns**

Each type of file has a specific, well-defined purpose:

- **Main Config (`sketchybarrc`)**: Entry point, orchestrates loading
- **Core Config (`config/`)**: Fundamental settings (bar, defaults, globals, events)
- **Items (`items/`)**: Define what appears on the bar and where
- **Plugins (`plugins/`)**: Provide dynamic content and handle updates
- **Segments (`segments/`)**: Group items visually (brackets)

### 2. **Clear Hierarchy**

```
Configuration Loading Order:
1. Global variables and theme loading
2. Bar appearance and default item settings  
3. Event definitions
4. Item definitions (what appears)
5. Segment groupings (visual organization)
6. Finalization and initialization
```

### 3. **Logical Categorization**

Files are grouped by functionality, not file type:

- **System**: System monitoring, status, hardware-related
- **Workspace**: Aerospace, workspaces, window management  
- **App**: Application-related items and functionality
- **Utils**: Shared utilities and helper scripts

### 4. **Consistent Naming**

- **Items**: `category/function.sh` (e.g., `system/battery.sh`)
- **Plugins**: `category/function_action.sh` (e.g., `system/battery_update.sh`) or `category/function.sh`
- **Segments**: `position/description.sh` (e.g., `right/system_status.sh`)
- **Config**: `purpose.sh` (e.g., `globals.sh`, `defaults.sh`)

### 5. **Minimal Coupling**

- All files load global configuration from one source
- Plugin paths are centralized in globals
- Theme and icon loading is centralized
- Each component can be modified independently

### 6. **Self-Documenting Structure**

The directory structure itself explains the purpose:
```
segments/right/system_status.sh  # Creates a right-side segment for system status
items/system/battery.sh          # Defines the battery item
plugins/system/battery.sh        # Updates battery content
```

### 7. **Maintainability Focus**

- **Easy to locate**: Predictable file locations
- **Easy to modify**: Clear boundaries between components
- **Easy to extend**: Consistent patterns for adding new items
- **Easy to debug**: Isolated component responsibilities

### 8. **Configuration Management**

- **Single source of truth**: Global variables in `config/globals.sh`
- **DRY principle**: No repeated configuration
- **Centralized theming**: All visual aspects controlled from theme files
- **Environment agnostic**: Uses variables for all paths

## Best Practices

### When Adding New Items:

1. **Create the item definition** in appropriate `items/` subdirectory
2. **Create the plugin script** in appropriate `plugins/` subdirectory
3. **Add to relevant segment** or create new segment if needed
4. **Load in main config** following the established order
5. **Use global variables** for all paths and theming

### When Modifying Existing Items:

1. **Identify the component type**: Item definition vs plugin logic
2. **Make changes in the appropriate file**
3. **Test the specific component** in isolation if possible
4. **Verify integration** with related components

### When Debugging:

1. **Check item definition** for basic configuration issues
2. **Check plugin script** for content generation problems  
3. **Check segment definition** for visual grouping issues
4. **Check global config** for path or variable problems

## Anti-Patterns to Avoid

- ❌ **Hardcoding paths** - Use variables from `globals.sh`
- ❌ **Mixing concerns** - Keep item definition separate from content generation
- ❌ **Duplicate configuration** - Use central configuration sources
- ❌ **Inconsistent categorization** - Follow established directory structure
- ❌ **Complex main config** - Keep `sketchybarrc` high-level only

## Future Extensions

This structure supports:
- **Plugin ecosystems**: Easy to add new plugin categories
- **Theme variations**: Centralized theming allows easy theme switching
- **Conditional loading**: Items/segments can be loaded conditionally
- **Modular configuration**: Components can be shared between configurations
- **A/B testing**: Different segments can be swapped easily

## Philosophy

*"The configuration should be as easy to understand as it is to modify. When someone opens a file, its purpose should be immediately clear from both its location and its content."*

This principle drives every organizational decision in this configuration structure.