#!/usr/bin/env bash

# Icon mapping function for SketchyBar using sketchybar-app-font
# Uses font ligatures for beautiful app icons

function __icon_map() {
    case "$1" in
    # === BROWSERS ===
    "Google Chrome" | "Google Chrome Canary" | "Chromium")
        icon_result=":google_chrome:"
        ;;
    "Safari")
        icon_result=":safari:"
        ;;
    "Firefox" | "Firefox Developer Edition" | "Firefox Nightly")
        icon_result=":firefox:"
        ;;
    "Arc")
        icon_result=":arc:"
        ;;

    # === CODE EDITORS & DEVELOPMENT ===
    "Cursor")
        icon_result=":cursor:"
        ;;
    "Zed")
        icon_result=":zed:"
        ;;
    "Visual Studio Code" | "VSCode" | "Code" | "Code - Insiders")
        icon_result=":code:"
        ;;
    "Windsurf")
        icon_result=":windsurf:"
        ;;
    "Emacs")
        icon_result=":emacs:"
        ;;
    "Xcode")
        icon_result=":xcode:"
        ;;
    "WebStorm" | "IntelliJ IDEA")
        icon_result=":intellij:"
        ;;

    # === TERMINALS ===
    "Warp")
        icon_result=":warp:"
        ;;
    "Terminal" | "iTerm2")
        icon_result=":terminal:"
        ;;
    "Alacritty")
        icon_result=":alacritty:"
        ;;

    # === AI & CHAT ===
    "ChatGPT")
        icon_result="󰭹"
        ;;
    "Google Gemini")
        icon_result="✨"
        ;;
    "Google Chat")
        icon_result="💬"
        ;;
    "Claude")
        icon_result=":claude:"
        ;;

    # === PRODUCTIVITY & OFFICE ===
    "Fantastical" | "Calendar")
        icon_result=":calendar:"
        ;;
    "Numbers")
        icon_result=":numbers:"
        ;;
    "Pages")
        icon_result=":pages:"
        ;;
    "Keynote")
        icon_result=":keynote:"
        ;;
    "Microsoft Word")
        icon_result=":microsoft_word:"
        ;;
    "Microsoft Excel")
        icon_result=":microsoft_excel:"
        ;;
    "Microsoft PowerPoint")
        icon_result=":microsoft_powerpoint:"
        ;;
    "Notion")
        icon_result=":notion:"
        ;;
    "Obsidian")
        icon_result=":obsidian:"
        ;;
    "Notes")
        icon_result=":notes:"
        ;;

    # === COMMUNICATION & EMAIL ===
    "Spark Desktop" | "Spark")
        icon_result=":spark:"
        ;;
    "Messages" | "Nachrichten")
        icon_result=":messages:"
        ;;
    "Discord" | "Discord Canary" | "Discord PTB")
        icon_result=":discord:"
        ;;
    "Slack")
        icon_result=":slack:"
        ;;
    "WhatsApp")
        icon_result=":whats_app:"
        ;;
    "zoom.us" | "Zoom")
        icon_result=":zoom:"
        ;;
    "FaceTime")
        icon_result=":facetime:"
        ;;
    "Skype")
        icon_result=":skype:"
        ;;

    # === SYSTEM & UTILITIES ===
    "1Password")
        icon_result=":one_password:"
        ;;
    "System Preferences" | "System Settings")
        icon_result=":system_preferences:"
        ;;
    "Activity Monitor")
        icon_result=":activity_monitor:"
        ;;
    "Stats")
        icon_result=":stats:"
        ;;
    "BuhoCleaner")
        icon_result=":buho_cleaner:"
        ;;
    "Tailscale")
        icon_result=":tailscale:"
        ;;
    "OrbStack")
        icon_result=":orbstack:"
        ;;
    "AeroSpace")
        icon_result=":aerospace:"
        ;;
    "Finder")
        icon_result=":finder:"
        ;;
    "App Store")
        icon_result=":app_store:"
        ;;

    # === MEDIA & ENTERTAINMENT ===
    "Spotify")
        icon_result=":spotify:"
        ;;
    "GarageBand")
        icon_result=":garage_band:"
        ;;
    "iMovie")
        icon_result=":imovie:"
        ;;
    "VLC")
        icon_result=":vlc:"
        ;;
    "Final Cut Pro")
        icon_result=":final_cut_pro:"
        ;;

    # === DEVELOPMENT TOOLS ===
    "GitHub Desktop")
        icon_result=":github_desktop:"
        ;;
    "Docker" | "Docker Desktop")
        icon_result=":docker:"
        ;;
    "Postman")
        icon_result=":postman:"
        ;;

    # === DESIGN & GRAPHICS ===
    "Photoshop" | "Adobe Photoshop")
        icon_result=":photoshop:"
        ;;
    "Illustrator" | "Adobe Illustrator")
        icon_result=":illustrator:"
        ;;
    "SF Symbols")
        icon_result=":sf_symbols:"
        ;;

    # === UTILITIES ===
    "Livebook")
        icon_result=":livebook:"
        ;;
    "Factory Bridge")
        icon_result=":factory_bridge:"
        ;;

    # === FALLBACK ===
    *)
        icon_result=":default:"
        ;;
    esac
}

# Call the function and echo the result
__icon_map "$1"
echo "$icon_result"