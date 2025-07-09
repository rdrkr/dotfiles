#!/usr/bin/env sh

# Apple Logo and Popup Menu
# This creates the Apple logo with a popup menu

# Font is now defined in theme
APPLE="󰀵"
ABOUT="󰋽"
PREFERENCES="󰍉"
ACTIVITY="󱣳"
LOCK="󰍁"
REBOOT="󰜉"
SHUTDOWN="󰐥"

POPUP_OFF="sketchybar --set apple.logo popup.drawing=off"
POPUP_CLICK_SCRIPT="sketchybar --set \$NAME popup.drawing=toggle"

# Apple logo main item
sketchybar --add item apple.logo left \
           --set apple.logo \
           icon=$APPLE \
           icon.font="MesloLGS Nerd Font:Black:16.0" \
           icon.color=$STATE_SUCCESS \
           background.drawing=off \
           label.drawing=off \
           padding_left=10 \
           padding_right=4 \
           script="$PLUGIN_DIR/app/apple.sh" \
           --subscribe apple.logo mouse.entered \
                                  mouse.exited \
                                  mouse.exited.global

# Apple popup menu items  
sketchybar --add item apple.about popup.apple.logo \
           --set apple.about \
           icon=$ABOUT \
           label="About" \
           padding_right=12 \
           click_script="alacritty --title 'About This Mac' -e sh -c 'neofetch; echo; echo \"Press any key to close...\"; read -n 1'; $POPUP_OFF"

sketchybar --add item apple.prefs popup.apple.logo \
           --set apple.prefs \
           icon=$PREFERENCES \
           label="Preferences" \
           padding_right=12 \
           click_script="open -a 'System Preferences'; $POPUP_OFF"

sketchybar --add item apple.activity popup.apple.logo \
           --set apple.activity \
           icon=$ACTIVITY \
           label="Activity" \
           padding_right=12 \
           click_script="open -a 'Activity Monitor'; $POPUP_OFF"

sketchybar --add item apple.lock popup.apple.logo \
           --set apple.lock \
           icon=$LOCK \
           label="Lock Screen" \
           padding_right=12 \
           click_script="pmset displaysleepnow; $POPUP_OFF"

sketchybar --add item apple.reboot popup.apple.logo \
           --set apple.reboot \
           icon=$REBOOT \
           label="Restart" \
           padding_right=12 \
           click_script="osascript -e 'tell app \"System Events\" to restart'; $POPUP_OFF"

sketchybar --add item apple.shutdown popup.apple.logo \
           --set apple.shutdown \
           icon=$SHUTDOWN \
           label="Shut Down" \
           padding_right=12 \
           click_script="osascript -e 'tell app \"System Events\" to shut down'; $POPUP_OFF" 