#!/usr/bin/env bash
osascript -e 'tell application "System Events" to if (get name of every process) contains "AeroSpaceBar" then tell application "AeroSpaceBar" to «event ascrpsbr» "updateOnFocusChanged"'
