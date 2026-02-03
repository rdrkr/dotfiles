#!/bin/bash
title="$1"
body="$2"

if [[ -n "${TMUX}" ]]; then
  printf "\ePtmux;\e\e]777;notify;%s;%s\a\e\\" "${title}" "${body}"
else
  printf "\e]777;notify;%s;%s\a" "${title}" "${body}"
fi
